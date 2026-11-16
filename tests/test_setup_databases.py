"""Unit tests for scripts/setup_databases.py minimal database builder."""
import csv
import gzip
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from metanextviro_cli import cli as mn_cli  # noqa: E402


def load_setup_module():
    spec = importlib.util.spec_from_file_location('setup_databases', ROOT / 'scripts/setup_databases.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


setup_db = load_setup_module()


class SetupDatabasesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def test_preset_and_component_dependency_resolution(self):
        self.assertEqual(
            setup_db.resolve_selected_components('discovery_only', None),
            ['taxonomy', 'refseq_viral_protein', 'vog_hmm'],
        )
        # Requesting refseq_viral_protein automatically ensures taxonomy is built first
        self.assertEqual(
            setup_db.resolve_selected_components('minimal', 'refseq_viral_protein,vog_hmm'),
            ['taxonomy', 'refseq_viral_protein', 'vog_hmm'],
        )
        with self.assertRaises(ValueError):
            setup_db.resolve_selected_components('minimal', 'unknown_db')

    def test_names_dmp_organism_lookup_handles_strains_and_synonyms(self):
        names_dmp = self.base / 'names.dmp'
        names_dmp.write_text(
            '10239\t|\tViruses\t|\t\t|\tscientific name\t|\n'
            '2697049\t|\tSevere acute respiratory syndrome coronavirus 2\t|\t\t|\tscientific name\t|\n'
            '2697049\t|\tSARS-CoV-2\t|\t\t|\tacronym\t|\n'
            '12110\t|\tFoot-and-mouth disease virus\t|\t\t|\tscientific name\t|\n'
        )
        mapping = setup_db.load_ncbi_name_to_taxid(names_dmp)
        self.assertEqual(
            setup_db.lookup_organism_taxid('Severe acute respiratory syndrome coronavirus 2 isolate Wuhan-Hu-1, complete genome', mapping),
            2697049,
        )
        self.assertEqual(setup_db.lookup_organism_taxid('SARS-CoV-2', mapping), 2697049)
        self.assertEqual(setup_db.lookup_organism_taxid('Foot-and-mouth disease virus type O', mapping), 12110)
        self.assertEqual(setup_db.lookup_organism_taxid('Completely Unindexed Virus XYZ', mapping), 10239)

    def test_merge_vog_taxonomy_and_write_nextflow_configs(self):
        ann_gz = self.base / 'vog.annotations.tsv.gz'
        lca_gz = self.base / 'vog.lca.tsv.gz'
        with gzip.open(ann_gz, 'wt') as handle:
            handle.write('#GroupName\tProteinCount\tSpeciesCount\tFunctionalCategory\tConsensusFunctionalDescription\n')
            handle.write('VOG00001\t42\t30\tXr\tRNA-dependent RNA polymerase\n')
        with gzip.open(lca_gz, 'wt') as handle:
            handle.write('#GroupName\tGenomesTotal\tLastCommonAncestor\n')
            handle.write('VOG00001\t30\tViruses;Riboviria;Orthornavirae;Pisuviricota;Pisoniviricetes;Picornavirales\n')

        vog_dir = self.base / 'dbs/viral_hmm'
        vog_dir.mkdir(parents=True)
        (vog_dir / 'vog_hallmarks.hmm').write_text('HMMER3/f\n')
        setup_db.merge_vog_taxonomy_tables(ann_gz, lca_gz, vog_dir / 'vog_hmm_taxonomy.tsv')

        with open(vog_dir / 'vog_hmm_taxonomy.tsv', newline='') as vog_handle:
            rows = list(csv.DictReader(vog_handle, delimiter='\t'))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['hmm_name'], 'VOG00001')
        self.assertIn('Picornavirales', rows[0]['lca_lineage'])

        # Simulate installed files and verify generated Nextflow config + YAML + manifest
        (self.base / 'dbs/taxonomy').mkdir(parents=True)
        (self.base / 'dbs/taxonomy/taxa.sqlite').write_text('sqlite')
        (self.base / 'dbs/viral_proteins').mkdir(parents=True)
        (self.base / 'dbs/viral_proteins/refseq_viral_proteins.dmnd').write_text('dmnd')
        (self.base / 'dbs/viral_proteins/refseq_hallmark_refs.faa').write_text('>r\nM\n')

        cfg_path, yml_path, params = setup_db.write_database_configs(self.base / 'dbs')
        self.assertIn('viral_protein_db', params)
        self.assertIn('viral_hmm_db', params)
        self.assertIn('viral_hmm_taxonomy', params)
        self.assertIn("viral_hmm_taxonomy =", cfg_path.read_text())
        self.assertTrue(yml_path.is_file())
        manifest = json.loads((self.base / 'dbs/database_manifest.json').read_text())
        self.assertEqual(manifest['params']['taxonomy_db'], str((self.base / 'dbs/taxonomy/taxa.sqlite').resolve()))

    def test_cli_dry_run_exits_cleanly_without_network(self):
        proc = subprocess.run(
            [sys.executable, str(ROOT / 'scripts/setup_databases.py'),
             '--db-dir', str(self.base / 'planned_dbs'), '--preset', 'minimal', '--dry-run'],
            capture_output=True, text=True, check=True,
        )
        self.assertIn('refseq_viral_protein', proc.stdout)
        self.assertIn('Dry run only', proc.stdout)
        self.assertFalse((self.base / 'planned_dbs').exists())

    def test_metanextviro_cli_launcher_builds_nextflow_and_setup_commands(self):
        cmd, info = mn_cli.build_nextflow_command(['--version'])
        self.assertIsNone(cmd)
        self.assertIn('MetaNextViro v0.2.0', info)

        setup_cmd, _ = mn_cli.build_nextflow_command(['setup-db', '--db-dir', '/tmp/dbs', '--dry-run'])
        self.assertEqual(setup_cmd[:2], [sys.executable, str(ROOT / 'scripts/setup_databases.py')])
        self.assertEqual(setup_cmd[2:], ['--db-dir', '/tmp/dbs', '--dry-run'])

        with patch('shutil.which', return_value='/usr/local/bin/nextflow'):
            nf_cmd, _ = mn_cli.build_nextflow_command(['--input', 'samples.csv', '-profile', 'conda'])
            self.assertEqual(nf_cmd[:3], ['/usr/local/bin/nextflow', 'run', str(ROOT / 'main.nf')])
            self.assertEqual(nf_cmd[3:], ['--input', 'samples.csv', '-profile', 'conda'])

            nf_help, _ = mn_cli.build_nextflow_command([])
            self.assertEqual(nf_help, ['/usr/local/bin/nextflow', 'run', str(ROOT / 'main.nf'), '--help'])


if __name__ == '__main__':
    unittest.main()
