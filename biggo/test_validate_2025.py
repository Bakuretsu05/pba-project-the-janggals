"""Fresh-checkout regressions; no browser or private raw directory required."""
import csv
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode=True
import validate_2025 as validator

class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='biggo-validation-test-')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.base=self.root/'biggo'
        self.base.mkdir()
        (self.root/'products').mkdir()
        for name in ['validate_2025.py','price_changes.csv','collection_status_2025.csv',
                     'coverage_check_2026-10-22.csv','verification_2025.csv',
                     'chart_checks_2025.csv','access_blocker_2025.json','validation_2025.json']:
            shutil.copyfile(validator.BASE/name,self.base/name)
        shutil.copyfile(validator.BASE.parent/'products/products.csv',self.root/'products/products.csv')

    def cli(self,*args):
        return subprocess.run([sys.executable,str(self.base/'validate_2025.py'),*args],capture_output=True,text=True,encoding='utf-8')

    def rewrite(self,change):
        rows=validator.read(self.base/'price_changes.csv')
        change(rows)
        with (self.base/'price_changes.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=validator.HEADER);writer.writeheader();writer.writerows(rows)

    def test_csv_only_fresh_checkout_is_read_only_and_explicit(self):
        before={p.name:p.read_bytes() for p in self.base.iterdir()}
        result=self.cli()
        self.assertEqual(result.returncode,0,result.stderr)
        report=json.loads(result.stdout)
        self.assertEqual(report['validation_mode'],'csv_only')
        self.assertFalse(report['raw_to_csv_verified'])
        self.assertEqual(report['price_change_rows'],1397)
        self.assertEqual(report['reported_retrieved_by_category'],{'3C':72,'APPL':44,'BEAU':0,'FOOD':0,'HOME':0})
        self.assertFalse(report['dataset_complete'])
        self.assertTrue(report['login_blocker']['response']['require_login'])
        self.assertEqual(report['independently_chart_checked'],1)
        self.assertEqual(report['independently_retrieved_twice'],0)
        self.assertEqual({p.name:p.read_bytes() for p in self.base.iterdir()},before)

    def test_explicit_raw_mode_fails_clearly_without_evidence(self):
        result=self.cli('--raw')
        self.assertEqual(result.returncode,1)
        self.assertIn('Full raw verification unavailable',result.stderr)
        self.assertNotIn('Traceback',result.stderr)

    def test_raw_mode_does_not_silently_fall_back_for_partial_evidence(self):
        raw=self.base/'raw/2025';raw.mkdir(parents=True)
        (raw/'requests.jsonl').write_text('',encoding='utf-8')
        result=self.cli('--raw')
        self.assertEqual(result.returncode,1)
        self.assertIn('missing evidence for 116 collected listings',result.stderr)

    def test_csv_only_checks_calendar_dates(self):
        self.rewrite(lambda rows:rows[0].update(changed_at='2025-02-30 10:00'))
        self.assertEqual(self.cli().returncode,1)

    def test_csv_only_checks_chronology(self):
        def swap(rows):rows[1],rows[2]=rows[2],rows[1]
        self.rewrite(swap)
        result=self.cli();self.assertEqual(result.returncode,1)
        self.assertIn('Chronology',result.stderr)

    def test_csv_only_rejects_duplicate_records(self):
        self.rewrite(lambda rows:rows.append(rows[0].copy()))
        result=self.cli();self.assertEqual(result.returncode,1)
        self.assertIn('Duplicate complete records',result.stderr)

    def test_csv_only_rejects_consecutive_equal_prices(self):
        self.rewrite(lambda rows:rows[1].update(price=rows[0]['price']))
        result=self.cli();self.assertEqual(result.returncode,1)
        self.assertIn('Consecutive equal prices',result.stderr)

if __name__=='__main__':unittest.main()
