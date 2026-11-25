from __future__ import annotations

from pathlib import Path

from qgis.PyQt.QtWidgets import QAction, QDialog, QMessageBox
from qgis.core import (
    Qgis, QgsApplication, QgsAuthMethodConfig, QgsDataSourceUri, QgsProject,
    QgsProviderRegistry, QgsRectangle, QgsVectorLayer,
)

from .core import LAYER_SPECS, MANAGED_PROPERTY, layer_table, load_config
from .login_dialog import LoginDialog


class SigTecPlugin:
    def __init__(self, iface):
        self.iface = iface
        self.action = None
        self.base_dir = Path(__file__).resolve().parent
        self.config = load_config(self.base_dir / "config.json")

    def initGui(self):
        self.action = QAction("Iniciar sesión en SIG-TEC", self.iface.mainWindow())
        self.action.triggered.connect(self.login)
        self.iface.addPluginToDatabaseMenu("SIG-TEC", self.action)
        self.iface.addToolBarIcon(self.action)

    def unload(self):
        if self.action:
            self.iface.removePluginDatabaseMenu("SIG-TEC", self.action)
            self.iface.removeToolBarIcon(self.action)

    def login(self):
        dialog = LoginDialog(self.iface.mainWindow())
        if dialog.exec() != QDialog.Accepted:
            return
        username, password = dialog.credentials()
        if not username or not password:
            QMessageBox.warning(self.iface.mainWindow(), "SIG-TEC",
                                "Debe indicar usuario y contraseña.")
            return
        try:
            authcfg = self._store_credentials(username, password)
            campus = self._authenticate(authcfg)
            layers = self._build_layers(campus["node_code"], authcfg)
            extent = self._campus_extent(campus, authcfg)
            self._replace_managed_layers(layers, campus["campus_nombre"])
            if extent is not None:
                self._zoom_to_campus(layers[0], extent)
        except Exception as exc:
            QMessageBox.critical(
                self.iface.mainWindow(), "SIG-TEC · No se pudo ingresar",
                self._safe_error(exc),
            )
            return
        finally:
            password = ""  # no conservar la contraseña en el objeto del complemento

        self.iface.messageBar().pushMessage(
            "SIG-TEC", f"Sesión iniciada: {campus['campus_nombre']}. Se cargaron 8 capas.",
            level=Qgis.Success, duration=8,
        )

    def _store_credentials(self, username, password):
        manager = QgsApplication.authManager()
        if not manager.masterPasswordIsSet():
            if not manager.setMasterPassword(True):
                raise RuntimeError("Cree o desbloquee la contraseña maestra de QGIS e intente de nuevo.")
        config = QgsAuthMethodConfig()
        config.setMethod("Basic")
        config.setName(f"SIG-TEC · {username}")
        config.setConfig("username", username)
        config.setConfig("password", password)
        if not manager.storeAuthenticationConfig(config):
            raise RuntimeError("QGIS no pudo guardar las credenciales en su almacén cifrado. "
                               "Configure una contraseña maestra en Preferencias > Opciones > Autenticación.")
        return config.id()

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

    def _campus_extent(self, campus, authcfg):
        endpoint = self.config["campuses"][campus["node_code"]]
        connection = self._connection(endpoint, authcfg)
        campus_id = campus["campus_id"]
        local_geometries = " UNION ALL ".join(
            f"SELECT geom FROM qgis.{layer_table(code)} WHERE campus_id = {campus_id}"
            for code, _name, _geometry in LAYER_SPECS
        )
        rows = connection.executeSql(f"""
            SELECT ST_XMin(bounds), ST_YMin(bounds), ST_XMax(bounds), ST_YMax(bounds)
            FROM (SELECT ST_Extent(geom) AS bounds
                  FROM ({local_geometries}) AS features) AS campus_extent
            WHERE bounds IS NOT NULL
        """)
        if not rows:
            return None
        extent = QgsRectangle(*rows[0])
        # EPSG:5367 usa metros. Incluye margen incluso con un solo punto.
        extent.grow(max(35.0, 0.1 * max(extent.width(), extent.height())))
        return extent

    def _zoom_to_campus(self, layer, extent):
        # Aplica el autoencuadre inicial de QGIS antes del encuadre del campus.
        self.iface.layerTreeCanvasBridge().setCanvasLayers()
        canvas = self.iface.mapCanvas()
        canvas.setExtent(canvas.mapSettings().layerExtentToOutputExtent(layer, extent))
        canvas.refresh()

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
                fallback = self.base_dir / "styles" / f"{code}.qml"
                message, loaded = layer.loadNamedStyle(str(fallback))
                if not loaded:
                    raise RuntimeError(f"No se pudo aplicar el estilo de {display_name}: {message}")
            result.append(layer)
        return result

    def _replace_managed_layers(self, layers, campus_name):
        project = QgsProject.instance()
        old_ids = [layer.id() for layer in project.mapLayers().values()
                   if layer.customProperty(MANAGED_PROPERTY, False)]
        project.removeMapLayers(old_ids)
        root = project.layerTreeRoot()
        previous = root.findGroup("SIG-TEC")
        if previous and not previous.children():
            root.removeChildNode(previous)
        group = root.findGroup("SIG-TEC") or root.addGroup("SIG-TEC")
        group.setCustomProperty("sigtec/campus", campus_name)
        for layer in layers:
            project.addMapLayer(layer, False)
            group.addLayer(layer)

    @staticmethod
    def _safe_error(exc):
        if isinstance(exc, PermissionError):
            return str(exc)
        if isinstance(exc, ConnectionError):
            return str(exc)
        # No mostrar mensajes del proveedor: podrían incluir datos de conexión.
        return ("No se pudo autenticar contra el nodo central. Verifique usuario, contraseña, "
                "configuración y disponibilidad de los nodos.")
