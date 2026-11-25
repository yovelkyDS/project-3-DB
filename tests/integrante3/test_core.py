import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CORE_PATH = ROOT / "qgis_plugin" / "sigtec" / "core.py"
SPEC = importlib.util.spec_from_file_location("sigtec_core", CORE_PATH)
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)


class CoreTests(unittest.TestCase):
    def test_configuracion_entregada_es_valida(self):
        config = core.load_config(ROOT / "qgis_plugin" / "sigtec" / "config.json")
        self.assertEqual(config["srid"], 5367)
        self.assertEqual(len(config["campuses"]), 5)

    def test_contrato_de_ocho_capas(self):
        self.assertEqual(len(core.LAYER_SPECS), 8)
        self.assertEqual(len({item[0] for item in core.LAYER_SPECS}), 8)
        self.assertEqual(core.layer_table("puntos_interes"), "v_puntos_interes")

    def test_rechaza_nodo_inaccesible_mal_configurado(self):
        data = json.loads((ROOT / "qgis_plugin" / "sigtec" / "config.json").read_text())
        data["campuses"]["san_carlos"]["port"] = 70000
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Puerto fuera de rango"):
                core.load_config(path)

    def test_existen_estilos_para_todas_las_capas(self):
        styles = ROOT / "qgis_plugin" / "sigtec" / "styles"
        for code, _name, _geometry in core.LAYER_SPECS:
            with self.subTest(capa=code):
                style = ET.parse(styles / f"{code}.qml")
                options = style.findall("./renderer-v2/symbols/symbol/layer/Option/Option")
                self.assertTrue(options)
                for option in options:
                    # Tipos que escribe QGIS 3.44; cualquier otro se ignora al abrir el estilo.
                    if option.get("value") is None and not len(option):
                        continue  # opción vacía (p. ej. "parameters" de un SVG)
                    self.assertIn(option.get("type"), {"QString", "bool", "double", "int", "Map"},
                                  option.get("name"))

    def test_autenticacion_usa_identidad_de_sesion_sin_tabla_de_claves(self):
        sql = (ROOT / "sql" / "integrante3" / "auth.sql").read_text(encoding="utf-8")
        self.assertIn("u.usuario = session_user", sql)
        self.assertNotIn("password text", sql.lower())
        self.assertIn("REVOKE ALL ON ALL TABLES IN SCHEMA auth FROM PUBLIC", sql)

    def test_layer_styles_coincide_con_qgis_344(self):
        sql = (ROOT / "sql" / "integrante3" / "layer_styles.sql").read_text(encoding="utf-8")
        for column in ("styleqml xml", "stylesld xml", "useasdefault boolean",
                       "owner varchar(63)", "r_raster_column varchar"):
            self.assertIn(column, sql.lower())


if __name__ == "__main__":
    unittest.main()
