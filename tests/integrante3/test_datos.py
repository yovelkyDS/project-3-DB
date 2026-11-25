import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CAMPUS = ("cartago", "san_jose", "san_carlos", "alajuela", "limon")
CAPAS = {"edificios": "Polygon", "carreteras": "LineString", "aceras": "LineString", "parqueos": "Polygon",
         "zonas_verdes": "Polygon", "puntos_interes": "Point", "accesibilidad": "LineString"}


class DatosRealesTests(unittest.TestCase):
    def leer(self, campus):
        return json.loads((ROOT / "data" / "osm" / f"{campus}.geojson").read_text(encoding="utf-8"))

    def test_cada_objeto_es_rastreable_en_osm(self):
        for campus in CAMPUS:
            data = self.leer(campus)
            self.assertIn("ODbL", data["fuente"])
            self.assertRegex(data["limite_osm"], r"^way/\d+$")
            for feature in data["features"]:
                properties = feature["properties"]
                self.assertRegex(properties["osm"], r"^(node|way|relation)/\d+$")
                self.assertTrue(properties["osm_version"] and properties["osm_fecha"])
                self.assertEqual(feature["geometry"]["type"], CAPAS[properties["capa"]])
                self.assertLessEqual(set(properties["supuestos"]), {
                    "pisos", "capacidad", "disponibilidad", "tipo", "superficie", "material", "ancho",
                    "condicion", "tipo_vegetacion"})

    def test_seis_capas_reales_en_cada_campus(self):
        reales = set(CAPAS) - {"accesibilidad"}
        for campus in CAMPUS:
            with self.subTest(campus=campus):
                self.assertLessEqual(reales, {f["properties"]["capa"] for f in self.leer(campus)["features"]})

    def test_alajuela_distingue_la_sede_anfitriona(self):
        nombres = [f["properties"]["atributos"]["nombre"] for f in self.leer("alajuela")["features"]
                   if f["properties"]["capa"] == "edificios"]
        self.assertTrue(all(re.search(r"UTN|TEC|sin nombre", n) for n in nombres), nombres)

    def test_importacion_archiva_y_no_envia_identificadores(self):
        sql = (ROOT / "sql" / "datos" / "importar_osm_v1.sql").read_text(encoding="utf-8")
        self.assertIn("ops.datos_retirados", sql)
        for capa in CAPAS:
            self.assertNotRegex(sql, rf"INSERT INTO {capa} \(id\b")


if __name__ == "__main__":
    unittest.main()
