from __future__ import annotations

from pathlib import Path

from qgis.PyQt.QtCore import QTimer, QUrl, Qt
from qgis.PyQt.QtGui import QIcon
from qgis.PyQt.QtNetwork import QTcpSocket
from qgis.PyQt.QtXml import QDomDocument
from qgis.PyQt.QtWidgets import QAction, QDialog, QDockWidget, QMessageBox
from qgis.core import (
    Qgis, QgsApplication, QgsAuthMethodConfig, QgsCoordinateReferenceSystem, QgsDataSourceUri,
    QgsProject, QgsProviderRegistry, QgsRasterLayer, QgsRectangle, QgsVectorLayer,
)

from .core import (
    BASEMAP, BASEMAP_PROPERTY, CAMPUS_NAMES, DRAW_ORDER, LAYER_SPECS, MANAGED_PROPERTY, NODE_CODES,
    layer_table, load_config,
)
from .login_dialog import LoginDialog
from .panel import Attribution, CampusMarkers, SigTecPanel


class MasterPasswordError(RuntimeError):
    """El almacén de credenciales de QGIS no está disponible (contraseña maestra)."""


class SigTecPlugin:
    def __init__(self, iface):
        self.iface = iface
        self.action = None
        self.base_dir = Path(__file__).resolve().parent
        self.config = load_config(self.base_dir / "config.json")
        self.panel = None
        self.panel_action = None
        self.session = None
        self.attribution = None
        self.markers = None
        self.probes = {}
        self.reachable = {}
        self.timer = None

    def initGui(self):
        window = self.iface.mainWindow()
        icon = QIcon(str(self.base_dir / "icon.svg"))
        self.action = QAction(icon, "Iniciar sesión en SIG-TEC", window)
        self.action.triggered.connect(lambda _checked=False: self.login())
        self.panel = SigTecPanel(window)
        self.panel.login_requested.connect(self.login)
        self.panel.logout_requested.connect(self.logout)
        self.panel.campus_selected.connect(self.go_to_campus)
        self.panel.center_requested.connect(lambda: self.go_to_campus(self.panel.selector.currentData()))
        self.panel.all_requested.connect(self.show_all)
        self.panel.refresh_requested.connect(self.refresh)
        self.panel.layer_toggled.connect(self._set_layer_visible)
        self.iface.addDockWidget(Qt.RightDockWidgetArea, self.panel)
        self.panel.hide()
        self.panel_action = self.panel.toggleViewAction()
        self.panel_action.setText("Panel SIG-TEC")
        for action in (self.action, self.panel_action):
            self.iface.addPluginToDatabaseMenu("SIG-TEC", action)
        self.iface.addToolBarIcon(self.action)
        self.timer = QTimer(window)
        self.timer.setInterval(20000)
        self.timer.timeout.connect(self._probe)
        QgsProject.instance().cleared.connect(self._project_cleared)

    def unload(self):
        if not self.action:
            return
        QgsProject.instance().cleared.disconnect(self._project_cleared)
        self.timer.stop()
        self._end_session()
        for action in (self.action, self.panel_action):
            self.iface.removePluginDatabaseMenu("SIG-TEC", action)
        self.iface.removeToolBarIcon(self.action)
        self.iface.removeDockWidget(self.panel)
        self.panel.deleteLater()
        self.action = self.panel = None

    def login(self):
        if not self._confirm_discard("Iniciar sesión de nuevo"):
            return
        dialog = LoginDialog(self.iface.mainWindow())
        if dialog.exec() != QDialog.Accepted:
            return
        username, password = dialog.credentials()
        if not username or not password:
            QMessageBox.warning(self.iface.mainWindow(), "SIG-TEC",
                                "Debe indicar usuario y contraseña.")
            return
        candidate = None
        try:
            candidate = self._store_credentials(username, password)
            campus = self._authenticate(candidate)
            authcfg = self._keep_credentials(candidate, username)
            candidate = None
            layers = self._build_layers(campus["node_code"], authcfg)
            extents = self._campus_extents(campus["node_code"], authcfg)
            self._replace_managed_layers(layers, campus["campus_nombre"])
            self._start_session(username, campus, extents, layers)
        except Exception as exc:
            QMessageBox.critical(
                self.iface.mainWindow(), "SIG-TEC · No se pudo ingresar",
                self._safe_error(exc),
            )
            return
        finally:
            if candidate:  # clave rechazada o central inaccesible: no dejarla guardada
                QgsApplication.authManager().removeAuthenticationConfig(candidate)
            password = ""  # no conservar la contraseña en el objeto del complemento

        self.iface.messageBar().pushMessage(
            "SIG-TEC", f"Sesión iniciada: {campus['campus_nombre']}. Se cargaron 8 capas.",
            level=Qgis.Success, duration=8,
        )

    # --- Sesión e interfaz ----------------------------------------------------
    def _start_session(self, username, campus, extents, layers):
        self.session = {"username": username, "extents": extents, **campus}
        self._add_basemap()
        self._remove_markers()
        self.markers = CampusMarkers(
            self.iface.mapCanvas(), layers[0].crs(),
            {CAMPUS_NAMES[node]: extent.center() for node, extent in extents.items()})
        self.panel.set_session(username, campus["node_code"], campus["campus_nombre"])
        self._update_legend()
        self.panel.set_status("espera", "Comprobando…")
        self._show_panels()
        self.iface.layerTreeCanvasBridge().setCanvasLayers()  # antes del encuadre del campus
        self.go_to_campus(campus["node_code"])
        self._probe()
        self.timer.start()

    def _remove_markers(self):
        if self.markers is not None:
            self.iface.mapCanvas().scene().removeItem(self.markers)
            self.markers = None

    def _show_panels(self):
        for dock in (self.iface.mainWindow().findChild(QDockWidget, "Layers"), self.panel):
            if dock is not None:
                dock.show()
                dock.raise_()

    def managed_layers(self):
        return [layer for layer in QgsProject.instance().mapLayers().values()
                if layer.customProperty(MANAGED_PROPERTY, False)]

    def _confirm_discard(self, title):
        pending = [layer.name() for layer in self.managed_layers()
                   if layer.isEditable() and layer.isModified()]
        if not pending:
            return True
        answer = QMessageBox.question(
            self.iface.mainWindow(), "SIG-TEC · " + title,
            "Hay cambios sin guardar en: " + ", ".join(sorted(pending)) +
            ". Si continúa, se perderán. ¿Desea continuar?",
        )
        return answer == QMessageBox.Yes

    def logout(self):
        """Retira solo las capas de SIG-TEC; el resto del proyecto y las credenciales no cambian."""
        if not self._confirm_discard("Cerrar sesión"):
            return
        project = QgsProject.instance()
        project.removeMapLayers([layer.id() for layer in project.mapLayers().values()
                                 if layer.customProperty(MANAGED_PROPERTY, False)
                                 or layer.customProperty(BASEMAP_PROPERTY, False)])
        group = project.layerTreeRoot().findGroup("SIG-TEC")
        if group and not group.children():
            project.layerTreeRoot().removeChildNode(group)
        self._end_session()
        self.iface.mapCanvas().refresh()
        self.iface.messageBar().pushMessage("SIG-TEC", "Sesión cerrada.", level=Qgis.Info, duration=5)

    def _project_cleared(self):
        self._end_session()

    def _end_session(self):
        self.session = None
        self.timer.stop()
        for socket in self.probes.values():
            socket.abort()
            socket.deleteLater()
        self.probes = {}
        if self.attribution:
            self.attribution.remove()
            self.attribution = None
        self._remove_markers()
        self.panel.clear()

    def refresh(self):
        """Relee datos y encuadres sin descartar ediciones en curso."""
        if not self.session:
            return
        layers = self.managed_layers()
        editing = [layer.name() for layer in layers if layer.isEditable()]
        for layer in layers:
            if not layer.isEditable():
                layer.dataProvider().reloadData()
                layer.triggerRepaint()
        try:
            authcfg = layers[0].dataProvider().uri().authConfigId() if layers else ""
            self.session["extents"] = self._campus_extents(self.session["node_code"], authcfg)
        except Exception:
            self.panel.set_status("error", "El nodo del campus no responde")
            self.iface.messageBar().pushMessage(
                "SIG-TEC", "No se pudieron actualizar las capas: el nodo del campus no responde.",
                level=Qgis.Warning, duration=8)
            return
        self._update_legend()
        self._probe()
        text = "Capas actualizadas."
        if editing:
            text += " En edición, sin cambios: " + ", ".join(sorted(editing)) + "."
        self.iface.messageBar().pushMessage("SIG-TEC", text, level=Qgis.Info, duration=5)

    def _update_legend(self):
        order = {name: i for i, name in enumerate(self._display_order())}
        layers = sorted(self.managed_layers(), key=lambda layer: order.get(layer.name(), 99))
        root = QgsProject.instance().layerTreeRoot()

        def visible(layer):
            node = root.findLayer(layer.id())
            return bool(node and node.itemVisibilityChecked())
        self.panel.set_legend(layers, visible)

    def _set_layer_visible(self, layer_id, visible):
        node = QgsProject.instance().layerTreeRoot().findLayer(layer_id)
        if node:
            node.setItemVisibilityChecked(visible)

    @staticmethod
    def _display_order():
        names = {code: name for code, name, _geometry in LAYER_SPECS}
        return [names[code] for code in DRAW_ORDER]

    # --- Navegación: solo mueve el mapa, nunca cambia permisos -----------------
    def go_to_campus(self, node_code):
        if not self.session:
            return
        extent = self.session["extents"].get(node_code)
        if extent is None:
            self.iface.messageBar().pushMessage(
                "SIG-TEC", f"No hay objetos de {CAMPUS_NAMES[node_code]} para encuadrar.",
                level=Qgis.Warning, duration=5)
            return
        self.panel.select(node_code)
        self._zoom(extent)

    def show_all(self):
        if not self.session or not self.session["extents"]:
            return
        total = QgsRectangle()
        for extent in self.session["extents"].values():
            total.combineExtentWith(extent)
        total.scale(1.35)  # espacio para los rótulos de campus
        self.panel.show_all()
        self._zoom(total)

    def _zoom(self, extent):
        layers = self.managed_layers()
        if not layers:
            return
        canvas = self.iface.mapCanvas()
        canvas.setExtent(canvas.mapSettings().layerExtentToOutputExtent(layers[0], extent))
        canvas.refresh()

    # --- Mapa base ---------------------------------------------------------------
    def _basemap_options(self):
        return {**BASEMAP, **self.config.get("basemap", {})}

    def _add_basemap(self):
        """Una sola capa OSM, siempre al fondo. Si falla, las capas institucionales no se afectan."""
        project = QgsProject.instance()
        options = self._basemap_options()
        existing = [layer for layer in project.mapLayers().values()
                    if layer.customProperty(BASEMAP_PROPERTY, False)]
        project.removeMapLayers([layer.id() for layer in existing])
        url = bytes(QUrl.toPercentEncoding(options["url"], b":/{}")).decode()
        layer = QgsRasterLayer(f"type=xyz&url={url}&zmin=0&zmax={options['zmax']}", options["name"], "wms")
        if not layer.isValid():
            self.panel.set_basemap("error", "No disponible")
            return
        layer.setCustomProperty(BASEMAP_PROPERTY, True)
        layer.setOpacity(options["opacity"])
        layer.serverProperties().setAttribution(options["attribution"])
        layer.serverProperties().setAttributionUrl("https://www.openstreetmap.org/copyright")
        project.addMapLayer(layer, False)
        project.layerTreeRoot().addLayer(layer)  # último nodo: debajo de todo
        if self.attribution is None:
            self.attribution = Attribution(self.iface.mapCanvas(), options["attribution"])

    # --- Estado de conexión, sin bloquear la interfaz ------------------------------
    def _probe(self):
        if not self.session:
            return
        node = self.session["node_code"]
        tile = QUrl(self._basemap_options()["url"].split("{")[0])
        targets = {
            "central": (self.config["central"]["host"], self.config["central"]["port"]),
            "campus": (self.config["campuses"][node]["host"], self.config["campuses"][node]["port"]),
            "basemap": (tile.host(), tile.port(443 if tile.scheme() == "https" else 80)),
        }
        self.reachable = {}
        for name, (host, port) in targets.items():
            old = self.probes.pop(name, None)
            if old:
                old.abort()
                old.deleteLater()
            socket = QTcpSocket(self.panel)
            self.probes[name] = socket
            # Qt puede anunciar "connected" un instante antes de informar un rechazo:
            # solo cuenta como disponible si la conexión sigue abierta poco después.
            socket.connected.connect(lambda n=name, s=socket: QTimer.singleShot(
                400, lambda: self._probed(n, s, True)))
            socket.errorOccurred.connect(lambda _e, n=name, s=socket: self._probed(n, s, False))
            socket.connectToHost(host, port)
        current = dict(self.probes)
        QTimer.singleShot(6000, lambda: self._probe_timeout(current))

    def _probe_timeout(self, sockets):
        for name, socket in sockets.items():
            self._probed(name, socket, False)  # ignora los ya resueltos o sustituidos

    def _probed(self, name, socket, ok):
        if not self.session or self.probes.get(name) is not socket or name in self.reachable:
            return
        self.reachable[name] = ok
        socket.abort()
        if name == "basemap":
            self.panel.set_basemap("ok" if ok else "parcial",
                                   "OpenStreetMap" if ok else "Sin Internet (las capas del TEC siguen disponibles)")
        if "central" in self.reachable and "campus" in self.reachable:
            campus = CAMPUS_NAMES[self.session["node_code"]]
            if self.reachable["campus"] and self.reachable["central"]:
                self.panel.set_status("ok", f"Conectado al nodo {campus}")
            elif self.reachable["campus"]:
                self.panel.set_status("parcial", f"Nodo {campus} activo; central sin respuesta")
            else:
                self.panel.set_status("error", f"Nodo {campus} sin respuesta")

    def _store_credentials(self, username, password):
        manager = QgsApplication.authManager()
        if not manager.masterPasswordIsSet():
            if not manager.setMasterPassword(True):
                # Nada se guardó todavía: basta con volver a intentar el ingreso.
                manager.clearMasterPassword()
                raise MasterPasswordError(self._master_password_help(manager))
        config = QgsAuthMethodConfig()
        config.setMethod("Basic")
        config.setName(f"SIG-TEC · {username}")
        config.setConfig("username", username)
        config.setConfig("password", password)
        if not manager.storeAuthenticationConfig(config):
            raise MasterPasswordError("QGIS no pudo guardar las credenciales en su almacén cifrado. "
                               "Configure una contraseña maestra en Preferencias > Opciones > Autenticación.")
        return config.id()

    def _keep_credentials(self, candidate, username):
        """Conserva una sola credencial por cuenta, ya validada por el central.

        Reutiliza el id de la sesión anterior para que los proyectos guardados sigan
        abriendo y no se acumulen entradas en el almacén de QGIS.
        """
        manager = QgsApplication.authManager()
        name = f"SIG-TEC · {username}"
        previous = [key for key, config in manager.availableAuthMethodConfigs().items()
                    if config.name() == name and config.method() == "Basic" and key != candidate]
        if not previous:
            return candidate
        config = QgsAuthMethodConfig()
        if not manager.loadAuthenticationConfig(candidate, config, True):
            return candidate
        config.setId(previous[0])
        if not manager.updateAuthenticationConfig(config):
            return candidate
        for key in [candidate, *previous[1:]]:
            manager.removeAuthenticationConfig(key)
        return previous[0]

    def _uri(self, endpoint, authcfg):
        uri = QgsDataSourceUri()
        uri.setConnection(
            endpoint["host"], str(endpoint["port"]), self.config["database"],
            "", "", QgsDataSourceUri.SslRequire, authcfg,
        )
        uri.setParam("connect_timeout", str(self.config["connect_timeout"]))
        return uri

    def _connection(self, endpoint, authcfg):
        uri = self._uri(endpoint, authcfg)
        metadata = QgsProviderRegistry.instance().providerMetadata("postgres")
        return metadata.createConnection(uri.uri(False), {})

    def _authenticate(self, authcfg):
        connection = self._connection(self.config["central"], authcfg)
        rows = connection.executeSql(
            "SELECT campus_id, node_code, campus_nombre FROM auth.sesion_campus()"
        )
        if len(rows) != 1:
            raise PermissionError("La cuenta no tiene un campus activo asignado.")
        campus_id, node_code, campus_nombre = rows[0]
        if node_code not in self.config["campuses"]:
            raise RuntimeError("El central devolvió un campus que no existe en config.json.")
        return {"campus_id": int(campus_id), "node_code": node_code,
                "campus_nombre": campus_nombre}

    def _campus_extents(self, node_code, authcfg):
        """Encuadre de cada campus según sus edificios (o todas sus capas si no tiene)."""
        connection = self._connection(self.config["campuses"][node_code], authcfg)
        features = " UNION ALL ".join(
            f"SELECT campus_id, geom, {int(code == 'edificios')} AS edificio FROM qgis.{layer_table(code)}"
            for code, _name, _geometry in LAYER_SPECS
        )
        rows = connection.executeSql(f"""
            SELECT campus_id, ST_XMin(b), ST_YMin(b), ST_XMax(b), ST_YMax(b)
            FROM (SELECT campus_id,
                         coalesce(ST_Extent(geom) FILTER (WHERE edificio = 1), ST_Extent(geom)) AS b
                  FROM ({features}) AS f GROUP BY campus_id) AS x
            WHERE b IS NOT NULL
        """)
        extents = {}
        for campus_id, *bounds in rows:
            extent = QgsRectangle(*map(float, bounds))
            # EPSG:5367 usa metros. Incluye margen incluso con un solo edificio.
            extent.grow(max(35.0, 0.1 * max(extent.width(), extent.height())))
            extents[NODE_CODES[int(campus_id) - 1]] = extent
        return extents

    def _build_layers(self, node_code, authcfg):
        endpoint = self.config["campuses"][node_code]
        result = []
        wkb_types = {
            "Point": Qgis.WkbType.Point,
            "LineString": Qgis.WkbType.LineString,
            "Polygon": Qgis.WkbType.Polygon,
        }
        for code, display_name, geometry_type in LAYER_SPECS:
            uri = self._uri(endpoint, authcfg)
            uri.setDataSource("qgis", layer_table(code), "geom", "", "id")
            uri.setSrid(str(self.config["srid"]))
            uri.setWkbType(wkb_types[geometry_type])
            layer = QgsVectorLayer(uri.uri(False), display_name, "postgres")
            if not layer.isValid():
                raise ConnectionError(
                    f"El nodo {node_code} no está accesible o la vista qgis.{layer_table(code)} no existe."
                )
            layer.setCustomProperty(MANAGED_PROPERTY, True)
            layer.setCustomProperty("sigtec/node_code", node_code)
            # QGIS busca primero el estilo por defecto replicado en layer_styles.
            _message, loaded = layer.loadDefaultStyle()
            if not loaded:
                # loadNamedStyle() en PostgreSQL vuelve a consultar la base: se lee el archivo.
                document = QDomDocument()
                document.setContent((self.base_dir / "styles" / f"{code}.qml").read_text(encoding="utf-8"))
                loaded, message = layer.importNamedStyle(document)
                if not loaded:
                    raise RuntimeError(f"No se pudo aplicar el estilo de {display_name}: {message}")
            result.append(layer)
        return result

    def _replace_managed_layers(self, layers, campus_name):
        project = QgsProject.instance()
        old_ids = [layer.id() for layer in project.mapLayers().values()
                   if layer.customProperty(MANAGED_PROPERTY, False)]
        project.removeMapLayers(old_ids)
        if not project.mapLayers() or all(layer.customProperty(BASEMAP_PROPERTY, False)
                                          for layer in project.mapLayers().values()):
            # Proyecto sin capas propias del usuario: trabaja en el sistema oficial del TEC.
            project.setCrs(QgsCoordinateReferenceSystem.fromEpsgId(self.config["srid"]))
        root = project.layerTreeRoot()
        previous = root.findGroup("SIG-TEC")
        if previous and not previous.children():
            root.removeChildNode(previous)
        group = root.findGroup("SIG-TEC") or root.insertGroup(0, "SIG-TEC")
        group.setCustomProperty("sigtec/campus", campus_name)
        order = {name: i for i, name in enumerate(self._display_order())}
        for layer in sorted(layers, key=lambda item: order[item.name()]):
            project.addMapLayer(layer, False)
            node = group.addLayer(layer)
            node.setExpanded(False)

    @staticmethod
    def _master_password_help(manager):
        if manager.isDisabled():
            return ("QGIS bloqueó su almacén de credenciales tras varios intentos con una contraseña "
                    "maestra incorrecta. Cierre y vuelva a abrir QGIS e intente de nuevo.")
        return ("La contraseña maestra de QGIS no se ingresó o no es correcta. No es la contraseña de su "
                "campus: protege las credenciales guardadas en este equipo.\n\n"
                "Si QGIS avisa que la del llavero no es válida, escriba la actual cuando la pida: "
                "QGIS actualizará el llavero. Si no la conoce, consulte «Contraseña maestra» en "
                "docs/INTEGRANTE_3.md.")

    @staticmethod
    def _safe_error(exc):
        if isinstance(exc, (PermissionError, MasterPasswordError)):
            return str(exc)
        if isinstance(exc, ConnectionError):
            return str(exc)
        # No mostrar mensajes del proveedor: podrían incluir datos de conexión.
        return ("No se pudo autenticar contra el nodo central. Verifique usuario, contraseña, "
                "configuración y disponibilidad de los nodos.")
