"""Prepara data/osm/<campus>.geojson a partir de OpenStreetMap (ODbL). Solo biblioteca estándar.

  python3 scripts/datos/preparar_osm.py --descargar   consulta la API de OSM y regenera los GeoJSON
  python3 scripts/datos/preparar_osm.py               regenera desde extractos ya descargados

Reglas:
* Ubicación, forma y nombre salen de OSM; no se inventa ninguno.
* Un atributo obligatorio del modelo que OSM no informa recibe un valor supuesto y su
  nombre queda en "supuestos", que la importación guarda en ops.procedencia_objetos.
* Iluminación no existe en OSM para estos campus; la importación genera demostración.
"""
import argparse
import json
from pathlib import Path
import re
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "tmp" / "osm"          # tmp/ no se versiona
OUT = ROOT / "data" / "osm"
API = "https://api.openstreetmap.org/api/0.6"

# Polígono OSM que delimita cada campus. En Alajuela el TEC funciona "Dentro de la Sede
# Central de la UTN en Villa Bonita" (tec.ac.cr/ubicaciones/centro-academico-alajuela).
LIMITES = {
    "cartago": 40819609, "san_jose": 199579277, "san_carlos": 351554216,
    "alajuela": 316304753, "limon": 665308676,
}
# Metros que se conservan de las vías y aceras alrededor del límite.
MARGEN = {"cartago": 25, "san_jose": 60, "san_carlos": 25, "alajuela": 25, "limon": 60}
# Donde el campus casi no tiene aceras, parqueos ni zonas verdes mapeados se incorporan los
# reales del entorno inmediato (metros), descritos como ajenos al TEC.
ENTORNO = {"san_jose": 250, "limon": 200}
EXCLUIDOS = {534139880}  # TEORética: fundación ajena al TEC dentro del polígono esquemático de San José
# Edificios del TEC en San José situados fuera del polígono de campus mapeado en OSM.
EXTRA_SAN_JOSE = re.compile(r"^(TEC - )?SJ-\s?\d")

# Erratas evidentes de la fuente (se corrige solo la ortografía).
CORRECCIONES = {
    "Curtura": "Cultura", "Parqieo": "Parqueo", "Igreso": "Ingreso", "Dociencia": "Docencia",
    "Metalugia": "Metalurgia", "Metereológica": "Meteorológica", "Tramiento": "Tratamiento",
    "parqueos residencias": "Parqueos residencias", "Admosférica": "Atmosférica",
}
SUPERFICIE = {
    "asphalt": "asfalto", "concrete": "concreto", "concrete:plates": "concreto", "concrete:lanes": "concreto",
    "paving_stones": "adoquin", "sett": "adoquin", "cobblestone": "adoquin", "gravel": "lastre",
    "fine_gravel": "lastre", "compacted": "lastre", "unpaved": "lastre", "pebblestone": "lastre",
    "ground": "tierra", "dirt": "tierra", "earth": "tierra", "grass": "tierra",
}
MATERIAL = {k: ("lastre" if v == "tierra" else v) for k, v in SUPERFICIE.items()}
VIAS = {
    "trunk": "principal", "primary": "principal", "secondary": "principal", "tertiary": "secundaria",
    "residential": "interna", "unclassified": "interna", "living_street": "interna",
    "service": "servicio", "track": "servicio",
}
POI_NOMBRE = [
    (re.compile(r"^laboratorio", re.I), "laboratorio"), (re.compile(r"^biblioteca", re.I), "biblioteca"),
    (re.compile(r"^(soda|comedor|restaurante)", re.I), "soda"), (re.compile(r"^cajero", re.I), "cajero"),
    (re.compile(r"^(cl[ií]nica)", re.I), "servicio_medico"),
    (re.compile(r"^(auditorio|mini auditorio)", re.I), "auditorio"),
]
POI_AMENITY = {
    "library": "biblioteca", "restaurant": "soda", "cafe": "soda", "fast_food": "soda", "food_court": "soda",
    "atm": "cajero", "bank": "cajero", "clinic": "servicio_medico", "doctors": "servicio_medico",
    "dentist": "servicio_medico", "theatre": "auditorio", "bus_station": "parada_bus",
}


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "sigtec-course-project"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def descargar():
    RAW.mkdir(parents=True, exist_ok=True)
    for node, way in LIMITES.items():
        full = get(f"{API}/way/{way}/full.json")
        time.sleep(2)
        points = [e for e in full["elements"] if e["type"] == "node"]
        lat, lon = [p["lat"] for p in points], [p["lon"] for p in points]
        pad = 0.0030 if node in ("san_jose", "limon") else 0.0008  # ~330 m de entorno donde el campus tiene poco mapeado
        box = (min(lon) - pad, min(lat) - pad, max(lon) + pad, max(lat) + pad)
        extract = get(API + "/map.json?bbox=%.6f,%.6f,%.6f,%.6f" % box)
        (RAW / f"{node}.raw.json").write_text(json.dumps(extract), encoding="utf-8")
        print("descargado", node, len(extract["elements"]), "elementos")
        time.sleep(3)


