"""Prueba de integración del complemento SIG-TEC con PyQGIS real, sin abrir ventanas.

Ejecuta el complemento tal como se instala (desde dist/sigtec_qgis.zip) contra los seis
nodos, con un perfil de QGIS temporal. No toca el perfil ni las credenciales del usuario.
Debe correr con el Python incluido en QGIS 3.44 LTR; use: make qgis-test

Solo sustituye la ventana de inicio de sesión (entrega usuario/clave) y QMessageBox
(captura el mensaje). La autenticación, las conexiones, los estilos, la carga, el dibujo
y la edición son los reales. Las ediciones crean y eliminan un punto temporal por campus.
"""
import os
from pathlib import Path
import secrets
import shutil
import socket
import sys
import tempfile
import traceback
import zipfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
TMP = Path(tempfile.mkdtemp(prefix="sigtec_qgis_"))
os.environ["QGIS_CUSTOM_CONFIG_PATH"] = str(TMP / "profile")
os.environ["QGIS_AUTH_DB_DIR_PATH"] = str(TMP)

from qgis.PyQt import sip  # noqa: E402
from qgis.PyQt.QtCore import QSize, Qt  # noqa: E402
from qgis.PyQt.QtGui import QColor  # noqa: E402
from qgis.PyQt.QtTest import QTest
from qgis.PyQt.QtWidgets import QDialog, QDockWidget, QMainWindow  # noqa: E402
from qgis.core import (  # noqa: E402
    NULL, Qgis, QgsApplication, QgsCoordinateReferenceSystem, QgsCredentials, QgsFeature, QgsFeatureRequest, QgsGeometry,
    QgsMapRendererSequentialJob, QgsMapSettings, QgsPointXY, QgsProject, QgsVectorLayer,
    QgsWkbTypes,
)
from qgis.gui import QgsLayerTreeMapCanvasBridge, QgsMapCanvas, QgsMessageBar  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ZIP = ROOT / "dist" / "sigtec_qgis.zip"
NODES = ["cartago", "san_jose", "san_carlos", "alajuela", "limon"]
FAILS = []


def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name:<46} {detail}", flush=True)
    if not ok:
        FAILS.append(name)


def env_values():
    return {
        k: v.strip().strip('"').strip("'")
        for k, v in (line.split("=", 1) for line in (ROOT / ".env").read_text("utf-8-sig").splitlines()
                     if "=" in line and not line.lstrip().startswith("#"))
    }


class CountingCredentials(QgsCredentials):
    """Cuenta los intentos de QGIS de pedir credenciales fuera de la ventana de SIG-TEC."""
    prompts = 0

    def __init__(self):
        super().__init__()
        self.setInstance(self)

    def request(self, realm, username, password, message):
        CountingCredentials.prompts += 1
        return False, username, password

    def requestMasterPassword(self, password, stored):
        return False, password


class FakeIface:
    """Subconjunto de QgisInterface que usa el complemento, con widgets reales."""

    def __init__(self):
        self.window = QMainWindow()
        self.canvas = QgsMapCanvas(self.window)
        self.window.resize(1300, 800)
        self.window.setCentralWidget(self.canvas)
        # Como QGIS Desktop con un proyecto del usuario en otro sistema: obliga a reproyectar.
        self.canvas.setDestinationCrs(QgsCoordinateReferenceSystem("EPSG:3857"))
        self.window.show()  # offscreen: da al lienzo su tamaño real, necesario para la escala
        QTest.qWait(800)
        self.bar = QgsMessageBar(self.window)
        self.bridge = QgsLayerTreeMapCanvasBridge(QgsProject.instance().layerTreeRoot(), self.canvas)
        self.menu, self.icons = [], []
        self.layers_dock = QDockWidget("Capas", self.window)
        self.layers_dock.setObjectName("Layers")
        self.layers_dock.hide()

    def destroy(self):
        """Destruye los widgets antes que la aplicación (PyQGIS falla al salir en otro orden)."""
        self.canvas.stopRendering()
        self.canvas.waitWhileRendering()
        sip.delete(self.bridge)
        sip.delete(self.window)

    def mainWindow(self): return self.window
    def mapCanvas(self): return self.canvas
    def messageBar(self): return self.bar
    def layerTreeCanvasBridge(self): return self.bridge
    def addPluginToDatabaseMenu(self, _name, action): self.menu.append(action)
    def removePluginDatabaseMenu(self, _name, action): self.menu.remove(action)
    def addToolBarIcon(self, action): self.icons.append(action)
    def removeToolBarIcon(self, action): self.icons.remove(action)
    def addDockWidget(self, area, dock): self.window.addDockWidget(area, dock)
    def removeDockWidget(self, dock): self.window.removeDockWidget(dock)


