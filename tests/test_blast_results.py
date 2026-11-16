"""Synthetic regressions for sorted BLAST reporting, XLSX widths, and contig organization."""
import csv
import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
NS = {'main': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


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


def hit(subject, start, end, score=100, query='contig', qlen=1000, taxid='11',
        length=None, pident=95, evalue='1e-20', title='Example subject'):
    values = [query, subject, pident, length or abs(end - start) + 1, 0, 0,
              start, end, 1, 1000, 50, evalue, score, qlen, 1000,
              title, taxid, 'plus' if start < end else 'minus']
    return dict(zip(blast.COL, values))


def read_table(path):
    with open(path, newline='') as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


def read_xlsx_sheet_xml(xlsx_path):
    with zipfile.ZipFile(xlsx_path) as archive:
        sheet_root = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
        shared_strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            sst = ET.fromstring(archive.read('xl/sharedStrings.xml'))
            for si in sst.findall('main:si', NS):
                shared_strings.append(''.join(t.text or '' for t in si.findall('.//main:t', NS)))
    rows = []
    for row_el in sheet_root.findall('.//main:sheetData/main:row', NS):
        vals = []
        for cell in row_el.findall('main:c', NS):
            ctype = cell.attrib.get('t')
            if ctype == 'inlineStr':
                t_el = cell.find('.//main:t', NS)
                vals.append(t_el.text if t_el is not None and t_el.text is not None else '')
            elif ctype == 's':
                v_el = cell.find('main:v', NS)
                vals.append(shared_strings[int(v_el.text)] if v_el is not None else '')
            else:
                v_el = cell.find('main:v', NS)
                vals.append(v_el.text if v_el is not None and v_el.text is not None else '')
        rows.append(vals)
    cols = {}
    for col_el in sheet_root.findall('.//main:cols/main:col', NS):
        start = int(col_el.attrib['min'])
        end = int(col_el.attrib['max'])
        for idx in range(start, end + 1):
            cols[idx] = float(col_el.attrib['width'])
    pane = sheet_root.find('.//main:pane', NS)
    autofilter = sheet_root.find('main:autoFilter', NS)
    return rows, cols, pane, autofilter


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

    def test_keeps_local_hits_unions_intervals_and_sorts_hsps_descending(self):
        self.run_parser([hit('a', 1, 300, score=100), hit('b', 601, 1000, score=50, taxid='22'),
                         hit('a', 500, 201, score=80)])
        hsps = read_table(self.base / 'sample_all_hsps_nt.tsv')
        self.assertEqual(len(hsps), 3)
        self.assertEqual([int(r['bit_score']) for r in hsps], [100, 80, 50])
        self.assertEqual(hsps[1]['query_start'], '500')

        summary_rows = read_table(self.base / 'sample_subject_summary_nt.tsv')
        self.assertEqual([r['subject_rank'] for r in summary_rows], ['1', '2'])
        self.assertEqual([r['subject_id'] for r in summary_rows], ['a', 'b'])
        summary = {row['subject_id']: row for row in summary_rows}
        self.assertEqual(summary['a']['query_regions'], '1-500')
        self.assertEqual(summary['a']['hsp_count'], '2')
        self.assertEqual(float(summary['a']['query_union_coverage']), 50)
        self.assertEqual(float(summary['b']['query_union_coverage']), 40)

        # Best-hits table includes merged winning-subject coverage and places sequence last.
        best = read_table(self.base / 'sample_best_hits_nt.tsv')
        self.assertEqual(list(best[0].keys())[-1], 'sequence')
        self.assertNotIn('sequence_length', best[0])
        self.assertEqual(best[0]['subject_id'], 'a')
        self.assertEqual(best[0]['hsp_count'], '2')
        self.assertEqual(float(best[0]['query_union_coverage']), 50)

        organizer.organize_contigs([self.base / 'sample_all_hsps_nt.tsv'], self.fasta, self.base / 'organized', 'sample')
        output = self.base / 'organized/sample'
        self.assertTrue((output / 'needs_review/contig.fasta').exists())
        self.assertFalse(list((output / 'viruses').rglob('contig.fasta')))
        evidence = read_table(output / 'classification_evidence.tsv')
        self.assertEqual([float(r['bit_score']) for r in evidence], [100.0, 80.0, 50.0])
        self.assertIn('family', read_table(output / 'classification_review.tsv')[0]['review_reason'])

    def test_sorts_final_tsv_xlsx_and_summaries_in_descending_order_across_contigs(self):
        self.fasta.write_text(
            '>contig_1\n' + 'A' * 400 + '\n'
            + '>contig_10\n' + 'C' * 300 + '\n'
            + '>contig_2\n' + 'G' * 1500 + '\n'
            + '>contig_3\n' + 'T' * 800 + '\n'
        )
        self.run_parser([
            hit('s1', 1, 250, score=120, query='contig_1', qlen=400),
            hit('s10', 1, 250, score=190, query='contig_10', qlen=300),
            hit('s2', 1, 1400, score=900, query='contig_2', qlen=1500),
            hit('s3', 1, 700, score=450, query='contig_3', qlen=800),
        ])
        expected_order = ['contig_2', 'contig_3', 'contig_10', 'contig_1']
        best_tsv = read_table(self.base / 'sample_best_hits_nt.tsv')
        self.assertEqual([r['query_id'] for r in best_tsv], expected_order)

        xlsx_rows, _, _, _ = read_xlsx_sheet_xml(self.base / 'sample_best_hits_nt.xlsx')
        self.assertEqual(xlsx_rows[0], blast.BEST_COLUMNS)
        self.assertEqual([r[0] for r in xlsx_rows[1:]], expected_order)
        self.assertEqual(xlsx_rows[1][-1], 'G' * 1500)

        subj = read_table(self.base / 'sample_subject_summary_nt.tsv')
        self.assertEqual([r['query_id'] for r in subj], expected_order)
        hsps = read_table(self.base / 'sample_all_hsps_nt.tsv')
        self.assertEqual([r['query_id'] for r in hsps], expected_order)

        organizer.organize_contigs([self.base / 'sample_all_hsps_nt.tsv'], self.fasta, self.base / 'organized', 'sample')
        evidence = read_table(self.base / 'organized/sample/classification_evidence.tsv')
        self.assertEqual([r['query_id'] for r in evidence], expected_order)

    def test_xlsx_column_widths_control_chars_and_stdlib_fallback(self):
        long_title = '=Polyprotein\x01' + ('VeryLongViralGenomeDescription_' * 5)
        self.run_parser([hit('acc1', 1, 900, score=500, title=long_title)])
        for force_stdlib in [False, True]:
            out_xlsx = self.base / f'check_{force_stdlib}.xlsx'
            rows = read_table(self.base / 'sample_best_hits_nt.tsv')
            blast.write_best_hits_xlsx(out_xlsx, rows, 'nt', force_stdlib=force_stdlib)
            sheet_rows, widths, pane, autofilter = read_xlsx_sheet_xml(out_xlsx)
            self.assertEqual(len(sheet_rows), 2)
            self.assertNotIn('\x01', sheet_rows[1][blast.BEST_COLUMNS.index('subject_title')])
            self.assertTrue(sheet_rows[1][blast.BEST_COLUMNS.index('subject_title')].startswith('=Polyprotein'))
            seq_col_idx = blast.BEST_COLUMNS.index('sequence') + 1
            title_col_idx = blast.BEST_COLUMNS.index('subject_title') + 1
            self.assertEqual(widths[seq_col_idx], 28.0)
            self.assertLessEqual(widths[title_col_idx], 46.0)
            self.assertGreaterEqual(widths[title_col_idx], 22.0)
            for idx, col_name in enumerate(blast.BEST_COLUMNS, 1):
                if col_name != 'sequence':
                    self.assertGreaterEqual(widths[idx], len(col_name) + 5)
            self.assertIsNotNone(pane)
            self.assertEqual(pane.attrib.get('topLeftCell'), 'A2')
            self.assertIsNotNone(autofilter)

    def test_disjoint_regions_of_same_subject_are_not_filled_in(self):
        self.run_parser([hit('a', 1, 100), hit('a', 900, 1000)])
        summary = read_table(self.base / 'sample_subject_summary_nt.tsv')[0]
        self.assertEqual(summary['query_regions'], '1-100;900-1000')
        self.assertEqual(int(summary['query_covered_bases']), 201)

    def test_translated_query_coverage_uses_nucleotide_coordinates(self):
        self.run_parser([hit('protein', 1, 300, length=100), hit('protein', 301, 600, length=100)])
        self.assertEqual(float(read_table(self.base / 'sample_subject_summary_nt.tsv')[0]['query_union_coverage']), 60)

    def test_negative_protein_frame_is_not_labeled_as_subject_strand(self):
        record = hit('protein', 600, 301, length=100)
        record['subject_strand'] = '-2'
        with self.raw.open('w', newline='') as handle:
            csv.DictWriter(handle, fieldnames=blast.COL, delimiter='\t').writerow(record)
        with patch.object(blast, 'TaxonomyResolver', FakeTaxonomy):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nr',
                                       'qcovhsp', strand_field='qframe')
        result = read_table(self.base / 'sample_all_hsps_nr.tsv')[0]
        self.assertEqual((result['query_frame'], result['query_strand'], result['subject_strand']),
                         ('-2', 'minus', ''))

    def test_malformed_search_output_fails_instead_of_shifting_columns(self):
        self.raw.write_text('\t'.join(str(value) for value in list(hit('a', 1, 100).values())[:-1]) + '\n')
        with self.assertRaisesRegex(ValueError, 'expected 18 columns, got 17'):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nt')

    def test_best_report_uses_score_and_keeps_a_whole_row(self):
        self.run_parser([hit('long', 1, 800, score=80), hit('short', 1, 100, score=150)])
        best = read_table(self.base / 'sample_best_hits_nt.tsv')[0]
        self.assertEqual((best['subject_id'], best['alignment_length']), ('short', '100'))

    def test_empty_search_has_headers_and_no_taxonomy_dependency(self):
        self.raw.write_text('')
        with patch.object(blast, 'TaxonomyResolver', side_effect=AssertionError('must not initialize')):
            blast.process_blast_results(self.raw, self.fasta, self.prefix, 'nt')
        for name in ['sample_all_hsps_nt.tsv', 'sample_subject_summary_nt.tsv', 'sample_best_hits_nt.tsv']:
            self.assertEqual(read_table(self.base / name), [])
            self.assertGreater((self.base / name).stat().st_size, 0)
        xlsx_rows, _, _, _ = read_xlsx_sheet_xml(self.base / 'sample_best_hits_nt.xlsx')
        self.assertEqual(xlsx_rows, [blast.BEST_COLUMNS])

    def test_long_contig_sequence_preserved_in_tsv_and_safely_capped_in_xlsx(self):
        self.fasta.write_text('>contig\n' + 'A' * 35000 + '\n')
        self.run_parser([hit('a', 1, 100, qlen=35000)])
        best = read_table(self.base / 'sample_best_hits_nt.tsv')[0]
        self.assertEqual(int(best['query_length']), 35000)
        self.assertEqual(len(best['sequence']), 35000)
        xlsx_rows, _, _, _ = read_xlsx_sheet_xml(self.base / 'sample_best_hits_nt.xlsx')
        xlsx_seq = xlsx_rows[1][-1]
        self.assertEqual(len(xlsx_seq), blast.EXCEL_MAX_CHARS)
        self.assertIn('full 35000 bp in TSV/FASTA', xlsx_seq)

    def test_invalid_coordinates_and_unknown_queries_fail(self):
        for record in [hit('a', 1, 1001), hit('a', 1, 100, query='missing')]:
            with self.subTest(record=record), self.assertRaisesRegex(ValueError, 'raw.tsv:1: invalid hit'):
                self.run_parser([record])

    def test_consistent_family_does_not_invent_species_consensus(self):
        self.run_parser([hit('a', 1, 100), hit('b', 400, 500)])
        path = self.base / 'sample_all_hsps_nt.tsv'
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
        organizer.organize_contigs([self.base / 'sample_all_hsps_nt.tsv'], self.fasta, self.base / 'organized', 'sample')
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
