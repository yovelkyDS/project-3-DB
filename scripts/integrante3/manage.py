"""Instalación, verificación y empaquetado del bloque del Integrante 3.

No requiere pip: utiliza Python 3.10+, Docker Compose y las herramientas del
repositorio. Nunca imprime ni incluye contraseñas en argumentos de procesos.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PLUGIN_ROOT = ROOT / "qgis_plugin" / "sigtec"
DIST = ROOT / "dist"
STATE = ROOT / ".distributed-state"
NODES = ["cartago", "san_jose", "san_carlos", "alajuela", "limon"]
LAYERS = [
    "edificios", "carreteras", "aceras", "parqueos", "zonas_verdes",
    "puntos_interes", "iluminacion", "accesibilidad",
]
PASSWORD_KEYS = {node: "SIGTEC_QGIS_" + node.upper() + "_PASSWORD" for node in NODES}
PORT_KEYS = {
    "central": "SIGTEC_PORT_CENTRAL",
    "cartago": "SIGTEC_PORT_CARTAGO",
    "san_jose": "SIGTEC_PORT_SAN_JOSE",
    "san_carlos": "SIGTEC_PORT_SAN_CARLOS",
    "alajuela": "SIGTEC_PORT_ALAJUELA",
    "limon": "SIGTEC_PORT_LIMON",
}


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def env_values() -> dict[str, str]:
    path = ROOT / ".env"
    if not path.exists():
        raise RuntimeError("Falta .env; ejecute primero scripts/setup.sh")
    return {
        line.split("=", 1)[0]: line.split("=", 1)[1].strip().strip('"').strip("'")
        for line in path.read_text(encoding="utf-8-sig").splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    }


def service(node: str) -> str:
    routes = STATE / "routes.json"
    if routes.exists():
        mapping = json.loads(routes.read_text(encoding="utf-8"))
        if node in mapping:
            return mapping[node]
    return "pg-" + node.replace("_", "-")


def run_sql(node: str, statement: str, *, user: str = "postgres",
            password: str | None = None, expect_failure: bool = False) -> str:
    values = env_values()
    if password is None and user == "postgres":
        password = values["POSTGRES_PASSWORD"]
    process_env = os.environ.copy()
    args = ["docker", "compose", "exec", "-T", "-e", "PGCONNECT_TIMEOUT=5"]
    if password is not None:
        process_env["PGPASSWORD"] = password
        args += ["-e", "PGPASSWORD"]
    args += [service(node), "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1",
             "-h", "127.0.0.1", "-U", user, "-d", "sigtec"]
    result = subprocess.run(
        args, input=statement, text=True, encoding="utf-8", capture_output=True,
        cwd=ROOT, env=process_env, timeout=180,
    )
    if expect_failure:
        if result.returncode == 0:
            raise RuntimeError(f"La conexión que debía rechazarse fue aceptada en {node}")
        return ""
    if result.returncode:
        raise RuntimeError(f"Falló SQL en {node}; revise docker compose logs {service(node)}")
    return result.stdout.strip()


def require_integrante2() -> None:
    for node in NODES:
        role = "qgis_" + node
        ok = run_sql(node, "SELECT (EXISTS (SELECT FROM pg_roles WHERE rolname="
                     f"{sql_literal(role)}) AND to_regclass('qgis.v_edificios') IS NOT NULL)::int")
        if ok != "1":
            raise RuntimeError(
                f"{node} no tiene las vistas/cuenta del Integrante 2; ejecute make replication-setup"
            )


def install_auth() -> None:
    run_sql("central", (ROOT / "sql/integrante3/auth.sql").read_text(encoding="utf-8"))
    values = env_values()
    for campus_id, node in enumerate(NODES, 1):
        role = "qgis_" + node
        password = values.get(PASSWORD_KEYS[node], "")
        if not password or password == "__GENERAR__":
            raise RuntimeError(f"{PASSWORD_KEYS[node]} no contiene una contraseña generada")
        role_ident = identifier(role)
        statement = f"""
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname={sql_literal(role)}) THEN
    CREATE ROLE {role_ident} LOGIN;
  END IF;
END $$;
ALTER ROLE {role_ident} LOGIN PASSWORD {sql_literal(password)}
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
INSERT INTO auth.usuario_campus(usuario, campus_id, activo)
VALUES ({sql_literal(role)}, {campus_id}, true)
ON CONFLICT (usuario) DO UPDATE SET campus_id=EXCLUDED.campus_id, activo=true;
GRANT USAGE ON SCHEMA auth TO {role_ident};
GRANT EXECUTE ON FUNCTION auth.sesion_campus() TO {role_ident};
"""
        run_sql("central", statement)
    print("OK autenticación central: cinco cuentas y asignaciones sincronizadas")


def install_styles() -> None:
    run_sql("central", (ROOT / "sql/integrante3/layer_styles.sql").read_text(encoding="utf-8"))
    for layer in LAYERS:
        qml = (PLUGIN_ROOT / "styles" / f"{layer}.qml").read_text(encoding="utf-8")
        statement = f"""