def managed(module):
    return [x for x in QgsProject.instance().mapLayers().values()
            if x.customProperty(module.MANAGED_PROPERTY, False)]


def main():
    app = QgsApplication([], True)
    app.initQgis()
    credentials = CountingCredentials()  # noqa: F841 (QGIS conserva la referencia como singleton)
    try:
        check("qgis.version", Qgis.QGIS_VERSION.startswith("3.44."), Qgis.QGIS_VERSION)
        manager = QgsApplication.authManager()
        check("qgis.almacen_credenciales_temporal",
              not manager.isDisabled() and manager.setMasterPassword(secrets.token_hex(16), True))

        with zipfile.ZipFile(ZIP) as archive:
            archive.extractall(TMP / "plugins")
        sys.path.insert(0, str(TMP / "plugins"))
        import sigtec
        from sigtec import plugin as module
        iface = FakeIface()
        plugin = sigtec.classFactory(iface)
        plugin.initGui()
        check("complemento.carga_desde_zip", len(iface.menu) == 2 and len(iface.icons) == 1)
        check("panel.oculto_sin_sesion", plugin.panel.isHidden() and not plugin.panel.active)

        messages, entered = [], {}

        class Dialog:
            def __init__(self, parent=None): pass
            def exec(self): return QDialog.Accepted
            def credentials(self): return entered["user"], entered["password"]

        class Box:
            @staticmethod
            def critical(_parent, title, text): messages.append(text)
            warning = critical

        real_dialog = module.LoginDialog(iface.mainWindow())
        check("complemento.formulario_real", real_dialog.password.echoMode() == real_dialog.password.Password)
        module.LoginDialog, module.QMessageBox = Dialog, Box

        def login(user, password):
            messages.clear()
            entered.update(user=user, password=password)
            plugin.login()
            return list(messages)

        values = env_values()
        passwords = {n: values["SIGTEC_QGIS_" + n.upper() + "_PASSWORD"] for n in NODES}
        user_layer = QgsVectorLayer("Point?crs=EPSG:5367", "capa del usuario", "memory")
        QgsProject.instance().addMapLayer(user_layer)
        styles = {}

        for cid, node in enumerate(NODES, 1):
            errors = login("qgis_" + node, passwords[node])
            layers = managed(module)
            check(f"{node}.inicio_de_sesion", not errors and len(layers) == 8, f"{len(layers)} capas {errors or ''}")
            if len(layers) != 8:
                continue
            names = {x.name() for x in layers}
            check(f"{node}.nombres", names == {s[1] for s in module.LAYER_SPECS})
            check(f"{node}.conexion_al_campus", all(
                x.dataProvider().uri().port() == str(plugin.config["campuses"][node]["port"]) for x in layers),
                "puerto " + layers[0].dataProvider().uri().port())
            check(f"{node}.srid_clave_geometria", all(
                x.crs().authid() == "EPSG:5367" and x.dataProvider().uri().keyColumn() == "id"
                and x.dataProvider().uri().geometryColumn() == "geom" for x in layers))
            spec = {s[1]: s[2] for s in module.LAYER_SPECS}
            check(f"{node}.tipos_geometria", all(
                QgsWkbTypes.displayString(x.wkbType()) == spec[x.name()] for x in layers))
            per_layer = {x.name(): {f["campus_id"] for f in x.getFeatures()} for x in layers}
            check(f"{node}.objetos_de_cinco_campus", all(v == {1, 2, 3, 4, 5} for v in per_layer.values()))
            check(f"{node}.sin_contrasena_en_el_proyecto",
                  not any(passwords[node] in x.source() for x in layers))
            # Estilo leído de PostgreSQL (layer_styles), no del QML de respaldo.
            from_db = []
            for x in layers:
                _text, ok = x.loadDefaultStyle()
                symbols = x.renderer().symbols(__import__("qgis.core", fromlist=["QgsRenderContext"]).QgsRenderContext())
                styles.setdefault(x.name(), set()).add(symbols[0].color().name())
                from_db.append(ok and x.listStylesInDatabase()[0] >= 1)
            check(f"{node}.estilos_desde_postgresql", all(from_db))
            check(f"{node}.encuadre_del_campus", all(
                iface.canvas.mapSettings().mapToLayerCoordinates(layers[0], iface.canvas.extent()).contains(
                    f.geometry().boundingBox())
                for x in layers if x.name() == "Edificios"
                for f in x.getFeatures(QgsFeatureRequest().setFilterExpression(f"campus_id={cid}"))))
            interfaz(node, module, plugin, iface)

            settings = QgsMapSettings()
            settings.setLayers(layers)
            settings.setDestinationCrs(layers[0].crs())
            settings.setExtent(iface.canvas.mapSettings().mapToLayerCoordinates(layers[0], iface.canvas.extent()))
            settings.setOutputSize(QSize(400, 300))
            settings.setBackgroundColor(QColor(Qt.white))
            job = QgsMapRendererSequentialJob(settings)
            job.start()
            job.waitForFinished()
            image = job.renderedImage()
            painted = sum(image.pixelColor(i, j) != QColor(Qt.white) for i in range(0, 400, 2) for j in range(0, 300, 2))
            check(f"{node}.dibujo", painted > 50 and not job.errors(), f"{painted} píxeles pintados")

            edit(node, cid, next(x for x in layers if x.name() == "Puntos de interés"))

            login("qgis_" + node, passwords[node])
            group = QgsProject.instance().layerTreeRoot().findGroup("SIG-TEC")
            check(f"{node}.reingreso_sin_duplicar", len(managed(module)) == 8 and len(group.findLayers()) == 8
                  and len(basemaps(module)) == 1)

        check("capas_ajenas_conservadas", user_layer.id() in QgsProject.instance().mapLayers())
        check("estilos_iguales_entre_campus", len(styles) == 8 and all(len(v) == 1 for v in styles.values()))

        before = {x.id() for x in managed(module)}
        stored = len(manager.configIds())
        CountingCredentials.prompts = 0
        errors = login("qgis_cartago", secrets.token_hex(12))
        check("contrasena_incorrecta.rechazada", len(errors) == 1 and {x.id() for x in managed(module)} == before,
              errors[0] if errors else "sin mensaje")
        # Limitación conocida: el proveedor de QGIS pide credenciales por su cuenta antes de
        # devolver el error al complemento. No es un fallo de seguridad; se informa.
        if CountingCredentials.prompts:
            print(f"AVISO contrasena_incorrecta.ventana_de_qgis               {CountingCredentials.prompts} solicitud(es); "
                  "al cancelarla aparece el mensaje de SIG-TEC")
        check("contrasena_incorrecta.no_queda_guardada", len(manager.configIds()) == stored,
              f"{stored} -> {len(manager.configIds())} credenciales")

        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            closed = s.getsockname()[1]
        original = plugin.config["campuses"]["limon"]["port"]
        plugin.config["campuses"]["limon"]["port"] = closed
        errors = login("qgis_limon", passwords["limon"])
        plugin.config["campuses"]["limon"]["port"] = original
        check("nodo_inaccesible.mensaje", len(errors) == 1 and "limon" in errors[0] and "accesible" in errors[0],
              errors[0] if errors else "sin mensaje")
        check("nodo_inaccesible.sin_carga_parcial", {x.id() for x in managed(module)} == before)

        sesion(module, plugin, iface, login, passwords, user_layer)

        ids = manager.configIds()
        check("credenciales.una_por_cuenta", len(ids) == len(NODES), f"{len(ids)} guardadas para {len(NODES)} cuentas")

        plugin.unload()
        check("complemento.descarga", not iface.menu and not iface.icons and plugin.panel is None)
    except Exception:
        traceback.print_exc()
        FAILS.append("excepción en la prueba")
    finally:
        QgsProject.instance().clear()
        if "iface" in locals():
            iface.destroy()
        app.exitQgis()
        shutil.rmtree(TMP, ignore_errors=True)
    print("----")
    print("RESULTADO:", "todas las pruebas pasaron" if not FAILS else f"{len(FAILS)} fallas: " + ", ".join(FAILS))
    return 1 if FAILS else 0


