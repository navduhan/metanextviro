"""Synthetic regressions for local BLAST evidence and conservative organization."""
import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'nextflow/bin' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


blast = load_script('process_blast_results')
organizer = load_script('organize_contigs_by_taxonomy')


class FakeTaxonomy:
    def __init__(self, dbfile=None):
        pass

    def resolve(self, tax_ids):
        return {**dict.fromkeys(blast.RANKS, ''), 'superkingdom': 'Viruses',
                'family': 'Family_A' if tax_ids == '11' else 'Family_B',
                'species': f'Species_{tax_ids}', 'taxonomy_status': 'resolved'}


def hit(subject, start, end, score=100, query='contig', qlen=1000, taxid='11', length=None):
    values = [query, subject, 95, length or abs(end-start)+1, 0, 0,
              start, end, 1, 1000, 50, '1e-20', score, qlen, 1000,
              'Example subject', taxid, 'plus' if start < end else 'minus']
    return dict(zip(blast.COL, values))


def read_table(path):
    with open(path, newline='') as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


class BlastEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.fasta = self.base / 'contigs.fa'
        self.fasta.write_text('>contig\n' + 'A' * 1000 + '\n')
        self.prefix = str(self.base / 'sample')
        self.raw = self.base / 'raw.tsv'

    def run_parser(self, hits):
        with self.raw.open('w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=blast.COL, delimiter='\t', lineterminator='\n')
            writer.writerows(hits)
        with patch.object(blast, 'TaxonomyResolver', FakeTaxonomy):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nt', 'qcovhsp')

    def test_keeps_local_hits_and_unions_overlapping_reverse_intervals(self):
        self.run_parser([hit('a', 1, 300), hit('b', 601, 1000, score=50, taxid='22'),
                         hit('a', 500, 201, score=80)])
        hsps = read_table(self.base / 'sample_hits_nt.tsv')
        self.assertEqual(len(hsps), 3)
        self.assertEqual(hsps[2]['query_start'], '500')
        summary = {row['subject_id']: row for row in read_table(self.base / 'sample_hit_summary_nt.tsv')}
        self.assertEqual(summary['a']['query_regions'], '1-500')
        self.assertEqual(summary['a']['hsp_count'], '2')
        self.assertEqual(float(summary['a']['query_union_coverage']), 50)
        self.assertEqual(float(summary['b']['query_union_coverage']), 40)
        # A local secondary hit is retained even though it loses the best-hit contest.
        best = read_table(self.base / 'sample_best_hits_nt.xls')
        self.assertEqual(best[0]['subject_id'], 'a')
        organizer.organize_contigs([self.base / 'sample_hits_nt.tsv'], self.fasta, self.base / 'organized', 'sample')
        output = self.base / 'organized/sample'
        self.assertTrue((output / 'needs_review/contig.fasta').exists())
        self.assertFalse(list((output / 'viruses').rglob('contig.fasta')))
        self.assertEqual(len(read_table(output / 'classification_evidence.tsv')), 3)
        self.assertIn('family', read_table(output / 'classification_review.tsv')[0]['review_reason'])

    def test_disjoint_regions_of_same_subject_are_not_filled_in(self):
        self.run_parser([hit('a', 1, 100), hit('a', 900, 1000)])
        summary = read_table(self.base / 'sample_hit_summary_nt.tsv')[0]
        self.assertEqual(summary['query_regions'], '1-100;900-1000')
        self.assertEqual(int(summary['query_covered_bases']), 201)

    def test_translated_query_coverage_uses_nucleotide_coordinates(self):
        self.run_parser([hit('protein', 1, 300, length=100), hit('protein', 301, 600, length=100)])
        self.assertEqual(float(read_table(self.base / 'sample_hit_summary_nt.tsv')[0]['query_union_coverage']), 60)

    def test_negative_protein_frame_is_not_labeled_as_subject_strand(self):
        record = hit('protein', 600, 301, length=100)
        record['subject_strand'] = '-2'
        with self.raw.open('w', newline='') as handle:
            csv.DictWriter(handle, fieldnames=blast.COL, delimiter='\t').writerow(record)
        with patch.object(blast, 'TaxonomyResolver', FakeTaxonomy):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nr',
                                       'qcovhsp', strand_field='qframe')
        result = read_table(self.base / 'sample_hits_nr.tsv')[0]
        self.assertEqual((result['query_frame'], result['query_strand'], result['subject_strand']),
                         ('-2', 'minus', ''))

    def test_malformed_search_output_fails_instead_of_shifting_columns(self):
        self.raw.write_text('\t'.join(str(value) for value in list(hit('a', 1, 100).values())[:-1]) + '\n')
        with self.assertRaisesRegex(ValueError, 'expected 18 columns, got 17'):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nt')

    def test_best_report_uses_score_and_keeps_a_whole_row(self):
        self.run_parser([hit('long', 1, 800, score=80), hit('short', 1, 100, score=150)])
        best = read_table(self.base / 'sample_best_hits_nt.xls')[0]
        self.assertEqual((best['subject_id'], best['alignment_length']), ('short', '100'))

    def test_empty_search_has_headers_and_no_taxonomy_dependency(self):
        self.raw.write_text('')
        with patch.object(blast, 'TaxonomyResolver', side_effect=AssertionError('must not initialize')):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nt')
        for name in ['sample_hits_nt.tsv', 'sample_hit_summary_nt.tsv', 'sample_best_hits_nt.xls']:
            self.assertEqual(read_table(self.base / name), [])
            self.assertGreater((self.base / name).stat().st_size, 0)

    def test_long_contig_length_is_not_replaced_with_zero(self):
        self.fasta.write_text('>contig\n' + 'A' * 31000 + '\n')
        self.run_parser([hit('a', 1, 100, qlen=31000)])
        best = read_table(self.base / 'sample_best_hits_nt.xls')[0]
        self.assertEqual(int(best['sequence_length']), 31000)
        self.assertEqual(len(best['sequence']), 31000)

    def test_invalid_coordinates_and_unknown_queries_fail(self):
        for record in [hit('a', 1, 1001), hit('a', 1, 100, query='missing')]:
            with self.subTest(record=record), self.assertRaisesRegex(ValueError, 'raw.tsv:1: invalid hit'):
                self.run_parser([record])

    def test_consistent_family_does_not_invent_species_consensus(self):
        self.run_parser([hit('a', 1, 100), hit('b', 400, 500)])
        path = self.base / 'sample_hits_nt.tsv'
        rows = read_table(path)
        rows[1]['species'] = 'Another_species'
        with path.open('w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=blast.HSP_COLUMNS, delimiter='\t')
            writer.writeheader()
            writer.writerows(rows)
        organizer.organize_contigs([path], self.fasta, self.base / 'organized', 'sample')
        fasta = (self.base / 'organized/sample/viruses/Family_A/contig.fasta').read_text()
        self.assertIn('|species=Unknown|', fasta)

    def test_all_no_hit_contigs_remain_available(self):
        self.run_parser([])
        organizer.organize_contigs([self.base / 'sample_hits_nt.tsv'], self.fasta, self.base / 'organized', 'sample')
        self.assertTrue((self.base / 'organized/sample/unclassified/contig.fasta').exists())


class TaxonomyTests(unittest.TestCase):
    def test_multi_taxid_uses_common_lineage_instead_of_mixing_ranks(self):
        class Database:
            def get_lineage(self, taxid):
                return {11: [1, 10239, 10, 11], 22: [1, 10239, 20, 22]}[taxid]

            def get_rank(self, ids):
                return {1: 'no rank', 10239: 'superkingdom', 10: 'family', 20: 'family', 11: 'species', 22: 'species'}

            def get_taxid_translator(self, ids):
                return {taxid: str(taxid) for taxid in ids}

        resolver = blast.TaxonomyResolver.__new__(blast.TaxonomyResolver)
        resolver.ncbi = Database()
        result = resolver.resolve('11;22')
        self.assertEqual(result['superkingdom'], 'Viruses')
        self.assertEqual(result['family'], '')
        self.assertEqual(result['species'], '')
        self.assertEqual(result['taxonomy_status'], 'lowest_common_ancestor')


if __name__ == '__main__':
    unittest.main()
