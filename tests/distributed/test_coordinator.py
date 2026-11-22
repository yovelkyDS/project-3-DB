"""Pruebas del coordinador sin Docker: decisiones durables y errores parciales."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('distributed',Path(__file__).resolve().parents[2]/'scripts/distributed/manage.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class CoordinatorTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.state=patch.object(m,'STATE',Path(self.tmp.name));self.state.start()
        self.prepared=set();self.committed=set();self.commands=[]
        self.db=patch.object(m,'sql',side_effect=self.sql);self.db.start()

    def tearDown(self):
        self.db.stop();self.state.stop();self.tmp.cleanup()

    def sql(self,node,statement,*args):
        self.commands.append((node,statement))
        if statement.startswith('BEGIN;'):
            data=json.loads(next(m.STATE.glob('*.json')).read_text())
            self.assertEqual(data['decision'],'abort')
            self.prepared.add(node)
        elif 'FROM pg_prepared_xacts' in statement:
            return '1' if node in self.prepared else ''
        elif statement.startswith('COMMIT PREPARED'):
            data=json.loads(next(m.STATE.glob('*.json')).read_text())
            self.assertEqual(data['decision'],'commit')
            self.prepared.remove(node);self.committed.add(node)
        elif statement.startswith('ROLLBACK PREPARED'):
            self.prepared.remove(node)
        elif 'count(*) FROM ops.operaciones_distribuidas' in statement:
            return '1' if node in self.committed else '0'
        return ''

    def test_commit_both(self):
        m.transaction('san_carlos')
        self.assertEqual(self.committed,{'central','san_carlos'})
        self.assertFalse(self.prepared)

    def test_failure_aborts_first_participant(self):
        m.transaction('san_carlos',fail=True)
        self.assertFalse(self.committed);self.assertFalse(self.prepared)

    def test_restart_after_decision_completes_and_is_idempotent(self):
        gid=m.transaction('san_carlos',crash=True)
        self.assertEqual(self.prepared,{'central','san_carlos'})
        path=m.STATE/(gid+'.json')
        m.resolve(path);m.resolve(path)
        self.assertEqual(self.committed,{'central','san_carlos'})
        self.assertTrue(json.loads(path.read_text())['resolved'])

    def test_crash_before_decision_presumes_abort(self):
        path=m.STATE/'sigtec_test.json'
        m.persist(path,{'gid':'sigtec_test','nodes':['san_carlos','central'],'resolved':False})
        self.prepared.add('san_carlos')
        m.resolve(path)
        self.assertFalse(self.committed);self.assertFalse(self.prepared)

    def test_failed_commit_can_be_retried_from_durable_decision(self):
        gid=m.transaction('san_carlos',crash=True)
        path=m.STATE/(gid+'.json')
        real=self.sql
        def fail_second(node,query,*args):
            if node=='central' and query.startswith('COMMIT PREPARED'): raise RuntimeError('offline')
            return real(node,query,*args)
        with patch.object(m,'sql',side_effect=fail_second):
            with self.assertRaises(RuntimeError): m.resolve(path)
        self.assertEqual(self.committed,{'san_carlos'})
        self.assertFalse(json.loads(path.read_text())['resolved'])
        m.resolve(path)
        self.assertEqual(self.committed,{'san_carlos','central'})

    def test_slots_are_unique_per_destination(self):
        for node in m.NODES: m.subscribe(node,'sigtec_from_central','central','sigtec_global','abc123')
        statements=[s for _,s in self.commands if s.startswith('CREATE SUBSCRIPTION')]
        self.assertEqual(len(statements),5)
        for node,s in zip(m.NODES,statements): self.assertIn("slot_name='sigtec_from_central_"+node+"'",s)


if __name__=='__main__': unittest.main()