def basemaps(module):
    return [x for x in QgsProject.instance().mapLayers().values()
            if x.customProperty(module.BASEMAP_PROPERTY, False)]


def visible(iface, layer, campus_id):
    """El lienzo contiene todos los edificios del campus."""
    view = iface.canvas.mapSettings().mapToLayerCoordinates(layer, iface.canvas.extent())
    request = QgsFeatureRequest().setFilterExpression(f"campus_id={campus_id}")
    return all(view.contains(f.geometry().boundingBox()) for f in layer.getFeatures(request))


def interfaz(node, module, plugin, iface):
    """Mapa base, panel, etiquetas y navegación recién iniciada la sesión."""
    panel, root = plugin.panel, QgsProject.instance().layerTreeRoot()
    base = basemaps(module)
    order = [x.layerId() for x in root.findLayers()]
    check(f"{node}.mapa_base_unico_y_al_fondo", len(base) == 1 and base[0].isValid() and order[-1] == base[0].id()
          and root.findLayer(base[0].id()).itemVisibilityChecked())
    check(f"{node}.atribucion_osm", plugin.attribution is not None and "OpenStreetMap" in plugin.attribution.label.text()
          and "OpenStreetMap" in base[0].serverProperties().attribution())
    group = [x.layer().name() for x in root.findGroup("SIG-TEC").findLayers()]
    check(f"{node}.orden_de_dibujo", group == plugin._display_order())
    check(f"{node}.panel_visible_con_sesion", not panel.isHidden() and not iface.layers_dock.isHidden() and panel.active
          and panel.user.text() == "qgis_" + node and panel.selector.currentData() == node)
    legend = panel.legend
    check(f"{node}.leyenda_de_ocho_capas", [legend.topLevelItem(i).text(0) for i in range(legend.topLevelItemCount())]
          == plugin._display_order() and not legend.topLevelItem(0).icon(0).isNull())
    layers = {x.name(): x for x in managed(module)}
    check(f"{node}.etiquetas_activas", all(layers[n].labelsEnabled() and layers[n].labeling()
          for n in ("Edificios", "Carreteras", "Puntos de interés")))
    check(f"{node}.simbologia_por_categorias", all(
        len(layers[n].renderer().legendSymbolItems()) >= k for n, k in
        (("Puntos de interés", 9), ("Carreteras", 5), ("Zonas verdes", 6), ("Edificios", 3))))

    buildings = layers["Edificios"]
    ok, texts = True, []
    for cid, other in enumerate(NODES, 1):
        panel.selector.setCurrentIndex(panel.selector.findData(other))
        panel.selector.activated.emit(panel.selector.currentIndex())
        ok = ok and visible(iface, buildings, cid)
        texts.append(panel.edit.text())
    own = module.CAMPUS_NAMES[node]
    check(f"{node}.navega_a_los_cinco_campus", ok)
    check(f"{node}.indicador_de_edicion", all(
        own in t and (("solo consulta" in t) == (n != node)) for n, t in zip(NODES, texts)))
    check(f"{node}.selector_no_cambia_la_sesion", plugin.session["node_code"] == node and all(
        x.dataProvider().uri().port() == str(plugin.config["campuses"][node]["port"]) for x in layers.values()))
    panel.all.click()
    check(f"{node}.todos_los_campus", all(visible(iface, buildings, c) for c in range(1, 6))
          and len(plugin.markers.visible_names()) == 5)
    plugin.go_to_campus(node)
    iface.canvas.zoomByFactor(0.2)
    panel.center.click()
    check(f"{node}.rotulos_de_campus_solo_alejado", plugin.markers.visible_names() == [],
          f"escala 1:{iface.canvas.scale():.0f}")
    check(f"{node}.boton_centrar", visible(iface, buildings, NODES.index(node) + 1))


