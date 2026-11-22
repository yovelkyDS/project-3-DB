from pathlib import Path
import subprocess,json,hashlib
out=Path('audit/raw'); nodes=['central','cartago','san_jose','san_carlos','alajuela','limon','recovery']; layers=['edificios','carreteras','aceras','parqueos','zonas_verdes','puntos_interes','iluminacion','accesibilidad']
def run(args):
 p=subprocess.run(args,text=True,capture_output=True); return {'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
allids=[]; snapshot={}
for node in nodes:
 svc='sigtec-pg-'+node.replace('_','-')+'-1'
 info=json.loads(subprocess.check_output(['docker','inspect',svc]))[0]
 safe={k:info.get(k) for k in ['Id','Image','Mounts','State']};safe['Ports']=info['NetworkSettings']['Ports'];safe['Networks']={k: {'IPAddress':v['IPAddress'],'Aliases':v['Aliases']} for k,v in info['NetworkSettings']['Networks'].items()}
 (out/(node+'_container.json')).write_text(json.dumps(safe,indent=2))
 q="""BEGIN READ ONLY;
 SELECT version(); SELECT postgis_full_version();
 SELECT name,setting FROM pg_settings WHERE name IN ('wal_level','max_replication_slots','max_wal_senders','data_checksums','max_logical_replication_workers','max_worker_processes','max_prepared_transactions','archive_mode','ssl','password_encryption','max_slot_wal_keep_size');
 SELECT system_identifier FROM pg_control_system();
 SELECT * FROM ops.node_info; SELECT * FROM ops.seed_runs; SELECT * FROM ops.schema_migrations;
 SELECT archived_count,failed_count,last_archived_wal,last_failed_wal FROM pg_stat_archiver;
 SELECT rolname,rolsuper,rolreplication,rolcanlogin,rolcreatedb,rolcreaterole FROM pg_roles ORDER BY rolname;
 SELECT line_number,type,database,user_name,address,auth_method,error FROM pg_hba_file_rules;
 SELECT * FROM pg_replication_slots; SELECT pubname FROM pg_publication; SELECT subname,subenabled FROM pg_subscription;
 SELECT pg_is_in_recovery(); SELECT timeline_id FROM pg_control_checkpoint();
 SELECT * FROM ops.recovery_markers ORDER BY id;
 COMMIT;"""
 def sql(q):return run(['docker','exec','-i','-u','postgres',svc,'psql','-X','-v','ON_ERROR_STOP=1','-d','sigtec','-P','pager=off','-c',q])
 data={'infra':sql(q)}
 if node not in ['central']:
  s='local_'+('san_carlos' if node=='recovery' else node)
  data['catalog']=sql("BEGIN READ ONLY; SELECT f_table_schema,f_table_name,type,srid FROM geometry_columns WHERE f_table_schema='"+s+"'; SELECT c.relname,c.relreplident,k.contype,pg_get_constraintdef(k.oid) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_constraint k ON k.conrelid=c.oid WHERE n.nspname='"+s+"' ORDER BY c.relname,k.contype; SELECT tgname,tgenabled FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='"+s+"' AND NOT tgisinternal; COMMIT;")
  data['layers']=[]
  snap=[]
  for l in layers:
   r=sql(f"BEGIN READ ONLY; SELECT '{l}' capa,count(*) filas,count(*) FILTER(WHERE NOT ST_IsValid(geom) OR ST_IsEmpty(geom) OR ST_SRID(geom)<>5367) invalidos,ST_Extent(ST_Transform(geom,4326)) extent FROM {s}.{l}; SELECT id,campus_id,ST_GeometryType(geom),ST_SRID(geom) FROM {s}.{l} ORDER BY id; COMMIT;")
   data['layers'].append(r)
   rr=run(['docker','exec','-u','postgres',svc,'psql','-X','-tA','-d','sigtec','-c',f'SELECT row_to_json(t)::text FROM {s}.{l} t ORDER BY id'])
   snap.append(l+rr['stdout'])
   if node!='recovery':
    ids=sql(f'SELECT id FROM {s}.{l} ORDER BY id')['stdout'];allids.append([node,l,ids])
  snapshot[node]=hashlib.sha256(''.join(snap).encode()).hexdigest()
 (out/(node+'_sql.json')).write_text(json.dumps(data,indent=2))
(out/'original_data_hashes.json').write_text(json.dumps(snapshot,indent=2))
(out/'all_original_ids.json').write_text(json.dumps(allids,indent=2))
(out/'original_recovery_docker.log').write_text(subprocess.check_output(['docker','logs','sigtec-pg-recovery-1'],stderr=subprocess.STDOUT,text=True))
print('Consultas de solo lectura registradas para 7 nodos; no se exportaron credenciales.')
