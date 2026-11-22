"""Read-only inventory and independent adversarial probes. No application edits."""
import concurrent.futures as cf
import hashlib
import json
import subprocess as sp
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'audit/reaudit/raw'
LAYERS = 'edificios carreteras aceras parqueos zonas_verdes puntos_interes iluminacion accesibilidad'.split()
NODES = 'central cartago san_jose san_carlos alajuela limon'.split()
DC = ['docker', 'compose', '--project-directory', str(ROOT/'remediation/lab'), '-f', str(ROOT/'remediation/lab/compose.yaml')]
records = []

def run(args, data=None, timeout=180):
    p = sp.run(args, input=data, text=True, capture_output=True, timeout=timeout)
    return dict(rc=p.returncode, stdout=p.stdout, stderr=p.stderr)

def sql(node, query, project='sigtec_remed', app=None):
    args = ['docker','exec','-i','-u','postgres']
    if app: args += ['-e',f'PGAPPNAME={app}']
    args += [project+'-pg-'+node.replace('_','-')+'-1','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-d','sigtec']
    return run(args, query)

def check(name, condition, evidence):
    records.append(dict(name=name, passed=bool(condition), evidence=evidence))
    print(('PASS ' if condition else 'FAIL ')+name, flush=True)

def union(s):
    return ' UNION ALL '.join(f"SELECT id,'{l}' capa,to_jsonb(t)::text payload FROM {s}.{l} t" for l in LAYERS)

def inventory(suffix):
    result = {}
    for proj in ['sigtec','sigtec_remed']:
        for n in NODES+['recovery']:
            s = 'local_san_carlos' if n=='recovery' else 'local_'+n
            q = "BEGIN READ ONLY; SELECT version(); SELECT postgis_full_version(); SELECT system_identifier FROM pg_control_system(); SELECT timeline_id FROM pg_control_checkpoint(); SELECT pg_is_in_recovery(); SELECT version FROM ops.schema_migrations ORDER BY version; SELECT current_setting('wal_level'),current_setting('max_prepared_transactions'),current_setting('max_replication_slots');"
            if n!='central':
                q += f"WITH o AS ({union(s)}) SELECT count(*),count(DISTINCT id),md5(string_agg(payload,'|' ORDER BY id,capa)) FROM o;"
                q += f"SELECT count(*),count(*) FILTER(WHERE tgenabled<>'O') FROM pg_trigger t JOIN pg_class c ON c.oid=tgrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='{s}' AND NOT tgisinternal;"
                q += "SELECT to_regclass('ops.identificadores_globales');"
            q += 'COMMIT;'
            result[proj+'/'+n] = sql(n,q,proj)
    ids=[]
    for n in NODES[1:]:
        r=sql(n,f"BEGIN READ ONLY; WITH o AS ({union('local_'+n)}) SELECT id FROM o ORDER BY id; COMMIT;",'sigtec')
        ids += [int(x) for x in r['stdout'].splitlines()]
    result['original_global_ids'] = dict(objects=len(ids),distinct=len(set(ids)),duplicates=len(ids)-len(set(ids)))
    result['docker'] = run(['docker','ps','--format','{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'])
    result['volumes'] = run(['docker','volume','ls','--format','{{.Name}}'])
    result['images'] = run(['docker','image','ls','--no-trunc','--format','{{.Repository}}:{{.Tag}}\t{{.ID}}'])
    result['running_image_ids'] = run(['docker','inspect','--format','{{.Name}} {{.Image}}',*[p+'-pg-'+n.replace('_','-')+'-1' for p in ['sigtec','sigtec_remed'] for n in NODES]])
    for proj in ['sigtec','sigtec_remed']:
        result[proj+'/binaries']=run(['docker','exec',proj+'-pg-cartago-1','bash','-c','sha256sum /usr/lib/postgresql/17/bin/postgres /usr/lib/postgresql/17/lib/postgis-3.so; dpkg-query -W libgeos-c1t64 libproj25 postgresql-17'])
    (OUT/f'inventory_{suffix}.json').write_text(json.dumps(result,indent=2))
    print('inventory saved',suffix)