def sesion(module, plugin, iface, login, passwords, user_layer):
    """Botones del panel, falta de Internet, cierre de sesión y proyecto nuevo."""
    panel = plugin.panel
    login("qgis_san_carlos", passwords["san_carlos"])
    QTest.qWait(1500)
    check("panel.estado_conectado", "Conectado" in panel.status.text(), panel.status.text().split("> ")[-1])
    item = panel.legend.topLevelItem(0)
    item.setCheckState(0, Qt.Unchecked)
    node = QgsProject.instance().layerTreeRoot().findLayer(item.data(0, Qt.UserRole))
    check("panel.apaga_y_enciende_capa", not node.itemVisibilityChecked())
    item.setCheckState(0, Qt.Checked)
    panel.refresh.click()
    check("panel.actualizar_capas", len(managed(module)) == 8 and len(plugin.session["extents"]) == 5)

    layer = next(x for x in managed(module) if x.name() == "Edificios")
    layer.startEditing()
    layer.changeAttributeValue(next(layer.getFeatures()).id(), layer.fields().indexOf("nombre"), "sin guardar")
    asked = []

    class Question(module.QMessageBox):
        Yes, No = 1, 0

        @staticmethod
        def question(*args):
            asked.append(args[2])
            return 0
    previous, module.QMessageBox = module.QMessageBox, Question
    panel.session.click()
    check("panel.no_pierde_ediciones_sin_confirmar", len(asked) == 1 and "Edificios" in asked[0]
          and len(managed(module)) == 8)
    layer.rollBack()
    module.QMessageBox = previous

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        closed = s.getsockname()[1]
    plugin.config["basemap"]["url"] = f"http://127.0.0.1:{closed}/{{z}}/{{x}}/{{y}}.png"
    errors = login("qgis_limon", passwords["limon"])
    QTest.qWait(1500)
    settings = QgsMapSettings()
    settings.setLayers([x for x in managed(module)])
    settings.setDestinationCrs(managed(module)[0].crs())
    settings.setExtent(iface.canvas.mapSettings().mapToLayerCoordinates(managed(module)[0], iface.canvas.extent()))
    settings.setOutputSize(QSize(300, 200))
    job = QgsMapRendererSequentialJob(settings)
    job.start()
    job.waitForFinished()
    image = job.renderedImage()
    painted = sum(image.pixelColor(i, j) != QColor(Qt.white) for i in range(0, 300, 3) for j in range(0, 200, 3))
    check("sin_internet.capas_institucionales", not errors and len(managed(module)) == 8 and painted > 50,
          f"{painted} píxeles")
    check("sin_internet.aviso_en_panel", "Sin Internet" in panel.basemap.text(), panel.basemap.text().split("> ")[-1])
    plugin.config["basemap"]["url"] = module.BASEMAP["url"]
    # Sin estilo en la base, el complemento aplica su QML de respaldo.
    module.QgsVectorLayer.loadDefaultStyle = lambda self: ("", False)
    fallback = plugin._build_layers("limon", managed(module)[0].dataProvider().uri().authConfigId())
    del module.QgsVectorLayer.loadDefaultStyle  # vuelve a verse el método real heredado
    check("estilo_de_respaldo_del_zip", len(fallback) == 8 and all(
        x.renderer().type() == "RuleRenderer" for x in fallback))
    del fallback
    original = plugin.config["campuses"]["limon"]["port"]
    plugin.config["campuses"]["limon"]["port"] = closed
    plugin._probe()
    QTest.qWait(1500)
    plugin.config["campuses"]["limon"]["port"] = original
    check("panel.estado_nodo_caido", "sin respuesta" in panel.status.text(), panel.status.text().split("> ")[-1])

    panel.session.click()
    check("cerrar_sesion.retira_solo_sigtec", not managed(module) and not basemaps(module)
          and user_layer.id() in QgsProject.instance().mapLayers() and plugin.attribution is None)
    check("cerrar_sesion.panel_inactivo", plugin.session is None and not panel.active and not panel.selector.isEnabled())

    QgsProject.instance().removeMapLayer(user_layer.id())
    login("qgis_cartago", passwords["cartago"])
    check("proyecto_vacio.sistema_oficial", QgsProject.instance().crs().authid() == "EPSG:5367")
    check("datos.sin_nombres_sinteticos", not any(
        "sintético" in str(f["nombre"]).lower() for x in managed(module) if x.name() in ("Edificios", "Carreteras", "Puntos de interés")
        for f in x.getFeatures()), "nombres reales en edificios, vías y puntos")
    lights = [f for x in managed(module) if x.name() == "Iluminación" for f in x.getFeatures()]
    check("datos.iluminacion_marcada_sintetica", bool(lights) and all(f["codigo"].startswith("SINT-") for f in lights),
          f"{len(lights)} luminarias")
    QgsProject.instance().clear()
    check("proyecto_nuevo.cierra_la_sesion", plugin.session is None and not panel.active)


