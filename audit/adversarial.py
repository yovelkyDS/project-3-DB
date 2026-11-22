import subprocess,json,time,concurrent.futures
from pathlib import Path
root=Path.cwd();lab=root/'audit/lab';out=root/'audit/raw';base=['docker','compose','--project-directory',str(lab),'-f',str(lab/'compose.yaml')];res=[]
def run(name,args,input=None):
 p=subprocess.run(args,input=input,text=True,capture_output=True);d={'test':name,'command':args,'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr};res.append(d);print(name,'rc=',p.returncode);return d
def sql(name,q):return run(name,['docker','exec','-i','-u','postgres','sigtec_audit_20261120-pg-cartago-1','psql','-X','-v','ON_ERROR_STOP=1','-d','sigtec'],q)
sql('create_unprivileged_editor', '''CREATE ROLE audit_editor NOSUPERUSER NOLOGIN;
GRANT USAGE ON SCHEMA local_cartago TO audit_editor;
GRANT SELECT,INSERT ON local_cartago.puntos_interes,local_cartago.iluminacion TO audit_editor;
SELECT last_value FROM local_cartago.objeto_id_seq;
''')
sql('ordinary_editor_bypasses_explicit_id_guard', '''BEGIN;
SET ROLE audit_editor;
SELECT current_user,session_user,has_sequence_privilege(current_user,'local_cartago.objeto_id_seq','USAGE');
SET LOCAL sigtec.permitir_id_explicito=on;
INSERT INTO local_cartago.puntos_interes(id,nombre,tipo,geom)
VALUES(1000000042,'AUDIT manual ID','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367)) RETURNING id;
COMMIT;
''')
# Primera sesión retiene un INSERT sin confirmar; la segunda inserta en otra tabla.
def race1():return sql('concurrent_insert_points', '''BEGIN; SET ROLE audit_editor; SET LOCAL sigtec.permitir_id_explicito=on;
INSERT INTO local_cartago.puntos_interes(id,nombre,tipo,geom) VALUES(1000000043,'AUDIT concurrent','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367));
SELECT pg_sleep(4); COMMIT;''')
with concurrent.futures.ThreadPoolExecutor(2) as ex:
 f=ex.submit(race1);time.sleep(1)
 sql('concurrent_insert_lighting', '''BEGIN; SET ROLE audit_editor; SET LOCAL sigtec.permitir_id_explicito=on;
INSERT INTO local_cartago.iluminacion(id,codigo,potencia,estado,geom) VALUES(1000000043,'AUDIT-RACE',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367)); COMMIT;''');f.result()
sql('duplicate_id_persisted', "SELECT id,count(*) FROM (SELECT id FROM local_cartago.puntos_interes UNION ALL SELECT id FROM local_cartago.iluminacion) t GROUP BY id HAVING count(*)>1;")
for kind in ['logical','physical']:
 run(kind+'_backup_wrong_password',base+['--profile','tools','run','--rm','-T','-e','SIGTEC_BACKUP_PASSWORD=audit-deliberately-invalid','-e','BACKUP_ROOT=/tmp/audit-negative-'+kind,'sigtec-tools','scripts/backup/'+kind+'_backup.sh','central'])
run('pitr_marker_command',base+['--profile','tools','run','--rm','-T','sigtec-tools','scripts/recovery/pitr_steps.sh','marcar-recuperada','san_carlos','audit-marker-validation','audit marker'])
run('transport_without_tls',base+['--profile','tools','run','--rm','-T','sigtec-tools','-c','. scripts/lib/db.sh; PGSSLMODE=disable psql_su central -tAc "SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()"'])
(out/'adversarial.json').write_text(json.dumps(res,indent=2))
