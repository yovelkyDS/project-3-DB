"""Carga la geografía real (data/osm/*.geojson) en los campus. Idempotente; solo biblioteca estándar.

  python3 scripts/datos/importar.py [campus ...] [--sin-respaldo]

Antes de modificar un campus crea un respaldo lógico del nodo. Cada campus se importa en una
sola transacción y la replicación distribuye el resultado al central y a los demás campus.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "scripts" / "distributed"), str(ROOT / "scripts" / "datos")]
from manage import LAYERS, NODES, lit, sql, verify  # noqa: E402
from preparar_osm import ENTORNO  # noqa: E402

SEED = "datos_osm_v1"
PREFIJOS = {"cartago": "CA", "san_jose": "SJ", "san_carlos": "SC", "alajuela": "AL", "limon": "LI"}


def guion(node):
    data = json.loads((ROOT / "data" / "osm" / f"{node}.geojson").read_text(encoding="utf-8"))
    docs = [{"limite": data["limite"]}] + data["features"]
    rows = "\n".join(f"{i}\x02{json.dumps(doc, ensure_ascii=True)}" for i, doc in enumerate(docs))
    config = {
        "imp_schema": "local_" + node, "imp_campus": NODES.index(node) + 1, "imp_prefijo": PREFIJOS[node],
        "imp_margen": data["margen_m"], "imp_entorno": ENTORNO.get(node, 0),
    }
    sets = "".join(f"SELECT set_config('sigtec.{k}', {lit(v)}, true);\n" for k, v in config.items())
    return ("BEGIN;\nCREATE TEMP TABLE _entrada (orden int, doc jsonb) ON COMMIT DROP;\n"
            "COPY _entrada FROM STDIN WITH (FORMAT csv, DELIMITER E'\\x02', QUOTE E'\\x01');\n"
            + rows + "\n\\.\n" + sets + (ROOT / "sql/datos/importar_osm_v1.sql").read_text(encoding="utf-8") + "\nCOMMIT;\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("campus", nargs="*", metavar="campus", help=", ".join(NODES))
    parser.add_argument("--sin-respaldo", action="store_true", help="solo si el respaldo acaba de hacerse")
    args = parser.parse_args()
    for node in args.campus:
        if node not in NODES:
            parser.error(f"campus no válido: {node}")
    cambios = False
    for node in args.campus or NODES:
        if sql(node, f"SELECT count(*) FROM ops.seed_runs WHERE seed_name = {lit(SEED)}") != "0":
            print(f"{node}: {SEED} ya estaba cargado (sin cambios)")
            continue
        if not args.sin_respaldo:
            print(f"{node}: respaldo lógico previo...", flush=True)
            subprocess.run(["bash", "scripts/backup/run.sh", "logical_backup.sh", node], cwd=ROOT, check=True)
        sql(node, guion(node))
        cambios = True
        filas = sql(node, "SELECT string_agg(capa || '=' || n, ' ' ORDER BY capa) FROM (SELECT capa || '(' || fuente || ')' AS capa, count(*) n FROM ops.procedencia_objetos GROUP BY 1) t")
        print(f"{node}: {filas}", flush=True)
        for layer in LAYERS:
            if sql(node, f"SELECT count(*) FROM local_{node}.{layer}") == "0":
                raise RuntimeError(f"{node}: la capa {layer} quedó vacía")
    if cambios and sql("central", "SELECT to_regclass('global.edificios') IS NOT NULL") == "t":
        verify()


if __name__ == "__main__":
    main()