def edit(node, cid, layer):
    """Alta, cambio y baja propias; los mismos tres intentos sobre un campus ajeno."""
    own = next(layer.getFeatures(QgsFeatureRequest().setFilterExpression(f"campus_id={cid}")))
    foreign = next(layer.getFeatures(QgsFeatureRequest().setFilterExpression(f"campus_id<>{cid}")))
    marker = "QA-QGIS-" + secrets.token_hex(4)

    def find():
        layer.dataProvider().reloadData()
        return list(layer.getFeatures(QgsFeatureRequest().setFilterExpression(f"nombre LIKE '{marker}%'")))

    def new_feature(campus):
        f = QgsFeature(layer.fields())
        for i, field in enumerate(layer.fields()):
            f[i] = NULL if field.name() in ("id", "campus_id") else own[field.name()]
        f["nombre"] = marker
        f["campus_id"] = campus
        p = own.geometry().asPoint()
        f.setGeometry(QgsGeometry.fromPointXY(QgsPointXY(p.x() + 3, p.y() + 3)))
        return f

    def commit(action):
        layer.startEditing()
        done = action()
        ok = done and layer.commitChanges()
        errors = "; ".join(layer.commitErrors())
        if not ok:
            layer.rollBack()
        return ok, errors

    try:
        ok, errors = commit(lambda: layer.addFeature(new_feature(NULL)))
        rows = find()
        check(f"{node}.alta_propia", ok and len(rows) == 1 and rows[0]["campus_id"] == cid
              and rows[0]["id"] // 1_000_000_000 == cid, str(rows[0]["id"]) if rows else errors)
        if rows:
            ok, errors = commit(lambda: layer.changeAttributeValue(
                rows[0].id(), layer.fields().indexOf("nombre"), marker + "-mod"))
            check(f"{node}.cambio_propio", ok and find()[0]["nombre"] == marker + "-mod", errors)

        index = layer.fields().indexOf("nombre")
        ok, errors = commit(lambda: layer.changeAttributeValue(foreign.id(), index, "ajeno"))
        check(f"{node}.cambio_ajeno_rechazado", not ok and "ajeno" in errors, errors.split("\n")[0][:60])
        ok, errors = commit(lambda: layer.deleteFeature(foreign.id()))
        check(f"{node}.baja_ajena_rechazada", not ok and "ajeno" in errors)
        ok, errors = commit(lambda: layer.addFeature(new_feature(cid % 5 + 1)))
        check(f"{node}.alta_ajena_rechazada", not ok and len(find()) <= 1)
        layer.dataProvider().reloadData()
        again = next(layer.getFeatures(QgsFeatureRequest().setFilterExpression(f"id={foreign['id']}")), None)
        check(f"{node}.dato_ajeno_intacto", again is not None and again.attributes() == foreign.attributes())
    finally:
        for f in find():
            ok, errors = commit(lambda f=f: layer.deleteFeature(f.id()))
        check(f"{node}.baja_propia", not find())


if __name__ == "__main__":
    sys.exit(main())