def contains(point, ring):
    x, y = point
    inside = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def near(point, ring, metros):
    """Distancia aproximada en metros del punto al anillo (suficiente para un margen)."""
    if contains(point, ring):
        return True
    kx, ky = 109600.0, 110600.0
    px, py = point[0] * kx, point[1] * ky
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        ax, ay, bx, by = x1 * kx, y1 * ky, x2 * kx, y2 * ky
        length = (bx - ax) ** 2 + (by - ay) ** 2
        t = 0 if not length else max(0, min(1, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / length))
        if (px - ax - t * (bx - ax)) ** 2 + (py - ay - t * (by - ay)) ** 2 <= metros ** 2:
            return True
    return False


def center(coords):
    points = coords[:-1] if len(coords) > 1 and coords[0] == coords[-1] else coords
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def join_rings(parts):
    """Une tramos de una relación multipolígono en anillos cerrados."""
    parts, rings = [list(p) for p in parts if len(p) > 1], []
    while parts:
        ring = parts.pop()
        while ring[0] != ring[-1]:
            for i, part in enumerate(parts):
                if part[0] == ring[-1]:
                    ring += part[1:]
                elif part[-1] == ring[-1]:
                    ring += part[::-1][1:]
                else:
                    continue
                parts.pop(i)
                break
            else:
                break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


def number(text, low, high):
    match = re.match(r"\s*(\d+(?:[.,]\d+)?)", text or "")
    if not match:
        return None
    value = float(match.group(1).replace(",", "."))
    return value if low <= value <= high else None


def clean(name):
    for wrong, right in CORRECCIONES.items():
        name = name.replace(wrong, right)
    return re.sub(r"\s+", " ", name).strip()[:110]


def poi_tipo(tags, name):
    for regex, tipo in POI_NOMBRE:
        if regex.search(name):
            return tipo
    if tags.get("highway") == "bus_stop":
        return "parada_bus"
    if tags.get("amenity") in POI_AMENITY:
        return POI_AMENITY[tags["amenity"]]
    if tags.get("healthcare"):
        return "servicio_medico"
    if tags.get("office"):
        return "oficina"
    return None


