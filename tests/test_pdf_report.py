# Author: Naveen Duhan
# SPDX-License-Identifier: MIT
"""Unit tests verifying cohort and per-sample PDF and HTML report generation, sample prefix isolation, symlink traversal, and Matplotlib PDF fallback."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / 'bin'
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from generate_reports import generate_all_reports  # noqa: E402
from report_data import collect_cohort_data  # noqa: E402


class FinalReportGenerationTests(unittest.TestCase):
    def _stage_full_cohort(self, tmp_path: Path):
        in_dir = tmp_path / 'inputs'
        (in_dir / '1').mkdir(parents=True)
        (in_dir / '2').mkdir(parents=True)
        (in_dir / '3').mkdir(parents=True)
        (in_dir / '4').mkdir(parents=True)

        # Sample1 contigs FASTA (1,500 bp + 800 bp)
        (in_dir / '1' / 'sample1_metanextviro_megahit_contigs.fa').write_text(
            '>s1_contig_alpha\n' + ('ACGTGCAT' * 188) + '\n'
            '>s1_contig_beta\n' + ('GCTATAGC' * 100) + '\n'
        )

        # Sample10 uses a symlinked QUAST directory (verifying followlinks=True)
        real_quast = tmp_path / 'external_quast' / 'sample10_quast'
        real_quast.mkdir(parents=True)
        (real_quast / 'report.tsv').write_text(
            'Assembly\tsample10\n'
            '# contigs (>= 0 bp)\t4\n'
            '# contigs (>= 1000 bp)\t2\n'
            'Largest contig\t3200\n'
            'Total length (>= 0 bp)\t6400\n'
            'N50\t2100\n'
            'GC (%)\t46.5\n'
        )
        (in_dir / '2' / 'sample10_quast').symlink_to(real_quast, target_is_directory=True)

        # Host depletion & mapping logs
        (in_dir / '1' / 'sample1_host_depletion_stats.txt').write_text(
            '10000 reads; of these:\n42.50% overall alignment rate\n'
        )
        (in_dir / '1' / 'sample1.mapping.log').write_text(
            '5750 reads; of these:\n78.40% overall alignment rate\n'
        )
        (in_dir / '2' / 'sample10.mapping.log').write_text(
            '8000 reads; of these:\n64.15% overall alignment rate\n'
        )

        # Coverage tables
        (in_dir / '1' / 'coverage_sample1.txt').write_text(
            'Contig\tAverage_Coverage\tTotal_Reads\tCovered_Bases\tCoverage_Breadth\n'
            's1_contig_alpha\t145.6\t920\t1480\t98.4\n'
            's1_contig_beta\t22.3\t110\t710\t88.75\n'
        )
        (in_dir / '2' / 'coverage_sample10.txt').write_text(
            'Contig\tAverage_Coverage\tTotal_Reads\tCovered_Bases\tCoverage_Breadth\n'
            's10_contig_omega\t310.2\t2150\t3190\t99.6\n'
        )

        # Kraken2 report for sample1 and sample10
        kraken_txt = (
            ' 12.00\t1200\t1200\tU\t0\tunclassified\n'
            ' 55.00\t5500\t100\tD\t10239\t  Viruses\n'
            ' 40.00\t4000\t4000\tF\t10880\t    Reoviridae\n'
            ' 15.00\t1500\t1500\tF\t11308\t    Orthomyxoviridae\n'
            ' 30.00\t3000\t3000\tD\t2\t  Bacteria\n'
            '  3.00\t300\t300\tD\t2759\t  Eukaryota\n'
        )
        (in_dir / '3' / 'sample1_kraken2_report.txt').write_text(kraken_txt)
        (in_dir / '3' / 'sample10_kraken2_report.txt').write_text(kraken_txt)

        # BLAST best hits (descending sorted)
        blast_hdr = (
            'query_id\tsubject_id\tpercent_identity\talignment_length\tevalue\tbit_score\t'
            'query_length\tsubject_length\tquery_union_coverage\tsubject_title\tsuperkingdom\t'
            'family\tspecies\n'
        )
        (in_dir / '3' / 'sample1_best_hits_viruses.tsv').write_text(
            blast_hdr
            + 's1_contig_alpha\tNC_01\t94.2\t1460\t1e-180\t2150\t1504\t1550\t97.1\tAvian orthoreovirus S1\tViruses\tSpinareoviridae\tAvian orthoreovirus\n'
        )
        (in_dir / '3' / 'sample10_best_hits_viruses.tsv').write_text(
            blast_hdr
            + 's10_contig_omega\tNC_09\t89.5\t2980\t0.0\t4120\t3200\t3250\t93.1\tInfluenza A PB2\tViruses\tOrthomyxoviridae\tAlphainfluenzavirus influenzae\n'
        )

        # Novel virus candidates
        novel_hdr = (
            'query_id\tcontig_length\tdiscovery_classification\tdiscovery_score\t'
            'putative_order\tputative_family\ttaxonomy_evidence_source\thallmark_category\t'
            'terminal_repeat_type\tcoding_density\tcoverage_breadth_pct\tvirfinder_score\n'
        )
        (in_dir / '4' / 'sample1_novel_virus_candidates.tsv').write_text(
            novel_hdr
            + 's1_contig_beta\t800\tputative_novel_virus_high_confidence\t86.5\t'
            'Picornavirales\tCaliciviridae\tprotein_lca+hmm_lca\tRdRp\tDTR\t89.2\t88.75\t0.96\n'
        )
        return in_dir

    def test_cohort_and_sample_reports_prevent_prefix_collision_and_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            in_dir = self._stage_full_cohort(tmp_path)
            out_dir = tmp_path / 'final_report'
            meta = {
                'version': '1.0.0',
                'nextflow_version': '26.10.5',
                'run_name': 'unit_test_run',
                'assembler': 'megahit',
                'deplete_host': True,
                'blast_options': 'viruses',
            }
            logo = ROOT / 'logo.png'
            generate_all_reports(
                ['sample1', 'sample10'],
                in_dir,
                out_dir,
                logo_path=str(logo) if logo.exists() else None,
                run_meta=meta,
            )

            cohort_pdf = out_dir / 'MetaNextViro_Summary_Report.pdf'
            cohort_html = out_dir / 'MetaNextViro_Summary_Report.html'
            s1_pdf = out_dir / 'per_sample' / 'sample1_Viral_Report.pdf'
            s1_html = out_dir / 'per_sample' / 'sample1_Viral_Report.html'
            s10_pdf = out_dir / 'per_sample' / 'sample10_Viral_Report.pdf'
            s10_html = out_dir / 'per_sample' / 'sample10_Viral_Report.html'

            for pdf_file in (cohort_pdf, s1_pdf, s10_pdf):
                self.assertTrue(pdf_file.is_file(), f'Missing {pdf_file}')
                self.assertTrue(pdf_file.read_bytes().startswith(b'%PDF-'))
                self.assertGreater(pdf_file.stat().st_size, 1500)

            html_text = cohort_html.read_text(encoding='utf-8')
            self.assertIn('role="region"', html_text)
            self.assertIn('@container (width < 640px)', html_text)
            self.assertIn('command="--sort"', html_text)
            self.assertIn('data-value=', html_text)
            self.assertIn('id="sort-status" role="status"', html_text)
            self.assertIn('data:image/png;base64,', html_text)
            self.assertIn('per_sample/sample1_Viral_Report.html', html_text)
            self.assertIn('per_sample/sample10_Viral_Report.pdf', html_text)
            self.assertIn('Picornavirales', html_text)
            self.assertIn('Caliciviridae', html_text)

            # Sample1 report must NOT leak sample10 contigs (prefix collision regression check)
            s1_text = s1_html.read_text(encoding='utf-8')
            self.assertIn('s1_contig_alpha', s1_text)
            self.assertNotIn('s10_contig_omega', s1_text)

            # Sample10 report must pick up symlinked QUAST N50 (2,100 bp) and sample10 contig
            s10_text = s10_html.read_text(encoding='utf-8')
            self.assertIn('s10_contig_omega', s10_text)
            self.assertIn('2,100', s10_text)
            self.assertNotIn('s1_contig_alpha', s10_text)

    def test_targeted_blast_only_and_matplotlib_pdf_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            in_dir = tmp_path / 'inputs'
            in_dir.mkdir()
            (in_dir / 'sampleA_metanextviro_megahit_contigs.fa').write_text(
                '>c1\n' + ('ATGCN' * 240).replace('N', 'G') + '\n'
            )
            (in_dir / 'virfinder_sampleA_full.txt').write_text(
                'name\tlength\tscore\tpvalue\tqvalue\tgc_percent\tn_fraction\tkmer_entropy\tlow_complexity_flag\tconfidence_tier\n'
                'c1\t1200\t0.94\t0.001\t0.005\t48.0\t0.0\t0.92\tno\thigh_confidence\n'
            )

            out_dir = tmp_path / 'out_fallback'
            generate_all_reports(
                ['sampleA'],
                in_dir,
                out_dir,
                logo_path=str(ROOT / 'nextflow.config'),  # non-image path must be ignored safely
                run_meta={'skip_taxonomic_profiling': True},
                force_pdf_fallback=True,
            )

            self.assertTrue((out_dir / 'MetaNextViro_Summary_Report.pdf').read_bytes().startswith(b'%PDF-'))
            self.assertTrue((out_dir / 'per_sample' / 'sampleA_Viral_Report.pdf').read_bytes().startswith(b'%PDF-'))
            cohort_html = (out_dir / 'MetaNextViro_Summary_Report.html').read_text(encoding='utf-8')
            self.assertNotIn('id="kraken-summary"', cohort_html)
            self.assertIn('virfinder_kmer_only', cohort_html)


if __name__ == '__main__':
    unittest.main()
