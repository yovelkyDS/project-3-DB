from pathlib import Path
import subprocess,json,hashlib
root=Path.cwd();lab=root/'audit/lab'; layers=['edificios','carreteras','aceras','parqueos','zonas_verdes','puntos_interes','iluminacion','accesibilidad']; nodes=['cartago','san_jose','san_carlos','alajuela','limon']
def snap():
 out={}
 for n in nodes:
  q='SELECT row_to_json(t)::text FROM ('+' UNION ALL '.join("SELECT '"+l+"' capa,row_to_json(r)::text dato FROM local_"+n+'.'+l+' r' for l in layers)+') t ORDER BY capa,dato'
  p=subprocess.run(['docker','exec','-u','postgres','sigtec_audit_20261120-pg-'+n.replace('_','-')+'-1','psql','-X','-tA','-d','sigtec','-c',q],capture_output=True,text=True,check=True);out[n]=hashlib.sha256(p.stdout.encode()).hexdigest()
 return out
before=snap();cred=hashlib.sha256((lab/'.env').read_bytes()).hexdigest()
with (root/'audit/raw/second_setup.log').open('w') as f:p=subprocess.run(['bash','scripts/setup.sh'],cwd=lab,stdout=f,stderr=subprocess.STDOUT)
after=snap();result=dict(exit_code=p.returncode,data_unchanged=before==after,credentials_unchanged=cred==hashlib.sha256((lab/'.env').read_bytes()).hexdigest(),before=before,after=after)
(root/'audit/raw/second_setup.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
