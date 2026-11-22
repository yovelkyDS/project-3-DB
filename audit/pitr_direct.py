import subprocess,json
from pathlib import Path
res=[]
for prefix,run in [('sigtec','20261120T172854Z'),('sigtec_audit_20261120','20261120T202335Z')]:
 for svc in ['pg-san-carlos','pg-recovery']:
  q=f"BEGIN READ ONLY; SELECT id,nombre,descripcion,pg_xact_commit_timestamp(xmin) FROM local_san_carlos.puntos_interes WHERE nombre IN ('PITR-A {run}','PITR-B {run}') ORDER BY id; SELECT run_id,marker FROM ops.recovery_markers WHERE run_id='{run}'; SELECT pg_is_in_recovery(); SELECT timeline_id FROM pg_control_checkpoint(); COMMIT;"
  args=['docker','exec','-u','postgres',prefix+'-'+svc+'-1','psql','-X','-v','ON_ERROR_STOP=1','-d','sigtec','-P','pager=off','-c',q];p=subprocess.run(args,capture_output=True,text=True);res.append(dict(project=prefix,service=svc,rc=p.returncode,stdout=p.stdout,stderr=p.stderr))
Path('audit/raw/pitr_direct.json').write_text(json.dumps(res,indent=2));print(json.dumps(res,indent=2))