def ids():
    s='local_cartago'; pt='ST_SetSRID(ST_MakePoint(510000,1090000),5367)'
    def insert(table, ident=None, label='reaudit'):
        if table=='puntos_interes': cols="nombre,tipo,geom"; vals=f"'{label}','otro',{pt}"
        else: cols='codigo,potencia,estado,geom'; vals=f"'{label}',100,'funcional',{pt}"
        if ident is not None: cols='id,'+cols; vals=str(ident)+','+vals
        return f'INSERT INTO {s}.{table}({cols}) VALUES ({vals}) RETURNING id;'
    r=sql('cartago',f"CREATE ROLE reaudit_editor NOLOGIN; GRANT USAGE ON SCHEMA {s} TO reaudit_editor; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA {s} TO reaudit_editor; CREATE ROLE reaudit_maint NOLOGIN IN ROLE sigtec_mantenimiento_id; SELECT has_sequence_privilege('reaudit_editor','{s}.objeto_id_seq','USAGE');")
    check('editor_has_no_sequence_usage',r['rc']==0 and r['stdout'].strip()=='f',r)
    for name,query in [
        ('explicit_editor_guc',"SET ROLE reaudit_editor; SET sigtec.permitir_id_explicito=on; "+insert('puntos_interes',1000000001)),
        ('authorization_function',f'SET ROLE reaudit_editor; SELECT {s}.sigtec_id_autorizar_explicito(1000000001);'),
        ('registry_write',"SET ROLE reaudit_editor; DELETE FROM ops.identificadores_globales;"),
        ('disable_trigger',f'SET ROLE reaudit_editor; ALTER TABLE {s}.puntos_interes DISABLE TRIGGER USER;'),
        ('replica_mode','SET ROLE reaudit_editor; SET session_replication_role=replica;'),
        ('grant_self','SET ROLE reaudit_editor; GRANT sigtec_mantenimiento_id TO reaudit_editor;')]:
        r=sql('cartago',query); check(name,r['rc']!=0 and '42501' in r['stderr'],r)
    r=sql('cartago','BEGIN; SET ROLE reaudit_editor; '+insert('puntos_interes')+'ROLLBACK;')
    check('automatic_editor_insert',r['rc']==0 and r['stdout'].strip().isdigit(),r)
    for finish in ['COMMIT','ROLLBACK']:
        r=sql('cartago',f"SELECT {s}.sigtec_id_siguiente();")
        ident=int(r['stdout'].strip()); app='reaudit_race_'+finish.lower()
        a=f"BEGIN; SET ROLE reaudit_maint; SET LOCAL sigtec.permitir_id_explicito=on; {insert('puntos_interes',ident,app)} SELECT pg_sleep(4); {finish};"
        with cf.ThreadPoolExecutor() as ex:
            future=ex.submit(sql,'cartago',a,'sigtec_remed',app)
            active=None
            for _ in range(40):
                active=sql('cartago',f"SELECT pid,wait_event FROM pg_stat_activity WHERE application_name='{app}' AND wait_event='PgSleep';")
                if active['stdout'].strip(): break
                time.sleep(.1)
            check('race_'+finish+'_overlap',bool(active['stdout'].strip()),active)
            start=time.monotonic()
            b=sql('cartago',f"BEGIN; SET ROLE reaudit_maint; SET LOCAL sigtec.permitir_id_explicito=on; {insert('iluminacion',ident,app)} COMMIT;",app='reaudit_second')
            elapsed=time.monotonic()-start; first=future.result()
        r=sql('cartago',f"WITH o AS ({union(s)}) SELECT count(*),min(capa) FROM o WHERE id={ident}; SELECT count(*) FROM ops.identificadores_globales WHERE id={ident};")
        expected=(b['rc']!=0 and '23505' in b['stderr']) if finish=='COMMIT' else b['rc']==0
        check('race_'+finish,first['rc']==0 and expected and elapsed>2 and r['stdout'].splitlines()==['1|'+('puntos_interes' if finish=='COMMIT' else 'iluminacion'),'1'],dict(first=first,second=b,seconds_waited=elapsed,result=r))
    # Real distinct connections, controlled overlap, ordinary writer, two layers.
    with cf.ThreadPoolExecutor(max_workers=6) as ex:
        futures=[]
        for i in range(6):
            table='puntos_interes' if i%2==0 else 'iluminacion'
            q='BEGIN; SET ROLE reaudit_editor; '+''.join(insert(table,label=f'reaudit_load_{i}_{j}') for j in range(30))+'SELECT pg_sleep(2); COMMIT;'
            futures.append(ex.submit(sql,'cartago',q,'sigtec_remed',f'reaudit_load_{i}'))
        time.sleep(.8)
        active=sql('cartago',"SELECT count(DISTINCT pid) FROM pg_stat_activity WHERE application_name LIKE 'reaudit_load_%' AND wait_event='PgSleep';")
        results=[f.result() for f in futures]
    check('automatic_concurrency_180',active['stdout'].strip()=='6' and all(r['rc']==0 for r in results),dict(activity=active,connections=results))
    r=sql('cartago',f"WITH o AS ({union(s)}) SELECT count(*),count(DISTINCT id),count(*) FILTER(WHERE g.id IS NULL OR g.capa<>o.capa) FROM o LEFT JOIN ops.identificadores_globales g USING(id);")
    nums=list(map(int,r['stdout'].strip().split('|')))
    check('all_layers_unique_and_registered',nums[0]==nums[1] and nums[2]==0,r)
    # Leave accepted test rows as evidence in lab; remove temporary roles only.
    r=sql('cartago','DROP OWNED BY reaudit_editor,reaudit_maint; DROP ROLE reaudit_editor,reaudit_maint;')
    check('probe_roles_removed',r['rc']==0,r)

