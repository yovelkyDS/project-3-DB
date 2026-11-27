"""Administración del integrante 2. Python 3.10+, Docker Compose v2; sin pip.
Ejecutar desde cualquier carpeta: python scripts/distributed/manage.py --help.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[2]
NODES = ['cartago', 'san_jose', 'san_carlos', 'alajuela', 'limon']
LAYERS = ['edificios', 'carreteras', 'aceras', 'parqueos', 'zonas_verdes', 'puntos_interes', 'iluminacion', 'accesibilidad']
STATE = ROOT / '.distributed-state'


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def ident(s):
    return '"' + str(s).replace('"', '""') + '"'


def service(node):
    routes=STATE / 'routes.json'
    mapping=json.loads(routes.read_text()) if routes.exists() else {}
    return mapping.get(node, 'pg-' + node.replace('_', '-'))


def sql(node, statement, user='postgres', password=None):
    # No contraseñas en argumentos, logs ni excepciones. stdin evita quoting del shell.
    args = ['docker', 'compose', 'exec', '-T', '-e', 'PGCONNECT_TIMEOUT=5']
    env = os.environ.copy()
    if password is None and user=='postgres':
        password=env_values()['POSTGRES_PASSWORD'].strip().strip(chr(34)).strip(chr(39))
    if password is not None:
        env['PGPASSWORD'] = password
        args += ['-e', 'PGPASSWORD']
    args += [service(node), 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
             '-h', '127.0.0.1', '-U', user, '-d', 'sigtec']
    p = subprocess.run(args, input=statement, text=True, encoding='utf-8',
                       capture_output=True, cwd=ROOT, env=env, timeout=180)
    if p.returncode:
        # CREATE SUBSCRIPTION / ALTER ROLE pueden incluir secretos en errores del servidor.
        raise RuntimeError(f'SQL falló en {node}; revise docker compose logs {service(node)} (pueden contener secretos).')
    return p.stdout.strip()


def env_values():
    return dict(line.split('=', 1) for line in (ROOT / '.env').read_text(encoding='utf-8-sig').splitlines()
                if '=' in line and not line.lstrip().startswith('#'))


def ensure_secret():
    values = env_values()
    if values.get('SIGTEC_REPL_PASSWORD', '__GENERAR__') == '__GENERAR__':
        path=ROOT / '.env'
        lines=[line for line in path.read_text(encoding='utf-8-sig').splitlines() if not line.startswith('SIGTEC_REPL_PASSWORD=')]
        path.write_text('\n'.join(lines)+'\nSIGTEC_REPL_PASSWORD='+secrets.token_hex(32)+'\n',encoding='utf-8')
    return env_values()['SIGTEC_REPL_PASSWORD'].strip().strip('"').strip("'")


def wait_ready(node, name, timeout=180):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        ready = sql(node, f"SELECT count(*)>0 AND bool_and(srsubstate='r') FROM pg_subscription_rel WHERE srsubid=(SELECT oid FROM pg_subscription WHERE subname={lit(name)})")
        if ready == 't':
            return
        time.sleep(1)
    raise RuntimeError(f'Suscripción {name} en {node} no sincronizó en {timeout}s')


def subscribe(node, name, publisher, publication, password):
    if sql(node, f'SELECT 1 FROM pg_subscription WHERE subname={lit(name)}'):
        return
    # libpq conninfo: secreto hex generado, sin caracteres de control.
    conn = f'host={service(publisher)} port=5432 dbname=sigtec user=sigtec_repl password={password} sslmode=require'
    sql(node, f'CREATE SUBSCRIPTION {ident(name)} CONNECTION {lit(conn)} PUBLICATION {ident(publication)} WITH (copy_data=true, origin=any, slot_name={lit(name + "_" + node)})')


def publication(node, name, tables):
    if not sql(node, f'SELECT 1 FROM pg_publication WHERE pubname={lit(name)}'):
        sql(node, f'CREATE PUBLICATION {ident(name)} FOR TABLE ' + ','.join(tables) + " WITH (publish='insert,update,delete')")


def create_global(node, source_schema):
    for layer in LAYERS:
        sql(node, f'''CREATE TABLE IF NOT EXISTS global.{layer}
            (LIKE {source_schema}.{layer} INCLUDING DEFAULTS);
            ALTER TABLE global.{layer} ALTER COLUMN campus_id DROP DEFAULT;
            DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='global.{layer}'::regclass AND contype='p') THEN
            ALTER TABLE global.{layer} ADD PRIMARY KEY(id); END IF; END $$;
            CREATE INDEX IF NOT EXISTS {layer}_global_geom_gix ON global.{layer} USING gist(geom);
            REVOKE ALL ON global.{layer} FROM PUBLIC;''')


def setup():
    if (STATE/'routes.json').exists():
        raise RuntimeError('Existe una ruta de recuperación. Use verify; no reaplique setup sobre una reincorporación.')
    password = ensure_secret()
    if not password or not password.isascii() or not password.isalnum():
        raise RuntimeError('SIGTEC_REPL_PASSWORD debe contener solo letras ASCII y digitos; use una clave aleatoria.')
    for node in ['central'] + NODES:
        print('Preparando', node, flush=True)
        if sql(node, 'SHOW max_prepared_transactions') == '0':
            raise RuntimeError(
                'Reconstruya la imagen con docker compose build pg-central y recree los nodos con '
                'docker compose up -d --force-recreate para habilitar max_prepared_transactions=16.'
            )
        sql(node, (ROOT / 'sql/distributed/functions.sql').read_text(encoding='utf-8-sig'))
        sql(node, f"DO $$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='sigtec_repl') THEN CREATE ROLE sigtec_repl LOGIN REPLICATION; END IF; END $$; ALTER ROLE sigtec_repl PASSWORD {lit(password)};")
    # La plantilla no es idempotente: aplicar únicamente esquemas ausentes, con transacción.
    source = (ROOT / 'sql/schema/capas_locales.sql').read_text(encoding='utf-8-sig')
    for cid, node in enumerate(NODES, 1):
        schema = 'local_' + node
        if sql('central', f'SELECT to_regclass({lit(schema+".edificios")})') == '':
            sql('central', f'\\set schema {schema}\n\\set campus_id {cid}\nBEGIN;\n' + source + '\nCOMMIT;')
    create_global('central', 'local_cartago')
    for node in NODES:
        schema = 'local_' + node
        create_global(node, schema)
        for layer in LAYERS:
            sql('central', f'''DROP TRIGGER IF EXISTS consolidar ON {schema}.{layer};
                CREATE TRIGGER consolidar AFTER INSERT OR UPDATE OR DELETE ON {schema}.{layer}
                FOR EACH ROW EXECUTE FUNCTION ops.consolidar_capa();
                ALTER TABLE {schema}.{layer} ENABLE ALWAYS TRIGGER consolidar;''')
        sql(node, f'GRANT USAGE ON SCHEMA {schema} TO sigtec_repl; GRANT SELECT ON ALL TABLES IN SCHEMA {schema} TO sigtec_repl;')
        publication(node, 'sigtec_local', [f'{schema}.{t}' for t in LAYERS])
        subscribe('central', 'sigtec_from_' + node, node, 'sigtec_local', password)
    for node in NODES:
        wait_ready('central', 'sigtec_from_' + node)
    # Initial COPY y reejecución: reconciliar bajo bloqueo de las tablas origen del central.
    for layer in LAYERS:
        origins = [f'local_{n}.{layer}' for n in NODES]
        sql('central', 'BEGIN; LOCK TABLE ' + ','.join(origins) + ' IN SHARE MODE; '
            + f'DELETE FROM global.{layer}; INSERT INTO global.{layer} '
            + ' UNION ALL '.join('SELECT * FROM '+s for s in origins) + '; COMMIT;')
    sql('central', 'GRANT USAGE ON SCHEMA global TO sigtec_repl; GRANT SELECT ON ALL TABLES IN SCHEMA global TO sigtec_repl;')
    publication('central', 'sigtec_global', ['global.' + t for t in LAYERS])
    for cid, node in enumerate(NODES, 1):
        subscribe(node, 'sigtec_from_central', 'central', 'sigtec_global', password)
        wait_ready(node, 'sigtec_from_central')
        configure_views(node, cid)
    verify()


def configure_views(node, cid):
    schema = 'local_' + NODES[cid-1]
    role = 'qgis_' + NODES[cid-1]
    password = env_values().get('SIGTEC_QGIS_' + NODES[cid-1].upper() + '_PASSWORD', '').strip().strip('"').strip("'")
    if not password or password == '__GENERAR__':
        raise RuntimeError('Primero ejecute el instalador I1 para generar contraseñas QGIS')
    sql(node, f"DO $$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname={lit(role)}) THEN CREATE ROLE {ident(role)} LOGIN; END IF; END $$; ALTER ROLE {ident(role)} PASSWORD {lit(password)}; INSERT INTO ops.editor_campus VALUES({lit(role)},{cid}) ON CONFLICT(usuario) DO UPDATE SET campus_id=EXCLUDED.campus_id; GRANT USAGE ON SCHEMA qgis TO {ident(role)};")
    for layer in LAYERS:
        sql(node, f'''CREATE OR REPLACE VIEW qgis.v_{layer} AS
            SELECT * FROM {schema}.{layer} UNION ALL SELECT * FROM global.{layer} WHERE campus_id<>{cid};
            DROP TRIGGER IF EXISTS editar ON qgis.v_{layer};
            CREATE TRIGGER editar INSTEAD OF INSERT OR UPDATE OR DELETE ON qgis.v_{layer}
              FOR EACH ROW EXECUTE FUNCTION ops.editar_capa('{layer}');
            GRANT SELECT,INSERT,UPDATE,DELETE ON qgis.v_{layer} TO {ident(role)};
            REVOKE ALL ON {schema}.{layer},global.{layer} FROM {ident(role)};''')


def snapshot(node, table):
    # Compara cada columna por identificador, incluida geometría EWKB y atributos.
    return sql(node, f"SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY id),'[]'::jsonb) FROM {table} t")


def bulk_snapshot(node, schemas):
    parts=[]
    for schema in schemas:
        for layer in LAYERS:
            table=schema+'.'+('v_' if schema=='qgis' else '')+layer
            parts += [lit(table),f"(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY id),'[]'::jsonb) FROM {table} t)"]
    return json.loads(sql(node,'SELECT jsonb_build_object('+','.join(parts)+')'))


def verify(timeout=120):
    end=time.monotonic()+timeout
    while True:
        failures=[]
        with ThreadPoolExecutor(max_workers=6) as pool:
            c=pool.submit(bulk_snapshot,'central',['global']+['local_'+n for n in NODES])
            jobs={n:pool.submit(bulk_snapshot,n,['local_'+n,'global','qgis']) for n in NODES}
            central=c.result()
            campuses={n:f.result() for n,f in jobs.items()}
        for layer in LAYERS:
            combined=[]
            for node in NODES:
                key='local_'+node+'.'+layer
                rows=campuses[node][key]
                combined.extend(rows)
                if rows!=central[key]: failures.append(node+'->'+layer+'->central')
            combined.sort(key=lambda x:x['id'])
            if combined!=central['global.'+layer]: failures.append('central.global.'+layer)
            for node in NODES:
                for schema in ['global.','qgis.v_']:
                    if combined!=campuses[node][schema+layer]: failures.append(node+'.'+schema+layer)
        if not failures:
            print('OK: ocho capas, filas y atributos iguales en ambas rutas; vistas sin perdidas ni duplicados.')
            return
        if time.monotonic()>=end: raise RuntimeError('Diferencias: '+', '.join(failures))
        time.sleep(2)


def persist(path, value):
    STATE.mkdir(exist_ok=True)
    temp=path.with_suffix('.tmp')
    with temp.open('w',encoding='utf-8') as f:
        json.dump(value,f); f.flush(); os.fsync(f.fileno())
    os.replace(temp,path)


def resolve(path):
    data=json.loads(path.read_text(encoding='utf-8'))
    decision=data.get('decision','abort')
    for node in data['nodes']:
        if sql(node, f'SELECT 1 FROM pg_prepared_xacts WHERE gid={lit(data["gid"])}'):
            sql(node, ('COMMIT' if decision=='commit' else 'ROLLBACK')+' PREPARED '+lit(data['gid']))
    data['resolved']=True
    persist(path,data)


def transaction(node, fail=False, crash=False):
    gid='sigtec_'+uuid.uuid4().hex
    path=STATE/(gid+'.json')
    data={'gid':gid,'nodes':[node,'central'],'decision':'abort','resolved':False}
    # Presumed abort persistido ANTES de preparar el primer participante.
    persist(path,data)
    try:
        for index,participant in enumerate(data['nodes']):
            if fail and index==1: raise RuntimeError('Falla simulada antes de preparar central')
            sql(participant, f"BEGIN; SET LOCAL lock_timeout='10s'; INSERT INTO ops.operaciones_distribuidas VALUES ({lit(gid)},'Demostracion autorizada campus-central',now()); PREPARE TRANSACTION {lit(gid)};")
        data['decision']='commit'
        persist(path,data)
        if crash:
            print('Decisión COMMIT persistida; interrupción simulada. Ejecute resolve. GID:',gid)
            return gid
    except Exception:
        resolve(path)
        if not fail: raise
    else:
        resolve(path)
    expected='0' if fail else '1'
    for participant in data['nodes']:
        assert sql(participant, f'SELECT count(*) FROM ops.operaciones_distribuidas WHERE id={lit(gid)}')==expected
    print('OK 2PC', 'reversión completa' if fail else 'confirmación en ambos',gid)
    return gid


def styles():
    if not sql('central', "SELECT to_regclass('public.layer_styles')"):
        raise RuntimeError('I3 debe crear public.layer_styles en central antes de habilitar su distribución')
    # DDL exacto del creador QGIS; no imponer una firma especulativa.
    p=subprocess.run(['docker','compose','exec','-T','--user','postgres','pg-central','pg_dump','-U','postgres','-d','sigtec',
                      '--schema-only','--no-owner','--no-privileges','-t','public.layer_styles'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
    if p.returncode: raise RuntimeError('No se pudo exportar DDL de layer_styles')
    sql('central','ALTER TABLE public.layer_styles REPLICA IDENTITY FULL; GRANT SELECT ON public.layer_styles TO sigtec_repl;')
    publication('central','sigtec_styles',['public.layer_styles'])
    for node in NODES:
        if not sql(node,"SELECT to_regclass('public.layer_styles')"):
            sql(node,p.stdout)
        sql(node,'ALTER TABLE public.layer_styles REPLICA IDENTITY FULL;')
        # Un nodo reincorporado tras PITR necesita ranura nueva: la anterior sigue reservada en central.
        name='sigtec_rejoined_styles' if service(node)=='pg-recovery' else 'sigtec_styles'
        if name!='sigtec_styles' and not sql(node,f'SELECT 1 FROM pg_subscription WHERE subname={lit(name)}'):
            # Es solo una copia de central; se vacia para que la copia inicial no choque con la PK.
            sql(node,'DELETE FROM public.layer_styles;')
        subscribe(node,name,'central','sigtec_styles',ensure_secret())
        wait_ready(node,name)
        sql(node,f'GRANT SELECT ON public.layer_styles TO {ident("qgis_"+node)};')
    print('Estilos distribuidos; modificar solamente en central.')


def detach(node, name):
    if sql(node,f'SELECT 1 FROM pg_subscription WHERE subname={lit(name)}'):
        sql(node,f'ALTER SUBSCRIPTION {ident(name)} DISABLE; ALTER SUBSCRIPTION {ident(name)} SET (slot_name=NONE);')
        sql(node,f'DROP SUBSCRIPTION {ident(name)};')


def rejoin(node):
    """PITR autoritativo: reemplaza copias de ese origen, conservando originales en pg-recovery.
    El nodo original debe estar detenido. No elimina datos originales ni volúmenes.
    """
    original='pg-'+node.replace('_','-')
    running=subprocess.run(['docker','compose','--profile','recovery','ps','--status','running','--services'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',check=True).stdout.splitlines()
    if original in running:
        raise RuntimeError('Detenga primero '+original+'; no se admiten dos dueños activos.')
    if 'pg-recovery' not in running:
        raise RuntimeError('pg-recovery no está en ejecución')
    if sql('recovery','SELECT node_code FROM ops.node_info WHERE singleton')!=node:
        raise RuntimeError('La instancia recuperada pertenece a otro campus')
    # Requisito RA-01: no reincorporar un PITR sin registro global y migración 0103.
    if sql('recovery',"SELECT to_regclass('ops.identificadores_globales')")=='':
        raise RuntimeError('Ejecute make migrate NODE=recovery y make recovery-status antes de reincorporar')
    status=sql('recovery', f'\\set schema local_{node}\n' + (ROOT/'sql/checks/verificar_registro_ids.sql').read_text(encoding='utf-8-sig'))
    if status.split('|')[-1] != 'OK':
        raise RuntimeError('Registro de identificadores inválido en recovery')
    if sql('central', f"SELECT 1 FROM pg_subscription WHERE subname={lit('sigtec_rejoin_'+node)}"):
        raise RuntimeError('Ya existe una reincorporación; revise su estado antes de repetir')
    cid=NODES.index(node)+1
    # Guardar evidencia ANTES de reconciliar; contiene filas posteriores al PITR que se retirarán.
    evidence={'node':node,'policy':'PITR autoritativo','central':{t:json.loads(snapshot('central','local_'+node+'.'+t)) for t in LAYERS}}
    persist(STATE/('before_rejoin_'+uuid.uuid4().hex+'.json'),evidence)
    role='qgis_'+node
    sql('recovery',f"DO $$ BEGIN IF EXISTS(SELECT FROM pg_roles WHERE rolname={lit(role)}) THEN ALTER ROLE {ident(role)} NOLOGIN; END IF; END $$;")
    sql('recovery',f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename={lit(role)} AND pid<>pg_backend_pid();")
    detach('recovery','sigtec_from_central')
    detach('recovery','sigtec_styles')
    detach('central','sigtec_from_'+node)
    # Evitar reutilizar ids ya vistos (incluye objetos borrados gracias al highwater).
    high=int(sql('central',f'SELECT coalesce(max(id),0) FROM ops.replication_highwater WHERE campus_id={cid}'))
    local_seq=int(sql('recovery',f'SELECT last_value FROM local_{node}.objeto_id_seq'))
    floor=max(local_seq,high-cid*1000000000,1)
    sql('recovery',f"SELECT setval('local_{node}.objeto_id_seq',{floor},true);")
    for layer in LAYERS:
        sql('central',f'DELETE FROM local_{node}.{layer};')
    routes=STATE/'routes.json'
    mapping=json.loads(routes.read_text()) if routes.exists() else {}
    mapping[node]='pg-recovery'
    persist(routes,mapping)
    # El PITR puede preceder a la instalación de I2.
    sql(node,(ROOT/'sql/distributed/functions.sql').read_text(encoding='utf-8-sig'))
    password=ensure_secret()
    sql(node,f"DO $$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='sigtec_repl') THEN CREATE ROLE sigtec_repl LOGIN REPLICATION; END IF; END $$; ALTER ROLE sigtec_repl PASSWORD {lit(password)}; GRANT USAGE ON SCHEMA local_{node} TO sigtec_repl; GRANT SELECT ON ALL TABLES IN SCHEMA local_{node} TO sigtec_repl;")
    publication(node,'sigtec_local',[f'local_{node}.{t}' for t in LAYERS])
    # Nueva ranura: el PITR no recupera las ranuras y la anterior del central queda reservada.
    name='sigtec_rejoin_'+node
    if sql('central',f'SELECT 1 FROM pg_subscription WHERE subname={lit(name)}'):
        raise RuntimeError('Ya existe una reincorporación; revise estado antes de repetir')
    subscribe('central',name,node,'sigtec_local',password)
    wait_ready('central',name)
    create_global(node,'local_'+node)
    sql(node,'TRUNCATE '+','.join('global.'+t for t in LAYERS)+';')
    subscribe(node,'sigtec_rejoined_global','central','sigtec_global',password)
    wait_ready(node,'sigtec_rejoined_global')
    configure_views(node,cid)
    verify()
    sql(node,f'ALTER ROLE {ident(role)} LOGIN;')
    print('Reincorporación verificada. QGIS debe usar puerto 55436. Nodo original permanece detenido.')


@contextmanager
def coordinator_lock():
    # Exclusión entre setup, resolve, rejoin y nuevas decisiones en esta PC.
    STATE.mkdir(exist_ok=True)
    with (STATE/'coordinator.lock').open('a+b') as handle:
        handle.seek(0); handle.write(b'0'); handle.flush(); handle.seek(0)
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(handle.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(),fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            handle.seek(0)
            if os.name=='nt': msvcrt.locking(handle.fileno(),msvcrt.LK_UNLCK,1)
            else: fcntl.flock(handle.fileno(),fcntl.LOCK_UN)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['setup','verify','transaction','resolve','styles','rejoin'])
    p.add_argument('--node',choices=NODES,default='san_carlos')
    p.add_argument('--fail',action='store_true')
    p.add_argument('--crash-after-decision',action='store_true')
    a=p.parse_args()
    if a.action=='setup': setup()
    elif a.action=='verify': verify()
    elif a.action=='transaction': transaction(a.node,a.fail,a.crash_after_decision)
    elif a.action=='styles': styles()
    elif a.action=='rejoin': rejoin(a.node)
    else:
        for path in STATE.glob('sigtec_*.json'):
            if not json.loads(path.read_text())['resolved']: resolve(path)
        print('Decisiones pendientes resueltas.')


if __name__=='__main__':
    with coordinator_lock():
        main()