def preparar(node):
    raw = json.loads((RAW / f"{node}.raw.json").read_text(encoding="utf-8"))["elements"]
    nodes = {e["id"]: (round(e["lon"], 7), round(e["lat"], 7)) for e in raw if e["type"] == "node"}
    ways = {e["id"]: e for e in raw if e["type"] == "way"}
    limit = [nodes[i] for i in ways[LIMITES[node]]["nodes"]]
    features = []

    def add(element, capa, geometry, attrs, supuestos=()):
        features.append({
            "type": "Feature", "geometry": geometry,
            "properties": {
                "capa": capa, "atributos": attrs, "supuestos": sorted(supuestos),
                "osm": f"{element['type']}/{element['id']}", "osm_version": element.get("version"),
                "osm_fecha": element.get("timestamp"),
            },
        })

    def host(name):
        """En Alajuela la infraestructura es de la UTN, sede anfitriona: se indica en el nombre."""
        if node == "alajuela" and not re.search(r"\b(UTN|TEC)\b", name):
            return name + " (UTN)"
        return name

    def area_layers(element, polygons, tags):
        name = clean(tags["name"]) if tags.get("name") else ""
        for polygon in polygons:
            geometry = {"type": "Polygon", "coordinates": polygon}
            inside = contains(center(polygon[0]), limit)
            vecino = not inside and node in ENTORNO and near(center(polygon[0]), limit, ENTORNO[node])
            amenity = tags.get("amenity", "")
            if amenity in ("parking", "motorcycle_parking", "bicycle_parking") and (inside or vecino):
                capacity = number(tags.get("capacity"), 1, 5000)
                tipo = {"motorcycle_parking": "motocicletas", "bicycle_parking": "bicicletas"}.get(amenity, "general")
                supuestos = {"disponibilidad"}
                if capacity is None:
                    supuestos.add("capacidad")   # la importación la estima por área
                if tipo == "general":
                    supuestos.add("tipo")
                add(element, "parqueos", geometry,
                    {"capacidad": int(capacity) if capacity else None, "tipo": tipo}, supuestos)
                if name:
                    add(element, "puntos_interes", {"type": "Point", "coordinates": center(polygon[0])},
                        {"nombre": host(name), "tipo": "otro", "descripcion":
                         "Parqueo del entorno, no pertenece al TEC. Fuente: OpenStreetMap." if vecino
                         else "Parqueo. Fuente: OpenStreetMap."})
                continue
            if tags.get("building") and (inside or (node == "san_jose" and EXTRA_SAN_JOSE.match(name))):
                levels = number(tags.get("building:levels"), 1, 30)
                add(element, "edificios", geometry, {
                    "nombre": host(name) if name else "Edificio sin nombre en OSM",
                    "codigo": f"OSM-{element['type'][0].upper()}{element['id']}"
                              + (f"-{polygons.index(polygon) + 1}" if len(polygons) > 1 else ""),
                    "pisos": int(levels) if levels else 1,
                }, set() if levels else {"pisos"})
                tipo = poi_tipo(tags, name)
                if name and tipo:
                    add(element, "puntos_interes", {"type": "Point", "coordinates": center(polygon[0])},
                        {"nombre": host(name), "tipo": tipo, "descripcion": "Ubicado en el edificio del mismo nombre. Fuente: OpenStreetMap."})
                continue
            tipo, supuesto = None, set()
            landuse, leisure, natural = tags.get("landuse"), tags.get("leisure"), tags.get("natural")
            if landuse == "forest" or natural == "wood":
                tipo = "bosque"
            elif leisure == "garden":
                tipo = "jardin"
            elif natural == "scrub":
                tipo = "arbustos"
            elif landuse in ("grass", "village_green", "meadow") or natural == "grassland":
                tipo = "cesped"
            elif leisure == "pitch" and tags.get("sport", "") in ("soccer", "baseball;softball", "baseball") \
                    and tags.get("surface", "grass") == "grass":
                tipo, supuesto = "cesped", (set() if tags.get("surface") else {"tipo_vegetacion"})
            elif landuse in ("recreation_ground", "greenfield"):
                tipo, supuesto = "cesped", {"tipo_vegetacion"}
            elif leisure == "park" or landuse in ("park", "plant_nursery"):
                tipo, supuesto = "mixta", {"tipo_vegetacion"}
            if tipo and (inside or vecino or any(contains(p, limit) for p in polygon[0])):
                add(element, "zonas_verdes", geometry, {"tipo_vegetacion": tipo}, supuesto)
                if name and vecino:
                    add(element, "puntos_interes", {"type": "Point", "coordinates": center(polygon[0])},
                        {"nombre": name, "tipo": "otro", "descripcion":
                         "Área verde pública del entorno, no pertenece al TEC. Fuente: OpenStreetMap."})

    for element in raw:
        tags = element.get("tags")
        if not tags or (element["type"] == "way" and element["id"] in EXCLUIDOS | {LIMITES[node]}):
            continue
        name = clean(tags["name"]) if tags.get("name") else ""

        if element["type"] == "node":
            point = nodes[element["id"]]
            if not (contains(point, limit) or (tags.get("highway") == "bus_stop" and near(point, limit, 40))):
                continue
            tipo = poi_tipo(tags, name)
            if tags.get("highway") == "elevator":
                name, tipo = "Ascensor", "otro"
            if not tipo and name and not tags.get("place") and any(
                    k in tags for k in ("amenity", "office", "shop", "tourism", "leisure", "historic",
                                        "man_made", "natural", "attraction")):
                tipo = "otro"
            if tags.get("building") and tipo is None and name:
                tipo = "oficina"
            if not tipo:
                continue
            if not name:
                name = tags.get("brand") or {"parada_bus": "Parada de autobús", "cajero": "Cajero automático"}.get(tipo, "")
            if not name:
                continue
            detail = tags.get("description", "")
            if tags.get("wheelchair") == "yes":
                detail = (detail + " Accesible en silla de ruedas.").strip()
            add(element, "puntos_interes", {"type": "Point", "coordinates": point},
                {"nombre": host(name), "tipo": tipo, "descripcion": (detail + " Fuente: OpenStreetMap.").strip()})
            continue

        if element["type"] == "relation":
            if tags.get("type") != "multipolygon":
                continue
            coords = {"outer": [], "inner": []}
            complete = True
            for member in element["members"]:
                way = ways.get(member["ref"]) if member["type"] == "way" else None
                if way is None or any(i not in nodes for i in way["nodes"]):
                    complete = False
                    continue
                coords["inner" if member["role"] == "inner" else "outer"].append([nodes[i] for i in way["nodes"]])
            if not complete:
                continue
            outers, inners = join_rings(coords["outer"]), join_rings(coords["inner"])
            polygons = [[o] + [i for i in inners if contains(center(i), o)] for o in outers]
            area_layers(element, polygons, tags)
            continue

        if any(i not in nodes for i in element["nodes"]):
            continue
        coords = [nodes[i] for i in element["nodes"]]
        closed = len(coords) >= 4 and coords[0] == coords[-1]
        highway = tags.get("highway", "")
        base = highway.removesuffix("_link")
        touches = any(near(p, limit, max(MARGEN[node], ENTORNO.get(node, 0))) for p in coords)
        if base in VIAS and touches and tags.get("area") != "yes":
            tipo = VIAS[base]
            if tags.get("service") in ("driveway", "parking_aisle", "drive-through"):
                tipo = "acceso"
            if tipo == "interna" and not any(contains(p, limit) for p in coords[1:-1] or coords):
                tipo = "secundaria"
            surface = SUPERFICIE.get(tags.get("surface"))
            add(element, "carreteras", {"type": "LineString", "coordinates": coords}, {
                "nombre": name or (f"Ruta {tags['ref']}" if tags.get("ref") else "Vía sin nombre en OSM"),
                "tipo": tipo, "superficie": surface or ("lastre" if highway == "track" else "asfalto"),
            }, set() if surface else {"superficie"})
            continue
        if highway in ("footway", "path", "steps", "pedestrian", "corridor") and touches and tags.get("area") != "yes":
            accessible = (tags.get("wheelchair") in ("yes", "designated") or tags.get("ramp") == "yes"
                          or tags.get("ramp:wheelchair") == "yes" or tags.get("tactile_paving") == "yes")
            line = {"type": "LineString", "coordinates": coords}
            if accessible:
                kind = ("rampa" if tags.get("ramp") == "yes" or tags.get("ramp:wheelchair") == "yes"
                        else "paso_accesible" if tags.get("footway") == "crossing" else "ruta_accesible")
                add(element, "accesibilidad", line,
                    {"tipo": kind, "condicion": "regular",
                     "descripcion": "Etiquetada como accesible en OpenStreetMap."}, {"condicion"})
            if tags.get("footway") != "crossing" and tags.get("indoor") != "yes":
                supuestos = {"condicion"}
                material = MATERIAL.get(tags.get("surface"))
                width = number(tags.get("width"), 0.3, 20)
                if not material:
                    supuestos.add("material")
                if not width:
                    supuestos.add("ancho")
                add(element, "aceras", line,
                    {"material": material or "otro", "ancho": width or 1.5, "condicion": "regular"}, supuestos)
            continue
        if closed:
            area_layers(element, [[coords]], tags)

    # Un mismo servicio mapeado como nodo y como edificio: se conserva el nodo (más preciso).
    points = [f for f in features if f["properties"]["capa"] == "puntos_interes"]
    for f in points:
        if f["properties"]["osm"].startswith("node/"):
            continue
        x, y = f["geometry"]["coordinates"]
        for other in points:
            ox, oy = other["geometry"]["coordinates"]
            if (other["properties"]["osm"].startswith("node/")
                    and other["properties"]["atributos"]["tipo"] == f["properties"]["atributos"]["tipo"]
                    and ((x - ox) * 109600) ** 2 + ((y - oy) * 110600) ** 2 < 30 ** 2):
                features.remove(f)
                break

    order = ["edificios", "carreteras", "aceras", "parqueos", "zonas_verdes", "puntos_interes", "accesibilidad"]
    features.sort(key=lambda f: (order.index(f["properties"]["capa"]), f["properties"]["osm"],
                                 f["properties"]["atributos"].get("codigo", "")))
    dates = [e["timestamp"] for e in raw if e.get("timestamp")]
    collection = {
        "type": "FeatureCollection", "campus": node,
        "fuente": "© colaboradores de OpenStreetMap, ODbL 1.0 (https://www.openstreetmap.org/copyright)",
        "edicion_osm_mas_reciente": max(dates),
        "limite_osm": f"way/{LIMITES[node]}", "margen_m": MARGEN[node],
        "limite": {"type": "Polygon", "coordinates": [limit]}, "features": features,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(collection, ensure_ascii=False, separators=(",", ":")).replace('{"type":"Feature",', '\n{"type":"Feature",')
    (OUT / f"{node}.geojson").write_text(text + "\n", encoding="utf-8")
    count = {layer: sum(f["properties"]["capa"] == layer for f in features) for layer in order}
    print(node, count, "nombrados:", sum("sin nombre" not in f["properties"]["atributos"].get("nombre", "sin nombre")
                                         for f in features if f["properties"]["capa"] == "edificios"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--descargar", action="store_true")
    if parser.parse_args().descargar:
        descargar()
    for campus in LIMITES:
        preparar(campus)