def f01():
    for kind in ['logical','physical']:
        script=f'''set +e
        export BACKUP_ROOT=/tmp/reaudit-negative-{kind}
        export SIGTEC_BACKUP_PASSWORD=reaudit-invalid-password
        bash scripts/backup/{kind}_backup.sh central
        rc=$?
        echo "SCRIPT_RC=$rc"
        echo "PUBLISHED=$(find "$BACKUP_ROOT/{kind}/central" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | wc -l)"
        cat "$BACKUP_ROOT/backup_log.tsv"
        exit 0'''
        r=run(DC+['--profile','tools','run','--rm','-T','sigtec-tools','-c',script])
        check('F01_'+kind,r['rc']==0 and 'SCRIPT_RC=1' in r['stdout'] and 'PUBLISHED=0' in r['stdout'] and '\tERROR\t' in r['stdout'] and '  OK central' not in r['stderr'] and 'reaudit-invalid-password' not in r['stderr'],r)

def pitr():
    # No compose reset/clean. Old recovery container and ALL volumes retained.
    config=dict(line.split('=',1) for line in (ROOT/'remediation/lab/.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
    label=time.strftime('reaudit_%Y%m%dT%H%M%SZ',time.gmtime())
    name='sigtec_reaudit_pitr'; prefix='sigtec_reaudit_20261120'
    if run(['docker','container','inspect',name])['rc']==0:
        raise RuntimeError('Previous evidence container exists; preserve it. Select fresh audit resource names before another PITR run.')
    for volume in [prefix+'_pgdata',prefix+'_wal']:
        if run(['docker','volume','inspect',volume])['rc']==0:
            raise RuntimeError('Previous evidence volume exists; preserve it: '+volume)
    def step(*args):
        r=run(DC+['--profile','tools','run','--rm','-T','sigtec-tools',*args],timeout=240)
        records.append(dict(step=list(args),**r)); print('step',args[0],r['rc'],flush=True)
        if r['rc']: raise RuntimeError(r)
        lines=r['stdout'].strip().splitlines()
        return lines[-1] if lines else ''
    r=sql('san_carlos','SELECT count(*) FROM pg_subscription;')
    check('pitr_no_active_subscriptions',r['stdout'].strip()=='0',r)
    if r['stdout'].strip()!='0': raise RuntimeError('subscription isolation required')
    step('scripts/backup/physical_backup.sh','san_carlos')
    base=step('-c','ls -1d /backups/physical/san_carlos/*/ | sort | tail -1').rstrip('/')+'/data'
    a=step('scripts/recovery/pitr_steps.sh','cambio-a','san_carlos',label); ida,tsa=a.split('|')
    time.sleep(1)
    target=step('scripts/recovery/pitr_steps.sh','objetivo','san_carlos').split('|')[0]
    time.sleep(1)
    b=step('scripts/recovery/pitr_steps.sh','cambio-b','san_carlos',label,ida); idb,tsb=b.split('|')
    wal=step('scripts/recovery/pitr_steps.sh','asegurar-wal','san_carlos')
    r=sql('san_carlos',f"SELECT '{tsa}'::timestamptz < '{target}'::timestamptz AND '{target}'::timestamptz < '{tsb}'::timestamptz;")
    check('pitr_A_target_B_order',r['stdout'].strip()=='t',dict(A=a,target=target,B=b,WAL=wal,result=r))
    recovery_stopped=False; source_killed=False; created=False
    try:
        r=run(['docker','stop','sigtec_remed-pg-recovery-1']); recovery_stopped=r['rc']==0
        if r['rc']: raise RuntimeError(r)
        r=run(['docker','kill','--signal=SIGKILL','sigtec_remed-pg-san-carlos-1']); source_killed=r['rc']==0
        if r['rc']: raise RuntimeError(r)
        args=['docker','run','-d','--name',name,'--hostname','reaudit-recovery','--network','sigtec_remed_net','-p','127.0.0.1:57436:5432','--entrypoint','sigtec-recovery-entrypoint',
              '-e','POSTGRES_PASSWORD='+config['POSTGRES_PASSWORD'],'-e','POSTGRES_DB=sigtec','-e','SIGTEC_NODE=recovery','-e','SIGTEC_NODE_HOST=reaudit-recovery','-e','RECOVERY_SOURCE_NODE=san_carlos','-e','RECOVERY_BASEBACKUP='+base,'-e','RECOVERY_TARGET_TIME='+target,
              '-v',prefix+'_pgdata:/var/lib/postgresql/data','-v',prefix+'_wal:/var/lib/postgresql/wal_archive','-v','sigtec_remed_backups:/backups:ro','-v','sigtec_remed_walarchive_san_carlos:/archives/san_carlos:ro',
              'sigtec-remed/postgis:17.12-3.5.4','postgres','-c','config_file=/etc/postgresql/postgresql.conf','-c','cluster_name=sigtec-reaudit-pitr']
        r=run(args); created=r['rc']==0
        records.append(dict(step='start_new_recovery_without_reset',**r))
        if r['rc']: raise RuntimeError(r)
        def rq(q):
            return run(['docker','exec','-i','-u','postgres',name,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-d','sigtec'],q)
        for _ in range(120):
            r=rq('SELECT pg_is_in_recovery();')
            if r['rc']==0 and r['stdout'].strip()=='f': break
            time.sleep(1)
        check('pitr_new_recovery_promoted',r['rc']==0 and r['stdout'].strip()=='f',r)
        r=rq(f"SELECT id,nombre,descripcion FROM local_san_carlos.puntos_interes WHERE id IN ({ida},{idb}) ORDER BY id; SELECT string_agg(marker,',' ORDER BY id) FROM ops.recovery_markers WHERE run_id='{label}'; SELECT timeline_id FROM pg_control_checkpoint(); WITH o AS ({union('local_san_carlos')}) SELECT count(*),count(DISTINCT id),count(*) FILTER(WHERE g.id IS NULL OR g.capa<>o.capa) FROM o LEFT JOIN ops.identificadores_globales g USING(id);")
        lines=r['stdout'].splitlines()
        check('pitr_restores_A_excludes_B_registry_coherent',r['rc']==0 and len(lines)==4 and lines[0].startswith(ida+'|PITR-A ') and 'Cambio A:' in lines[0] and lines[1]=='A' and lines[2]=='2' and lines[3].split('|')[0]==lines[3].split('|')[1] and lines[3].split('|')[2]=='0',r)
        ip=run(['docker','inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}',name])['stdout'].strip()
        r=run(DC+['--profile','tools','run','--rm','-T','sigtec-tools','-c',f"echo '{ip} pg-recovery' >> /etc/hosts; scripts/recovery/pitr_steps.sh marcar-recuperada san_carlos {label} 'Segunda auditoria independiente'"])
        marker=rq(f"SELECT count(*) FROM ops.recovery_markers WHERE run_id='{label}' AND marker='RECUPERADA';")
        check('F03_marker_actual_script',r['rc']==0 and marker['stdout'].strip()=='1',dict(command=r,stored=marker))
        r=run(['docker','logs',name]); (OUT/'pitr_new_container.log').write_text(r['stdout']+r['stderr'])
        check('pitr_WAL_replay_stops_before_B','recovery stopping before commit' in r['stderr'] and 'selected new timeline ID: 2' in r['stderr'],r)
        (OUT/'pitr_parameters.json').write_text(json.dumps(dict(run=label,base=base,A=a,target=target,B=b,WAL=wal,container=name,new_volumes=[prefix+'_pgdata',prefix+'_wal']),indent=2))
    finally:
        if created: run(['docker','stop',name])
        if source_killed: run(['docker','start','sigtec_remed-pg-san-carlos-1'])
        if recovery_stopped: run(['docker','start','sigtec_remed-pg-recovery-1'])
    r=sql('san_carlos',f"SELECT id,nombre,descripcion FROM local_san_carlos.puntos_interes WHERE id IN ({ida},{idb}) ORDER BY id;")
    check('pitr_source_keeps_A_modified_and_B',r['rc']==0 and len(r['stdout'].splitlines())==2 and 'MODIFICADO POR EL CAMBIO B' in r['stdout'] and 'PITR-B '+label in r['stdout'],r)

def original_restores():
    # Copy sources from read-only volumes to ephemeral container storage.
    script='''set -e
    export BACKUP_ROOT=/tmp/reaudit-original-backups
    mkdir -p "$BACKUP_ROOT"/{logical,physical}
    for kind in logical physical; do
      for node in central cartago san_jose san_carlos alajuela limon; do
        d=$(ls -1d /original-backups/$kind/$node/*/ | sort | tail -1)
        mkdir -p "$BACKUP_ROOT/$kind/$node"
        cp -a "$d" "$BACKUP_ROOT/$kind/$node/"
      done
    done
    . scripts/lib/backup.sh
    for node in central cartago san_jose san_carlos alajuela limon; do
      validate_physical_dir "$(latest_dir "$BACKUP_ROOT/physical/$node")"
    done
    bash scripts/backup/logical_restore_test.sh all
    bash scripts/backup/physical_restore_test.sh all
    '''
    args=['docker','run','--rm','-i','--network','none','--entrypoint','bash','-e','POSTGRES_PASSWORD=unused','-e','SIGTEC_BACKUP_PASSWORD=unused','-v','sigtec_backups:/original-backups:ro']
    for n in NODES: args += ['-v',f'sigtec_walarchive_{n}:/archives/{n}:ro']
    for d in ['scripts','sql','tests']: args += ['-v',str(ROOT/d)+':/opt/sigtec/'+d+':ro']
    args+=['-w','/opt/sigtec','sigtec-remed/postgis:17.12-3.5.4','-c',script]
    r=run(args,timeout=300)
    (OUT/'original_restores.log').write_text(r['stdout']+r['stderr'])
    check('original_backups_restored_with_current_image',r['rc']==0 and r['stderr'].count('restauración lógica VÁLIDA')==6 and r['stderr'].count('copia física RECUPERABLE')==6,dict(rc=r['rc'],logical=r['stderr'].count('restauración lógica VÁLIDA'),physical=r['stderr'].count('copia física RECUPERABLE')))

def residual():
    # Controlled scheduling in a writable temporary PATH, without changing pg_dump or project scripts.
    script='''set -e
    export BACKUP_ROOT=/tmp/reaudit-f09
    mkdir -p /tmp/reaudit-bin
    cat > /tmp/reaudit-bin/pg_dump <<'WRAP'
#!/bin/bash
/usr/lib/postgresql/17/bin/pg_dump "$@" || exit $?
touch /tmp/reaudit-dump-finished
sleep 3
WRAP
    chmod +x /tmp/reaudit-bin/pg_dump
    export PATH=/tmp/reaudit-bin:$PATH
    (
      for i in $(seq 1 100); do [ -f /tmp/reaudit-dump-finished ] && break; sleep .1; done
      . scripts/lib/db.sh
      psql_su cartago -c "INSERT INTO local_cartago.puntos_interes(nombre,tipo,geom) VALUES ('REAUDIT-F09','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367))"
    ) & writer=$!
    bash scripts/backup/logical_backup.sh cartago
    wait "$writer"
    set +e
    bash scripts/backup/logical_restore_test.sh cartago
    echo RESTORE_RC=$?
    '''
    r=run(DC+['--profile','tools','run','--rm','-T','sigtec-tools','-c',script])
    check('F09_reproduced_live_manifest_mismatch',r['rc']==0 and 'RESTORE_RC=1' in r['stdout'] and 'FALLA conteos:' in r['stderr'] and 'pg_restore terminado sin errores' in r['stderr'],r)
    r=run(['docker','exec','sigtec_remed-pg-central-1','bash','-c', '''PGPASSWORD="$POSTGRES_PASSWORD" psql -X -qAt -h 127.0.0.1 -U postgres -d 'dbname=sigtec sslmode=disable' -c 'SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()' '''])
    check('F06_plain_TCP_still_accepted',r['rc']==0 and r['stdout'].strip()=='f',r)
    for value in ['0','1','banana']:
        args=['make','-n','wal-retention','APPLY='+value]
        r=run(args)
        check('F05_expansion_'+value,r['rc']==0 and '""|0)' in r['stdout'] and '1) a="--apply"' in r['stdout'],r)
    r=run(['make','wal-retention','APPLY=banana'])
    check('F05_invalid_value_fails_before_retention',r['rc']!=0 and 'APPLY debe ser 1' in r['stderr'],r)
    env=dict(__import__('os').environ)
    for k in list(env):
        if k.startswith('SIGTEC_PORT_'): env.pop(k)
    env['COMPOSE_PROJECT_NAME']='sigtec_reaudit_prereq_empty'
    p=sp.run(['bash',str(ROOT/'remediation/lab/scripts/check_prereqs.sh')],env=env,text=True,capture_output=True)
    r=dict(rc=p.returncode,stdout=p.stdout,stderr=p.stderr)
    check('F04_reads_lab_env_without_export',p.returncode==1 and '57430' in p.stdout and 'configuración leída de .env' in p.stdout and '55430' not in p.stdout,r)

def integration():
    results={}
    for project in ['sigtec','sigtec_remed']:
        sigs=[]
        for n in NODES[1:]:
            s='local_'+n
            q=f"BEGIN READ ONLY; SELECT c.relname,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid WHERE ns.nspname='{s}' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped ORDER BY c.relname,a.attnum; SELECT 'REGISTRY', count(*) FROM ops.identificadores_globales; SELECT p.proname,p.prosecdef,p.proconfig,p.proacl FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='{s}' ORDER BY p.proname; SELECT 'TRIGGERS',t.tgname,t.tgenabled,count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=tgrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='{s}' AND NOT tgisinternal GROUP BY 1,2,3 ORDER BY 2; SELECT rolname,rolsuper,rolcreaterole,rolcreatedb,rolreplication,rolcanlogin FROM pg_roles WHERE rolname IN ('sigtec_backup','sigtec_mantenimiento_id'); SELECT 'PRIV',has_schema_privilege('public','{s}','CREATE'),has_table_privilege('public','ops.identificadores_globales','INSERT'),has_function_privilege('public','{s}.tg_registrar_identificador()','EXECUTE'),has_function_privilege('public','{s}.sigtec_id_autorizar_explicito(bigint)','EXECUTE'); COMMIT;"
            r=sql(n,q,project); results[project+'/'+n]=r
            sigs.append(r['stdout'].split('REGISTRY')[0])
        check(project+'_five_campus_signatures_match',len(set(sigs))==1 and all(results[project+'/'+n]['rc']==0 for n in NODES[1:]),dict(rows=[len(x.splitlines()) for x in sigs]))
    r=sql('san_jose',"BEGIN; CREATE PUBLICATION reaudit_interface FOR TABLES IN SCHEMA local_san_jose; SELECT schemaname,tablename FROM pg_publication_tables WHERE pubname='reaudit_interface' ORDER BY tablename; ROLLBACK;")
    check('publication_8_layers_excludes_ops',r['rc']==0 and len(r['stdout'].splitlines())==8 and 'ops|' not in r['stdout'],r)
    results['prior_pitr']={}
    for node in ['san_carlos','recovery']:
        results['prior_pitr'][node]=sql(node,"BEGIN READ ONLY; SELECT id,nombre,descripcion,pg_xact_commit_timestamp(xmin) FROM local_san_carlos.puntos_interes WHERE nombre IN ('PITR-A 20261120T212428Z','PITR-B 20261120T212428Z') ORDER BY id; SELECT marker FROM ops.recovery_markers WHERE run_id='20261120T212428Z' ORDER BY id; SELECT timeline_id FROM pg_control_checkpoint(); COMMIT;")
    r=run(['docker','logs','sigtec_remed-pg-recovery-1']); (OUT/'prior_pitr_container.log').write_text(r['stdout']+r['stderr'])
    (OUT/'integration_catalogs.json').write_text(json.dumps(results,indent=2))

def marker_followup():
    params=json.loads((OUT/'pitr_parameters.json').read_text()); name=params['container']; label=params['run']
    try:
        r=run(['docker','stop','sigtec_remed-pg-recovery-1'])
        if r['rc']: raise RuntimeError(r)
        r=run(['docker','start',name])
        if r['rc']: raise RuntimeError(r)
        for _ in range(60):
            r=run(['docker','exec','-u','postgres',name,'pg_isready','-q'])
            if r['rc']==0: break
            time.sleep(1)
        ip=run(['docker','inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}',name])['stdout'].strip()
        r=run(DC+['--profile','tools','run','--rm','-T','sigtec-tools','-c',f"echo '{ip} pg-recovery' >> /etc/hosts; scripts/recovery/pitr_steps.sh marcar-recuperada san_carlos {label} 'Segunda auditoria independiente'"])
        stored=run(['docker','exec','-u','postgres',name,'psql','-X','-qAt','-d','sigtec','-c',f"SELECT marker FROM ops.recovery_markers WHERE run_id='{label}' ORDER BY id;"])
        check('F03_actual_marker_verified_after_harness_fix',r['rc']==0 and stored['stdout'].splitlines()==['A','RECUPERADA'],dict(command=r,stored=stored))
    finally:
        run(['docker','stop',name]); run(['docker','start','sigtec_remed-pg-recovery-1'])

if __name__=='__main__':
    action=sys.argv[1]
    if action=='inventory': inventory(sys.argv[2])
    else:
        try:
            globals()[action]()
        finally:
            (OUT/(action+'_independent.json')).write_text(json.dumps(records,indent=2))
        sys.exit(0 if all(r.get('passed',True) for r in records) else 1)
