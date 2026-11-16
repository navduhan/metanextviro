"""Unit regressions for automated post-BLAST contig triage and novel virus discovery."""
import csv
import importlib.util
import random
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from Bio import SeqIO
from Bio.Seq import Seq

ROOT = Path(__file__).resolve().parents[1]
NS = {'main': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'nextflow/bin' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


blast = load_script('process_blast_results')
triage = load_script('triage_contigs')
arch = load_script('scan_viral_architecture')
parsers = load_script('parse_discovery_hits')
synth = load_script('synthesize_novel_viruses')


def read_table(path):
    with open(path, newline='') as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


SENSE_CODONS = [
    a + b + c for a in 'ACGT' for b in 'ACGT' for c in 'ACGT'
    if (a + b + c) not in ('TAA', 'TAG', 'TGA')
]


def make_coding_seq(codons_count, dtr_len=0, itr_len=0, seed=17):
    rng = random.Random(seed)
    body = 'ATG' + ''.join(rng.choice(SENSE_CODONS) for _ in range(codons_count)) + 'TAA'
    if dtr_len:
        flank = ''.join(rng.choice('ACGT') for _ in range(dtr_len))
        return flank + body + flank
    if itr_len:
        flank = ''.join(rng.choice('ACGT') for _ in range(itr_len))
        return flank + body + str(Seq(flank).reverse_complement())
    return body


class NovelDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def write_hsp_file(self, path, rows):
        with open(path, 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=blast.HSP_COLUMNS, delimiter='\t')
            writer.writeheader()
            for r in rows:
                base_row = dict.fromkeys(blast.HSP_COLUMNS, '')
                base_row.update(r)
                writer.writerow(base_row)

    def test_triage_skips_confident_known_viral_and_cellular_hits_automatically(self):
        fasta = self.base / 'contigs.fa'
        seqs = {
            'known_vir': make_coding_seq(150),        # ~906 bp
            'known_bact': make_coding_seq(160),       # ~966 bp
            'short_unk': 'ACGT' * 80,                 # 320 bp (<500)
            'divergent_vir': make_coding_seq(180),    # ~1086 bp
            'dark_matter': make_coding_seq(200),      # ~1206 bp
        }
        fasta.write_text(''.join(f'>{k}\n{v}\n' for k, v in seqs.items()))

        hsps = self.base / 'hsps.tsv'
        self.write_hsp_file(hsps, [
            {
                'query_id': 'known_vir', 'query_length': len(seqs['known_vir']),
                'alignment_length': 850, 'percent_identity': 96.5, 'query_coverage': 93.8,
                'bit_score': 1500, 'evalue': '0.0', 'subject_id': 'NC_001',
                'subject_title': 'Known virus', 'superkingdom': 'Viruses',
                'family': 'Picornaviridae', 'species': 'Known_sp',
                'query_start': 1, 'query_end': 850, 'search_database': 'viruses',
            },
            {
                'query_id': 'known_bact', 'query_length': len(seqs['known_bact']),
                'alignment_length': 800, 'percent_identity': 94.0, 'query_coverage': 82.8,
                'bit_score': 1300, 'evalue': '0.0', 'subject_id': 'NZ_001',
                'subject_title': 'E. coli', 'superkingdom': 'Bacteria',
                'query_start': 1, 'query_end': 800, 'search_database': 'nt',
            },
            {
                'query_id': 'divergent_vir', 'query_length': len(seqs['divergent_vir']),
                'alignment_length': 350, 'percent_identity': 66.2, 'query_coverage': 32.2,
                'bit_score': 180, 'evalue': '1e-35', 'subject_id': 'NC_099',
                'subject_title': 'Distant virus', 'superkingdom': 'Viruses',
                'family': 'Dicistroviridae', 'query_start': 100, 'query_end': 449,
                'search_database': 'viruses',
            },
        ])

        prefix = str(self.base / 'sample')
        triage.triage_contigs(fasta, [hsps], prefix, min_candidate_length=500)
        with open(self.base / 'sample_candidate_contigs.fa') as handle:
            cand_ids = [rec.id for rec in SeqIO.parse(handle, 'fasta')]
        self.assertEqual(cand_ids, ['dark_matter', 'divergent_vir'])

        manifest = {r['query_id']: r for r in read_table(self.base / 'sample_triage_manifest.tsv')}
        self.assertEqual(manifest['known_vir']['triage_category'], 'known_virus')
        self.assertEqual(manifest['known_vir']['send_to_discovery'], 'no')
        self.assertEqual(manifest['known_bact']['triage_category'], 'known_non_viral')
        self.assertEqual(manifest['short_unk']['triage_category'], 'short_unassigned')
        self.assertEqual(manifest['divergent_vir']['triage_reason'], 'divergent_or_partial_viral_hit')
        self.assertEqual(manifest['dark_matter']['triage_reason'], 'no_blast_hit')

    def test_architecture_scanner_detects_dtr_itr_low_complexity_and_empty_input(self):
        fasta = self.base / 'cands.fa'
        dtr_contig = make_coding_seq(180, dtr_len=30)
        itr_contig = make_coding_seq(160, itr_len=26)
        low_comp = 'ATATATATAT' * 80
        stop_riddled = ('TAATAGTGATAA' * 150)  # 1800 bp dense stop codons in forward frames + AT low entropy
        fasta.write_text(
            f'>dtr_vir\n{dtr_contig}\n'
            f'>itr_vir\n{itr_contig}\n'
            f'>repeat_seq\n{low_comp}\n'
            f'>stops_seq\n{stop_riddled}\n'
        )
        prefix = str(self.base / 'sample')
        arch.scan_viral_architecture(fasta, prefix, min_orf_aa=60)
        metrics = {r['query_id']: r for r in read_table(self.base / 'sample_architecture_metrics.tsv')}

        self.assertEqual(metrics['dtr_vir']['terminal_repeat_type'], 'DTR')
        self.assertGreaterEqual(int(metrics['dtr_vir']['terminal_repeat_length']), 30)
        self.assertGreater(float(metrics['dtr_vir']['coding_density']), 80.0)

        self.assertEqual(metrics['itr_vir']['terminal_repeat_type'], 'ITR')
        self.assertGreaterEqual(int(metrics['itr_vir']['terminal_repeat_length']), 26)

        self.assertEqual(metrics['repeat_seq']['low_complexity_flag'], 'yes')

        # Empty input must not crash and must produce valid headers
        empty_fa = self.base / 'empty.fa'
        empty_fa.write_text('')
        arch.scan_viral_architecture(empty_fa, str(self.base / 'empty'))
        self.assertEqual(read_table(self.base / 'empty_architecture_metrics.tsv'), [])
        self.assertEqual((self.base / 'empty_candidate_orfs.faa').read_text(), '')

    def test_end_to_end_synthesis_ranks_high_moderate_eve_plasmid_and_dark_matter(self):
        rng = random.Random(99)
        dark_noncoding = ''.join(
            rng.choice(['TAA', 'TAG', 'TGA']) if i % 8 == 0 else rng.choice(SENSE_CODONS)
            for i in range(220)
        )
        contigs = {
            'cand_vf': make_coding_seq(220, itr_len=24, seed=2),     # High-confidence (VF + 2-ORF Picornavirales LCA)
            'cand_rdrp': make_coding_seq(300, dtr_len=25, seed=1),   # High-confidence (VOG RdRp HMM)
            'cand_vf_only': make_coding_seq(170, seed=5),            # Moderate-confidence (VF k-mer only, no homolog)
            'cand_eve': make_coding_seq(200, seed=3),                # Host-flanked EVE/provirus
            'cand_dark': dark_noncoding,                             # Unconfirmed dark matter
            'cand_plasmid': make_coding_seq(190, seed=4),            # geNomad plasmid
        }
        fasta = self.base / 'contigs.fa'
        fasta.write_text(''.join(f'>{k}\n{v}\n' for k, v in contigs.items()))

        prefix = str(self.base / 'sample')
        triage.triage_contigs(fasta, [], prefix, min_candidate_length=500)
        arch.scan_viral_architecture(self.base / 'sample_candidate_contigs.fa', prefix, min_orf_aa=60)

        # Coverage table
        cov_tsv = self.base / 'coverage.tsv'
        cov_tsv.write_text(
            'Contig\tAverage_Coverage\tTotal_Reads\tCovered_Bases\tCoverage_Breadth\n'
            f'cand_rdrp\t120.5\t2400\t{len(contigs["cand_rdrp"])}\t99.5\n'
            f'cand_vf\t35.2\t600\t{len(contigs["cand_vf"])}\t94.0\n'
            f'cand_vf_only\t20.0\t300\t{len(contigs["cand_vf_only"])}\t91.0\n'
            f'cand_eve\t18.0\t200\t400\t33.0\n'
            f'cand_plasmid\t50.0\t800\t{len(contigs["cand_plasmid"])}\t98.0\n'
            f'cand_dark\t5.0\t50\t600\t90.0\n'
        )

        # HMM domtblout fixture for cand_rdrp_orf1 + VOG LCA taxonomy lookup
        domtbl = self.base / 'domtbl.txt'
        domtbl.write_text(
            'cand_rdrp_orf1 - 602 VOG00500 PF00680 450 1.2e-42 148.5 0.1 '
            '1 1 2.0e-45 2.5e-42 147.9 0.1 10 430 50 470 48 475 0.96 RNA-dependent RNA polymerase\n'
        )
        hmm_tax = self.base / 'vog_tax.tsv'
        hmm_tax.write_text(
            'hmm_name\tfunctional_category\tdescription\tlca_lineage\n'
            'VOG00500\tXr\tRNA-dependent RNA polymerase\tViruses;Riboviria;Orthornavirae;Pisuviricota;Pisoniviricetes;Picornavirales\n'
        )
        hmm_tsv = self.base / 'hmm.tsv'
        parsers.parse_hmmer_domtblout(domtbl, hmm_tsv, hmm_taxonomy_path=hmm_tax)

        # Multi-ORF viral protein table for cand_vf (two ORFs agreeing on Order Picornavirales, differing on Family)
        vp_tsv = self.base / 'vp.tsv'
        with open(vp_tsv, 'w', newline='') as vp_out:
            writer = csv.DictWriter(vp_out, fieldnames=parsers.VP_COLUMNS, delimiter='\t')
            writer.writeheader()
            writer.writerow({
                'query_id': 'cand_vf', 'orf_id': 'cand_vf_orf1', 'subject_id': 'YP_1',
                'percent_identity': 38.0, 'alignment_length': 200, 'orf_coverage_pct': 85.0,
                'evalue': 1e-30, 'bit_score': 180.0, 'orf_length_aa': 220, 'subject_length': 230,
                'tax_id': '1', 'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota',
                'class': 'Pisoniviricetes', 'order': 'Picornavirales', 'family': 'Picornaviridae',
                'genus': 'Enterovirus', 'species': 'Enterovirus A', 'taxonomy_status': 'resolved',
                'subject_title': 'capsid [Enterovirus A]',
            })
            writer.writerow({
                'query_id': 'cand_vf', 'orf_id': 'cand_vf_orf2', 'subject_id': 'YP_2',
                'percent_identity': 34.0, 'alignment_length': 190, 'orf_coverage_pct': 80.0,
                'evalue': 1e-25, 'bit_score': 160.0, 'orf_length_aa': 210, 'subject_length': 220,
                'tax_id': '2', 'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota',
                'class': 'Pisoniviricetes', 'order': 'Picornavirales', 'family': 'Dicistroviridae',
                'genus': 'Cripavirus', 'species': 'Cricket paralysis virus', 'taxonomy_status': 'resolved',
                'subject_title': 'helicase [Cricket paralysis virus]',
            })

        # VirFinder table
        vf_tsv = self.base / 'vf.tsv'
        vf_tsv.write_text(
            'name\tlength\tscore\tpvalue\tqvalue\tgc_percent\tn_fraction\tkmer_entropy\tlow_complexity_flag\tconfidence_tier\n'
            f'cand_vf\t{len(contigs["cand_vf"])}\t0.96\t0.0005\t0.005\t50.0\t0.0\t0.88\tno\thigh_confidence\n'
            f'cand_vf_only\t{len(contigs["cand_vf_only"])}\t0.91\t0.004\t0.02\t49.0\t0.0\t0.86\tno\thigh_confidence\n'
        )

        # CheckV summary flagging host genes on cand_eve
        cv_tsv = self.base / 'checkv.tsv'
        cv_tsv.write_text(
            'contig_id\tcheckv_quality\tcompleteness\tviral_genes\thost_genes\n'
            'cand_eve\tLow-quality\t25.0\t2\t3\n'
        )

        # geNomad plasmid call on cand_plasmid
        gm_vir = self.base / 'gm_vir.tsv'
        gm_vir.write_text('seq_name\tvirus_score\tn_hallmarks\ttopology\ttaxonomy\n')
        gm_plas = self.base / 'gm_plas.tsv'
        gm_plas.write_text('seq_name\tplasmid_score\n' 'cand_plasmid\t0.92\n')

        vf_tax_prefix = str(self.base / 'virfinder_sample_taxonomy')
        synth.synthesize_novel_viruses(
            contigs_fasta=fasta,
            candidate_orfs=self.base / 'sample_candidate_orfs.faa',
            triage_manifest=self.base / 'sample_triage_manifest.tsv',
            architecture_tsv=self.base / 'sample_architecture_metrics.tsv',
            prefix=prefix,
            coverage_tsv=cov_tsv,
            virfinder_tsv=vf_tsv,
            checkv_tsv=cv_tsv,
            genomad_virus_tsv=gm_vir,
            genomad_plasmid_tsv=gm_plas,
            hmm_tsv=hmm_tsv,
            viral_protein_tsv=vp_tsv,
            virfinder_tax_prefix=vf_tax_prefix,
        )

        rows = read_table(self.base / 'sample_novel_virus_candidates.tsv')
        self.assertEqual(
            [r['query_id'] for r in rows],
            ['cand_vf', 'cand_rdrp', 'cand_vf_only', 'cand_eve', 'cand_dark', 'cand_plasmid'],
        )
        by_id = {r['query_id']: r for r in rows}
        self.assertEqual(by_id['cand_rdrp']['discovery_classification'], 'putative_novel_virus_high_confidence')
        self.assertEqual(by_id['cand_rdrp']['hallmark_category'], 'RdRp')
        self.assertEqual(by_id['cand_rdrp']['putative_order'], 'Picornavirales')
        self.assertEqual(by_id['cand_rdrp']['putative_kingdom'], 'Orthornavirae')

        # Two ORFs disagree at Family (53% vs 47% bitscore < 60% threshold), so LCA resolves cleanly to Order = Picornavirales!
        self.assertEqual(by_id['cand_vf']['discovery_classification'], 'putative_novel_virus_high_confidence')
        self.assertEqual(by_id['cand_vf']['putative_order'], 'Picornavirales')
        self.assertEqual(by_id['cand_vf']['putative_family'], '')
        self.assertEqual(by_id['cand_vf']['taxonomy_evidence_source'], 'viral_protein_lca(2_orfs)')

        self.assertEqual(by_id['cand_vf_only']['discovery_classification'], 'putative_novel_virus_moderate_confidence')
        self.assertEqual(by_id['cand_vf_only']['taxonomy_evidence_source'], 'none_kmer_or_architecture_only')

        # VirFinder taxonomy table assigns Order Picornavirales directly alongside VirFinder score!
        vf_tax_rows = read_table(self.base / 'virfinder_sample_taxonomy.tsv')
        self.assertEqual([r['query_id'] for r in vf_tax_rows], ['cand_vf', 'cand_vf_only'])
        self.assertEqual(vf_tax_rows[0]['putative_order'], 'Picornavirales')
        self.assertTrue((self.base / 'virfinder_sample_taxonomy.xlsx').is_file())

        self.assertEqual(by_id['cand_eve']['discovery_classification'], 'possible_eve_or_provirus_needs_review')
        self.assertEqual(by_id['cand_dark']['discovery_classification'], 'unconfirmed_dark_matter')
        self.assertEqual(by_id['cand_plasmid']['discovery_classification'], 'plasmid_or_low_complexity_artifact')

        # Only high and moderate confidence novel candidates are promoted to FASTA/ORF outputs
        with open(self.base / 'sample_novel_virus_candidates.fasta') as nt_handle:
            promoted_nt = [rec.id for rec in SeqIO.parse(nt_handle, 'fasta')]
        self.assertEqual(promoted_nt, ['cand_vf', 'cand_rdrp', 'cand_vf_only'])
        with open(self.base / 'sample_novel_virus_orfs.faa') as aa_handle:
            promoted_aa = [rec.id for rec in SeqIO.parse(aa_handle, 'fasta')]
        self.assertTrue(any(i.startswith('cand_rdrp_orf') for i in promoted_aa))
        self.assertFalse(any(i.startswith('cand_eve_orf') for i in promoted_aa))

        # Verify XLSX exists, has sequence at final column with clamped width 28.0
        xlsx_path = self.base / 'sample_novel_virus_candidates.xlsx'
        with zipfile.ZipFile(xlsx_path) as zf:
            sheet_root = ET.fromstring(zf.read('xl/worksheets/sheet1.xml'))
        cols = {}
        for col_el in sheet_root.findall('.//main:cols/main:col', NS):
            for idx in range(int(col_el.attrib['min']), int(col_el.attrib['max']) + 1):
                cols[idx] = float(col_el.attrib['width'])
        seq_col_idx = synth.CANDIDATE_COLUMNS.index('sequence') + 1
        self.assertEqual(cols[seq_col_idx], 28.0)


if __name__ == '__main__':
    unittest.main()
