"""Lógica sin dependencias de QGIS, reutilizada por pruebas y complemento."""
from __future__ import annotations

import json
from pathlib import Path

LAYER_SPECS = (
    ("edificios", "Edificios", "Polygon"),
    ("carreteras", "Carreteras", "LineString"),
    ("aceras", "Aceras", "LineString"),
    ("parqueos", "Parqueos", "Polygon"),
    ("zonas_verdes", "Zonas verdes", "Polygon"),
    ("puntos_interes", "Puntos de interés", "Point"),
    ("iluminacion", "Iluminación", "Point"),
    ("accesibilidad", "Accesibilidad", "LineString"),
)
NODE_CODES = ("cartago", "san_jose", "san_carlos", "alajuela", "limon")
MANAGED_PROPERTY = "sigtec/managed"


def load_config(path: str | Path) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {"database", "sslmode", "connect_timeout", "srid", "central", "campuses"}
    missing = required.difference(data)
    if missing:
        raise ValueError("Faltan opciones: " + ", ".join(sorted(missing)))
    if set(data["campuses"]) != set(NODE_CODES):
        raise ValueError("La configuración debe definir exactamente los cinco campus")
    if data["srid"] != 5367:
        raise ValueError("SIG-TEC requiere EPSG:5367")
    for name, endpoint in [("central", data["central"]), *data["campuses"].items()]:
        if not endpoint.get("host") or not isinstance(endpoint.get("port"), int):
            raise ValueError(f"Host o puerto inválido para {name}")
        if not 1 <= endpoint["port"] <= 65535:
            raise ValueError(f"Puerto fuera de rango para {name}")
    timeout = data["connect_timeout"]
    if not isinstance(timeout, int) or not 1 <= timeout <= 60:
        raise ValueError("connect_timeout debe estar entre 1 y 60 segundos")
    return data


def layer_table(layer_code: str) -> str:
    if layer_code not in {item[0] for item in LAYER_SPECS}:
        raise ValueError(f"Capa desconocida: {layer_code}")
    return "v_" + layer_code
