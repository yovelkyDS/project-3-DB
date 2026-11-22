from pathlib import Path
import subprocess,json,hashlib
r=Path.cwd();o=r/'audit/raw';expect=json.loads((o/'original_hashes.json').read_text());changed=[n for n,h in expect.items() if not (r/n).exists() or hashlib.sha256((r/n).read_bytes()).hexdigest()!=h]
layers=['edificios','carreteras','aceras','parqueos','zonas_verdes','puntos_interes','iluminacion','accesibilidad'];base=json.loads((o/'original_data_hashes.json').read_text());after={}
for n in base:
 s='local_'+('san_carlos' if n=='recovery' else n);snap=[]
 for l in layers:
  p=subprocess.run(['docker','exec','-u','postgres','sigtec-pg-'+n.replace('_','-')+'-1','psql','-X','-tA','-d','sigtec','-c',f'SELECT row_to_json(t)::text FROM {s}.{l} t ORDER BY id'],check=True,text=True,capture_output=True);snap.append(l+p.stdout)
 after[n]=hashlib.sha256(''.join(snap).encode()).hexdigest()
# Solo resultado booleano de escaneo de secretos; nunca revelar el valor encontrado.
secrets=[line.split('=',1)[1] for line in (r/'.env').read_text().splitlines() if 'PASSWORD=' in line and len(line.split('=',1)[1])>=12]
leaks=[]
for p in r.rglob('*'):
 if not p.is_file() or p.name=='.env' or '.git' in p.parts:continue
 try:
  if any(v in p.read_text(errors='ignore') for v in secrets):leaks.append(str(p.relative_to(r)))
 except OSError:pass
versions=subprocess.run(['docker','version','--format','{{.Client.Version}} {{.Server.Version}}'],capture_output=True,text=True)
result=dict(original_files_checked=len(expect),changed_original_files=changed,original_geographic_data_unchanged=base==after,hashes_after=after,original_secret_leaks_in_other_files=leaks,docker=versions.stdout.strip())
(o/'final_integrity.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