DELETE FROM public.layer_styles
 WHERE f_table_catalog='sigtec' AND f_table_schema='qgis'
   AND f_table_name={sql_literal('v_' + layer)} AND stylename='SIG-TEC institucional';
INSERT INTO public.layer_styles
 (f_table_catalog, f_table_schema, f_table_name, f_geometry_column,
  stylename, styleqml, useasdefault, description, owner, update_time, type)
VALUES
 ('sigtec', 'qgis', {sql_literal('v_' + layer)}, 'geom',
  'SIG-TEC institucional', {sql_literal(qml)}::xml, true,
  'Simbología institucional SIG-TEC v1.0', current_user, clock_timestamp(), NULL);
"""
        run_sql("central", statement)

    # Reutiliza la distribución de layer_styles acordada con el Integrante 2.
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts/distributed/manage.py"), "styles"],
        cwd=ROOT, text=True, encoding="utf-8",
    )
    if result.returncode:
        raise RuntimeError("No se pudo habilitar la distribución de layer_styles")
    print("OK ocho estilos institucionales guardados en central y distribuidos")


def verify(wait_seconds: int = 60) -> None:
    values = env_values()
    errors: list[str] = []
    mapping = run_sql(
        "central",
        "SELECT coalesce(string_agg(usuario::text || ':' || campus_id, ',' ORDER BY campus_id),'') "
        "FROM auth.usuario_campus WHERE activo",
    )
    expected = ",".join(f"qgis_{node}:{index}" for index, node in enumerate(NODES, 1))
    if mapping != expected:
        errors.append(f"asignación central inesperada: {mapping}")

    for campus_id, node in enumerate(NODES, 1):
        role = "qgis_" + node
        password = values[PASSWORD_KEYS[node]]
        result = run_sql(
            "central", "SELECT campus_id || ':' || node_code FROM auth.sesion_campus()",
            user=role, password=password,
        )
        if result != f"{campus_id}:{node}":
            errors.append(f"{role}: central devolvió {result!r}")
        bad_password = password + "-incorrecta"
        run_sql("central", "SELECT 1", user=role, password=bad_password, expect_failure=True)

        view_count = run_sql(
            node,
            "SELECT count(*) FROM information_schema.views WHERE table_schema='qgis' "
            "AND table_name IN (" + ",".join(sql_literal("v_" + layer) for layer in LAYERS) + ")",
            user=role, password=password,
        )
        if view_count != "8":
            errors.append(f"{node}: la cuenta ve {view_count}/8 vistas")

    deadline = time.monotonic() + wait_seconds
    pending = set(NODES)
    while pending and time.monotonic() < deadline:
        for node in list(pending):
            if run_sql(node, "SELECT count(*) FROM public.layer_styles WHERE "
                       "f_table_catalog='sigtec' AND f_table_schema='qgis' "
                       "AND useasdefault") == "8":
                pending.remove(node)
        if pending:
            time.sleep(1)
    if pending:
        errors.append("estilos sin sincronizar en: " + ", ".join(sorted(pending)))

    if errors:
        raise RuntimeError("Verificación I3 fallida:\n- " + "\n- ".join(errors))
    print("OK I3: 5 sesiones, rechazo de claves incorrectas, 40 vistas y 8 estilos por campus")


def package() -> Path:
    DIST.mkdir(exist_ok=True)
    target = DIST / "sigtec_qgis.zip"
    config_path = PLUGIN_ROOT / "config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    # El contrato usa 55430–55435, pero Windows/Hyper-V puede reservarlos.
    # Si existe .env, el ZIP debe reflejar los puertos efectivos sin modificar
    # el config.json versionado ni incluir ninguna contraseña.
    if (ROOT / ".env").exists():
        values = env_values()
        config["central"]["port"] = int(values.get(PORT_KEYS["central"], config["central"]["port"]))
        for node in NODES:
            config["campuses"][node]["port"] = int(
                values.get(PORT_KEYS[node], config["campuses"][node]["port"])
            )
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(PLUGIN_ROOT.rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                destination = Path("sigtec") / path.relative_to(PLUGIN_ROOT)
                if path == config_path:
                    archive.writestr(str(destination).replace("\\", "/"),
                                     json.dumps(config, ensure_ascii=False, indent=2) + "\n")
                else:
                    archive.write(path, destination)
    print(f"OK complemento instalable: {target.relative_to(ROOT)}")
    return target


def setup() -> None:
    require_integrante2()
    install_auth()
    install_styles()
    verify()
    package()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["setup", "verify", "package"])
    parser.add_argument("--wait-seconds", type=int, default=60)
    args = parser.parse_args()
    if args.action == "setup":
        setup()
    elif args.action == "verify":
        verify(args.wait_seconds)
    else:
        package()


if __name__ == "__main__":
    main()
