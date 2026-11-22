"""Pruebas de integración reales. Requiere manage.py setup y los seis nodos activos.
Ejecutar: python tests/distributed/integration.py
"""
import importlib.util
import argparse
import json
from pathlib import Path
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

spec=importlib.util.spec_from_file_location('distributed',Path(__file__).resolve().parents[2]/'scripts/distributed/manage.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def eventually(node,layer,obj_id,expected):
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        failures=[]
        def check(n):
            mismatches=[]
            tables=(['local_'+node+'.'+layer,'global.'+layer] if n=='central'
                    else ['global.'+layer,'qgis.v_'+layer])
            parts=[]
            for t in tables:
                parts += [m.lit(t),f'(SELECT to_jsonb(t) FROM {t} t WHERE id={obj_id})']
            rows=json.loads(m.sql(n,'SELECT jsonb_build_object('+','.join(parts)+')'))
            for table,actual in rows.items():
                if actual!=expected: mismatches.append(n+':'+table)
            return mismatches
        with ThreadPoolExecutor(max_workers=6) as pool:
            for result in pool.map(check,['central']+m.NODES): failures.extend(result)
        if not failures:
            print('OK propagación',node,layer,obj_id,'DELETE' if expected is None else 'INSERT/UPDATE',flush=True)
            return
        time.sleep(1)
    raise AssertionError('No propagó: '+','.join(failures))


def rejected(node, statement, role, password, code):
    # ON_ERROR_STOP desactivado solamente para capturar SQLSTATE con psql.
    result=m.sql(node,'\\set ON_ERROR_STOP off\n'+statement+'\n\\echo :SQLSTATE',role,password)
    assert result.splitlines()[-1]==code,(statement,result,code)


def run(only_node=None):
    values=m.env_values()
    for cid,node in enumerate(m.NODES,1):
        if only_node and node!=only_node: continue
        role='qgis_'+node
        password=values['SIGTEC_QGIS_'+node.upper()+'_PASSWORD'].strip().strip('"').strip("'")
        foreign=m.NODES[(cid)%5]
        for layer in m.LAYERS:
            view='qgis.v_'+layer
            payload=json.loads(m.sql(node,f'SELECT row_to_json(t) FROM local_{node}.{layer} t LIMIT 1'))
            payload['id']=None; payload['campus_id']=None
            if 'codigo' in payload: payload['codigo']='T'+uuid.uuid4().hex[:20]
            insert=f'INSERT INTO {view} SELECT (json_populate_record(NULL::{view},{m.lit(json.dumps(payload))})).* RETURNING id;'
            obj_id=int(m.sql(node,insert,role,password))
            try:
                expected=json.loads(m.sql(node,f'SELECT row_to_json(t) FROM {view} t WHERE id={obj_id}',role,password))
                assert expected['campus_id']==cid
                eventually(node,layer,obj_id,expected)
                m.sql(node,f'UPDATE {view} SET geom=ST_Translate(geom,1,0) WHERE id={obj_id}',role,password)
                expected=json.loads(m.sql(node,f'SELECT row_to_json(t) FROM {view} t WHERE id={obj_id}',role,password))
                eventually(node,layer,obj_id,expected)
                rejected(node,f'UPDATE {view} SET campus_id={(cid%5)+1} WHERE id={obj_id};',role,password,'23514')
                rejected(node,f'UPDATE {view} SET id=id+100000 WHERE id={obj_id};',role,password,'23514')
                rejected(node,f'DELETE FROM local_{node}.{layer} WHERE id={obj_id};',role,password,'42501')
                foreign_id=m.sql(node,f'SELECT id FROM {view} WHERE campus_id={(cid%5)+1} LIMIT 1')
                assert foreign_id,'Datos ajenos ausentes; ejecute verify primero'
                rejected(node,f'UPDATE {view} SET geom=ST_Translate(geom,2,0) WHERE id={foreign_id};',role,password,'42501')
                rejected(node,f'DELETE FROM {view} WHERE id={foreign_id};',role,password,'42501')
                payload['campus_id']=(cid%5)+1
                rejected(node,f'INSERT INTO {view} SELECT (json_populate_record(NULL::{view},{m.lit(json.dumps(payload))})).*;',role,password,'23514')
                # Un GUC manipulable no debe permitir cambiar el campus autenticado.
                rejected(node,f"SET sigtec.campus_id='{(cid%5)+1}'; DELETE FROM {view} WHERE id={foreign_id};",role,password,'42501')
            finally:
                m.sql(node,f'DELETE FROM {view} WHERE id={obj_id}',role,password)
            eventually(node,layer,obj_id,None)
    m.transaction('san_carlos'); m.transaction('san_carlos',fail=True)
    gid=m.transaction('san_carlos',crash=True)
    m.resolve(m.STATE/(gid+'.json'))
    for node in ['san_carlos','central']:
        assert m.sql(node,f'SELECT count(*) FROM ops.operaciones_distribuidas WHERE id={m.lit(gid)}')=='1'
        assert m.sql(node,f'SELECT count(*) FROM pg_prepared_xacts WHERE gid={m.lit(gid)}')=='0'
    m.verify()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node',choices=m.NODES)
    run(parser.parse_args().node)
