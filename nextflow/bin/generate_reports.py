#!/usr/bin/env python3
"""Generate Cohort and Sample-Wise PDF + Interactive HTML reports for MetaNextViro."""

import argparse
import base64
import html
import json
import os
import sys
import tempfile
import textwrap
from datetime import datetime
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.backends.backend_pdf import PdfPages  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from report_data import (  # noqa: E402
    build_methods_paragraph,
    collect_cohort_data,
    render_cohort_figures,
    render_sample_figures,
    safe_float,
    safe_int,
)

CAVEATS_TEXT = (
    "Scientific Interpretation Guardrails: (1) Sequence identification in metagenomic reads or contigs "
    "does not by itself confirm active viral replication or host infection; evaluate read breadth, negative "
    "controls, and phylogenetic placement. (2) Query union coverage reflects reference alignment coordinate "
    "spans rather than verified genome termini. (3) Putative higher-rank novel taxonomy (Order/Family) is "
    "inferred conservatively via homology LCA and awaits formal ICTV demarcation review."
)


def _is_valid_image(path_str):
    return bool(
        path_str and os.path.isfile(path_str)
        and str(path_str).lower().endswith(('.png', '.jpg', '.jpeg'))
    )


def fmt_int(val):
    return f'{safe_int(val):,}'


def fmt_pct(val):
    if val is None or val == '':
        return 'N/A'
    return f'{safe_float(val):.1f}%'


def fmt_float(val, digits=1):
    if val is None or val == '':
        return 'N/A'
    return f'{safe_float(val):.{digits}f}'


def build_cohort_spec(data, figs, timestamp_str):
    sids = data['sample_ids']
    samples = data['samples']
    meta = data['run_meta']
    total_contigs = sum(samples[s]['assembly']['total_contigs'] for s in sids)
    distinct_fams = len([f for f in data['family_matrix'] if f != 'Unclassified_Viruses'])
    high_novel = sum(1 for r in data['promoted_novel'] if r.get('discovery_classification') == 'putative_novel_virus_high_confidence')
    mod_novel = len(data['promoted_novel']) - high_novel

    kpis = [
        ('Samples Analyzed', fmt_int(len(sids)), 'Cohort size'),
        ('Assembled Contigs', fmt_int(total_contigs), f"Assembler: {meta.get('assembler', 'megahit')}"),
        ('Known Viral Contigs', fmt_int(len(data['all_viral_hits'])), f'{distinct_fams} viral families'),
        ('Novel Candidates', fmt_int(len(data['promoted_novel'])), f'{high_novel} high / {mod_novel} moderate'),
    ]

    sections = []

    # 1. Assembly & Mapping QC
    qc_headers = [
        ('Sample', 'text'), ('Contigs', 'number'), ('Contigs >= 1 kb', 'number'),
        ('Max Contig (bp)', 'number'), ('Assembly Size (bp)', 'number'),
        ('N50 (bp)', 'number'), ('GC (%)', 'number'), ('Host Depleted (%)', 'number'),
        ('Mapped to Contigs (%)', 'number'),
    ]
    qc_rows = []
    for s in sids:
        asm = samples[s]['assembly']
        h_pct = samples[s]['host_depleted_pct']
        m_pct = samples[s]['contig_mapping_pct']
        qc_rows.append([
            (s, s),
            (fmt_int(asm['total_contigs']), asm['total_contigs']),
            (fmt_int(asm['contigs_ge_1kb']), asm['contigs_ge_1kb']),
            (fmt_int(asm['max_contig_bp']), asm['max_contig_bp']),
            (fmt_int(asm['total_bp']), asm['total_bp']),
            (fmt_int(asm['n50_bp']), asm['n50_bp']),
            (fmt_float(asm['gc_pct'], 2), asm['gc_pct']),
            (fmt_pct(h_pct) if h_pct is not None else 'Skipped', h_pct if h_pct is not None else -1),
            (fmt_pct(m_pct) if m_pct is not None else 'N/A', m_pct if m_pct is not None else -1),
        ])
    sections.append({
        'id': 'assembly-qc',
        'title': '1. Preprocessing, Host Depletion & Assembly Quality',
        'intro': 'Contiguity, GC composition, optional pre-assembly host subtraction, and read-to-contig mapping rates across all samples.',
        'figure': figs.get('qc'),
        'fig_alt': 'Two-panel horizontal bar chart comparing assembly N50 and total contig counts across samples.',
        'tables': [{
            'id': 'tbl-cohort-qc',
            'caption': 'Per-sample assembly and read alignment summary',
            'headers': qc_headers,
            'rows': qc_rows,
            'col_weights': [1.4, 0.9, 1.0, 1.1, 1.2, 0.9, 0.8, 1.0, 1.1],
        }],
    })

    # 2. Kraken2 Read Classification
    kraken_sids = [s for s in sids if samples[s]['kraken'] is not None]
    if kraken_sids:
        kr_headers = [
            ('Sample', 'text'), ('Viruses (%)', 'number'), ('Bacteria (%)', 'number'),
            ('Eukaryota (%)', 'number'), ('Archaea (%)', 'number'),
            ('Unclassified (%)', 'number'), ('Top Viral Families (Read Level)', 'text'),
        ]
        kr_rows = []
        for s in kraken_sids:
            kr = samples[s]['kraken']
            top_vf = ', '.join(f'{n} ({p:.2f}%)' for n, p, _ in kr['viral_families'][:3]) or 'None detected'
            kr_rows.append([
                (s, s),
                (fmt_float(kr['viruses_pct'], 2), kr['viruses_pct']),
                (fmt_float(kr['bacteria_pct'], 2), kr['bacteria_pct']),
                (fmt_float(kr['eukaryota_pct'], 2), kr['eukaryota_pct']),
                (fmt_float(kr['archaea_pct'], 2), kr['archaea_pct']),
                (fmt_float(kr['unclassified_pct'], 2), kr['unclassified_pct']),
                (top_vf, top_vf),
            ])
        sections.append({
            'id': 'kraken-summary',
            'title': '2. Read-Level Taxonomic Profiling (Kraken2)',
            'intro': 'Exact k-mer read classification proportions and dominant read-level viral families.',
            'figure': figs.get('kraken'),
            'fig_alt': 'Stacked horizontal bar chart of Kraken2 read classification percentages across samples.',
            'tables': [{
                'id': 'tbl-cohort-kraken',
                'caption': 'Kraken2 domain and viral family read proportions',
                'headers': kr_headers,
                'rows': kr_rows,
                'col_weights': [1.3, 0.9, 0.9, 0.9, 0.8, 1.0, 2.8],
            }],
        })

    # 3. Known Viral Identifications (BLAST + Coverage Joined)
    if data['all_viral_hits'] or not meta.get('skip_blast_annotation'):
        bl_headers = [
            ('Sample', 'text'), ('Contig ID', 'text'), ('Length (bp)', 'number'),
            ('Align (bp/aa)', 'number'), ('Identity (%)', 'number'),
            ('Union Cov (%)', 'number'), ('Depth (x)', 'number'),
            ('Breadth (%)', 'number'), ('Viral Family', 'text'), ('Closest Reference / Species', 'text'),
        ]
        bl_rows = []
        for h in data['all_viral_hits'][:60]:
            fam = h.get('family', '').strip() or 'Unclassified'
            sp = h.get('species', '').strip() or h.get('subject_title', '')[:65]
            bl_rows.append([
                (h['sample_id'], h['sample_id']),
                (h['query_id'], h['query_id']),
                (fmt_int(h.get('query_length')), safe_int(h.get('query_length'))),
                (fmt_int(h.get('alignment_length')), safe_int(h.get('alignment_length'))),
                (fmt_float(h.get('percent_identity'), 1), safe_float(h.get('percent_identity'))),
                (fmt_float(h.get('query_union_coverage'), 1), safe_float(h.get('query_union_coverage'))),
                (fmt_float(h.get('mean_depth'), 1), safe_float(h.get('mean_depth'))),
                (fmt_float(h.get('breadth_pct'), 1), safe_float(h.get('breadth_pct'))),
                (fam, fam),
                (sp, sp),
            ])
        tables_list = []
        if bl_rows:
            tables_list.append({
                'id': 'tbl-cohort-blast',
                'caption': f"Top known viral contigs sorted descending by alignment length (showing {len(bl_rows)} of {len(data['all_viral_hits'])})",
                'headers': bl_headers,
                'rows': bl_rows,
                'col_weights': [1.0, 1.6, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 1.2, 2.0],
            })
        if data['family_matrix'] and len(sids) >= 1:
            fm_headers = [('Viral Family', 'text'), ('Total Viral Contigs', 'number'), ('Samples Positive', 'number'), ('Peak Read Depth (x)', 'number')]
            fm_rows = []
            for fam, per_s in sorted(data['family_matrix'].items(), key=lambda kv: (-sum(v['count'] for v in kv[1].values()), kv[0])):
                tot_c = sum(v['count'] for v in per_s.values())
                pos_s = sum(1 for v in per_s.values() if v['count'] > 0)
                max_d = max((v['max_depth'] for v in per_s.values()), default=0.0)
                fm_rows.append([
                    (fam, fam), (fmt_int(tot_c), tot_c), (f'{pos_s}/{len(sids)}', pos_s), (fmt_float(max_d, 1), max_d)
                ])
            tables_list.append({
                'id': 'tbl-family-matrix',
                'caption': 'Viral family detection summary across cohort',
                'headers': fm_headers,
                'rows': fm_rows,
                'col_weights': [2.5, 1.3, 1.3, 1.3],
            })
        sections.append({
            'id': 'known-viruses',
            'title': '3. Known Viral Identifications (BLAST + Read Coverage)',
            'intro': (
                f"Identified {len(data['all_viral_hits'])} viral contigs across {distinct_fams} viral families, "
                "sorted in descending order of alignment length and joined with whole-contig read depth and breadth."
                if data['all_viral_hits'] else "No known viral contigs met BLAST homology thresholds in this run."
            ),
            'figure': figs.get('blast'),
            'fig_alt': 'Scatter bubble plot of viral contig length versus log10 mean read depth, sized by coverage breadth.',
            'tables': tables_list,
        })

    # 4. Novel Virus Discovery & VirFinder Putative Taxonomy
    if data['all_novel_candidates']:
        nv_headers = [
            ('Sample', 'text'), ('Contig ID', 'text'), ('Len (bp)', 'number'),
            ('Classification', 'text'), ('Score', 'number'), ('Putative Order', 'text'),
            ('Putative Family', 'text'), ('Tax Source', 'text'), ('Hallmark / Repeat', 'text'),
            ('Coding (%)', 'number'), ('Breadth (%)', 'number'),
        ]
        nv_rows = []
        for r in data['all_novel_candidates'][:50]:
            cls_short = r.get('discovery_classification', '').replace('putative_novel_virus_', 'novel_').replace('_needs_review', '')
            hall = r.get('hallmark_category') or ''
            rep = r.get('terminal_repeat_type', 'none')
            feat = ', '.join(x for x in [hall, rep if rep != 'none' else ''] if x) or '-'
            nv_rows.append([
                (r['sample_id'], r['sample_id']),
                (r['query_id'], r['query_id']),
                (fmt_int(r.get('contig_length')), safe_int(r.get('contig_length'))),
                (cls_short, cls_short),
                (fmt_float(r.get('discovery_score'), 1), safe_float(r.get('discovery_score'))),
                (r.get('putative_order') or '-', r.get('putative_order') or ''),
                (r.get('putative_family') or '-', r.get('putative_family') or ''),
                (r.get('taxonomy_evidence_source') or '-', r.get('taxonomy_evidence_source') or ''),
                (feat, feat),
                (fmt_float(r.get('coding_density'), 1), safe_float(r.get('coding_density'))),
                (fmt_float(r.get('coverage_breadth_pct'), 1) if r.get('coverage_breadth_pct') != '' else 'N/A', safe_float(r.get('coverage_breadth_pct'), -1)),
            ])
        eve_cnt = sum(1 for r in data['all_novel_candidates'] if r.get('discovery_classification') == 'possible_eve_or_provirus_needs_review')
        art_cnt = sum(1 for r in data['all_novel_candidates'] if r.get('discovery_classification') == 'plasmid_or_low_complexity_artifact')
        sections.append({
            'id': 'novel-discovery',
            'title': '4. Novel & Divergent Virus Discovery (Automated Post-BLAST Cascade)',
            'intro': (
                f"Evaluated {len(data['all_novel_candidates'])} unassigned/divergent contigs after automatically skipping "
                f"confident BLAST hits: {len(data['promoted_novel'])} promoted as putative novel candidates, "
                f"{eve_cnt} held for EVE/provirus review, and {art_cnt} flagged as plasmid or low-complexity artifacts."
            ),
            'figure': figs.get('novel'),
            'fig_alt': 'Scatter plot of 6-frame ORF coding density versus contig length for candidate novel viral contigs.',
            'tables': [{
                'id': 'tbl-cohort-novel',
                'caption': 'Ranked novel and divergent viral candidates with putative ICTV Order/Family assignments',
                'headers': nv_headers,
                'rows': nv_rows,
                'col_weights': [0.9, 1.4, 0.7, 1.4, 0.6, 1.1, 1.1, 1.2, 0.9, 0.7, 0.7],
            }],
        })

    return {
        'report_title': 'MetaNextViro Cohort Analysis Report',
        'subtitle': f"Viral Metagenomics, Coverage & Novel Virus Discovery Summary ({len(sids)} Sample{'s' if len(sids) != 1 else ''})",
        'timestamp': timestamp_str,
        'run_meta': meta,
        'kpis': kpis,
        'sections': sections,
        'methods': build_methods_paragraph(data),
        'caveats': CAVEATS_TEXT,
        'sample_links': [
            {'sample_id': s, 'html': f'per_sample/{s}_Viral_Report.html', 'pdf': f'per_sample/{s}_Viral_Report.pdf'}
            for s in sids
        ],
    }


def build_sample_spec(sid, data, sample_figs, timestamp_str):
    s = data['samples'][sid]
    meta = data['run_meta']
    asm = s['assembly']
    prom = [
        r for r in s['novel_rows']
        if r.get('discovery_classification') in (
            'putative_novel_virus_high_confidence',
            'putative_novel_virus_moderate_confidence',
        )
    ]
    kpis = [
        ('Assembled Contigs', fmt_int(asm['total_contigs']), f"N50: {fmt_int(asm['n50_bp'])} bp"),
        ('Max Contig Length', f"{fmt_int(asm['max_contig_bp'])} bp", f"GC: {fmt_float(asm['gc_pct'], 1)}%"),
        ('Known Viral Hits', fmt_int(len(s['viral_hits'])), f"Mapped: {fmt_pct(s['contig_mapping_pct'])}"),
        ('Novel Candidates', fmt_int(len(prom)), f"{len(s['novel_rows'])} screened"),
    ]

    sections = [{
        'id': 'sample-qc',
        'title': f'1. Sample {sid}: Assembly & Read Coverage Overview',
        'intro': 'Contig assembly metrics and whole-contig read depth/breadth profiles.',
        'figure': sample_figs.get('coverage'),
        'fig_alt': f'Top contigs by mean read depth and coverage breadth for sample {sid}.',
        'tables': [{
            'id': f'tbl-{sid}-qc',
            'caption': f'Assembly and alignment statistics for {sid}',
            'headers': [
                ('Metric', 'text'), ('Value', 'text')
            ],
            'rows': [
                [('Total Assembled Contigs', 'Total Assembled Contigs'), (fmt_int(asm['total_contigs']), asm['total_contigs'])],
                [('Contigs >= 1,000 bp', 'Contigs >= 1,000 bp'), (fmt_int(asm['contigs_ge_1kb']), asm['contigs_ge_1kb'])],
                [('Largest Contig (bp)', 'Largest Contig (bp)'), (fmt_int(asm['max_contig_bp']), asm['max_contig_bp'])],
                [('Total Assembly Length (bp)', 'Total Assembly Length (bp)'), (fmt_int(asm['total_bp']), asm['total_bp'])],
                [('Assembly N50 (bp)', 'Assembly N50 (bp)'), (fmt_int(asm['n50_bp']), asm['n50_bp'])],
                [('Assembly GC (%)', 'Assembly GC (%)'), (fmt_pct(asm['gc_pct']), asm['gc_pct'])],
                [('Host Reads Depleted (%)', 'Host Reads Depleted (%)'), (fmt_pct(s['host_depleted_pct']) if s['host_depleted_pct'] is not None else 'Not enabled', 0)],
                [('Reads Mapped to Contigs (%)', 'Reads Mapped to Contigs (%)'), (fmt_pct(s['contig_mapping_pct']), 0)],
            ],
            'col_weights': [2.5, 2.0],
        }],
    }]

    if s['viral_hits']:
        rows = []
        for h in s['viral_hits'][:50]:
            fam = h.get('family', '').strip() or 'Unclassified'
            sp = h.get('species', '').strip() or h.get('subject_title', '')[:70]
            rows.append([
                (h['query_id'], h['query_id']),
                (fmt_int(h.get('query_length')), safe_int(h.get('query_length'))),
                (fmt_int(h.get('alignment_length')), safe_int(h.get('alignment_length'))),
                (fmt_float(h.get('percent_identity'), 1), safe_float(h.get('percent_identity'))),
                (fmt_float(h.get('query_union_coverage'), 1), safe_float(h.get('query_union_coverage'))),
                (fmt_float(h.get('mean_depth'), 1), safe_float(h.get('mean_depth'))),
                (fmt_float(h.get('breadth_pct'), 1), safe_float(h.get('breadth_pct'))),
                (fam, fam),
                (sp, sp),
            ])
        sections.append({
            'id': 'sample-blast',
            'title': '2. Known Viral Contigs (Sorted Descending by Alignment Length)',
            'intro': f"Detected {len(s['viral_hits'])} viral contigs in sample {sid}.",
            'figure': None,
            'fig_alt': '',
            'tables': [{
                'id': f'tbl-{sid}-blast',
                'caption': f'Known viral contigs in {sid}',
                'headers': [
                    ('Contig ID', 'text'), ('Length (bp)', 'number'), ('Align (bp/aa)', 'number'),
                    ('Identity (%)', 'number'), ('Union Cov (%)', 'number'), ('Depth (x)', 'number'),
                    ('Breadth (%)', 'number'), ('Viral Family', 'text'), ('Species / Closest Hit', 'text'),
                ],
                'rows': rows,
                'col_weights': [1.6, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 1.2, 2.2],
            }],
        })

    if s['novel_rows']:
        nv_rows = []
        for r in s['novel_rows'][:50]:
            cls_s = r.get('discovery_classification', '').replace('putative_novel_virus_', 'novel_')
            nv_rows.append([
                (r['query_id'], r['query_id']),
                (fmt_int(r.get('contig_length')), safe_int(r.get('contig_length'))),
                (cls_s, cls_s),
                (fmt_float(r.get('discovery_score'), 1), safe_float(r.get('discovery_score'))),
                (r.get('putative_order') or '-', r.get('putative_order') or ''),
                (r.get('putative_family') or '-', r.get('putative_family') or ''),
                (r.get('hallmark_category') or '-', r.get('hallmark_category') or ''),
                (fmt_float(r.get('coding_density'), 1), safe_float(r.get('coding_density'))),
                (fmt_float(r.get('virfinder_score'), 2) if r.get('virfinder_score') != '' else '-', safe_float(r.get('virfinder_score'), -1)),
            ])
        sections.append({
            'id': 'sample-novel',
            'title': '3. Putative Novel & Divergent Virus Candidates',
            'intro': f"Evaluated {len(s['novel_rows'])} unassigned/divergent contigs in {sid}; {len(prom)} promoted as putative novel viral candidates.",
            'figure': None,
            'fig_alt': '',
            'tables': [{
                'id': f'tbl-{sid}-novel',
                'caption': f'Novel virus candidate assessment for {sid}',
                'headers': [
                    ('Contig ID', 'text'), ('Len (bp)', 'number'), ('Classification', 'text'),
                    ('Score', 'number'), ('Putative Order', 'text'), ('Putative Family', 'text'),
                    ('Hallmark', 'text'), ('Coding (%)', 'number'), ('VirFinder Score', 'number'),
                ],
                'rows': nv_rows,
                'col_weights': [1.6, 0.8, 1.6, 0.7, 1.2, 1.2, 0.9, 0.8, 0.9],
            }],
        })

    return {
        'report_title': f'Sample Viral Report: {sid}',
        'subtitle': f"MetaNextViro Single-Sample Diagnostic & Discovery Summary",
        'timestamp': timestamp_str,
        'run_meta': meta,
        'kpis': kpis,
        'sections': sections,
        'methods': build_methods_paragraph(data),
        'caveats': CAVEATS_TEXT,
        'sample_links': [],
    }


def _render_pdf_reportlab(spec, pdf_path, logo_path=None):
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import inch
    from reportlab.pdfgen import canvas as rl_canvas
    from reportlab.platypus import (
        Image as RLImage,
        KeepTogether,
        Paragraph,
        SimpleDocTemplate,
        Spacer,
        Table,
        TableStyle,
    )

    class NumberedCanvas(rl_canvas.Canvas):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._saved_page_states = []

        def showPage(self):
            self._saved_page_states.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            total_pages = len(self._saved_page_states)
            for state in self._saved_page_states:
                self.__dict__.update(state)
                self._draw_header_footer(total_pages)
                super().showPage()
            super().save()

        def _draw_header_footer(self, total_pages):
            w, h = letter
            self.saveState()
            if self._pageNumber > 1:
                self.setStrokeColor(colors.HexColor('#CBD5E1'))
                self.setLineWidth(0.5)
                self.line(0.55 * inch, h - 0.48 * inch, w - 0.55 * inch, h - 0.48 * inch)
                self.setFont('Helvetica-Bold', 8)
                self.setFillColor(colors.HexColor('#1E293B'))
                self.drawString(0.55 * inch, h - 0.40 * inch, spec['report_title'])
                self.setFont('Helvetica', 8)
                self.setFillColor(colors.HexColor('#64748B'))
                self.drawRightString(w - 0.55 * inch, h - 0.40 * inch, f"MetaNextViro v{spec['run_meta'].get('version', '0.2.0')}")

            self.setStrokeColor(colors.HexColor('#CBD5E1'))
            self.setLineWidth(0.5)
            self.line(0.55 * inch, 0.48 * inch, w - 0.55 * inch, 0.48 * inch)
            self.setFont('Helvetica', 7.5)
            self.setFillColor(colors.HexColor('#64748B'))
            self.drawString(0.55 * inch, 0.32 * inch, f"Generated: {spec['timestamp']}")
            self.drawRightString(w - 0.55 * inch, 0.32 * inch, f'Page {self._pageNumber} of {total_pages}')
            self.restoreState()

    doc = SimpleDocTemplate(
        str(pdf_path),
        pagesize=letter,
        leftMargin=0.55 * inch,
        rightMargin=0.55 * inch,
        topMargin=0.62 * inch,
        bottomMargin=0.62 * inch,
        title=spec['report_title'],
        author='MetaNextViro Pipeline',
    )
    usable_w = letter[0] - 1.10 * inch
    styles = getSampleStyleSheet()

    st_banner_title = ParagraphStyle('BannerTitle', parent=styles['Normal'], fontName='Helvetica-Bold',
                                     fontSize=16, leading=20, textColor=colors.white)
    st_banner_sub = ParagraphStyle('BannerSub', parent=styles['Normal'], fontName='Helvetica',
                                   fontSize=9.5, leading=13, textColor=colors.HexColor('#E2E8F0'))
    st_h2 = ParagraphStyle('SecH2', parent=styles['Normal'], fontName='Helvetica-Bold',
                           fontSize=11.5, leading=15, textColor=colors.HexColor('#0F1E2E'),
                           spaceBefore=12, spaceAfter=4)
    st_body = ParagraphStyle('BodyTxt', parent=styles['Normal'], fontName='Helvetica',
                             fontSize=8.5, leading=12, textColor=colors.HexColor('#334155'), spaceAfter=6)
    st_cap = ParagraphStyle('TblCap', parent=styles['Normal'], fontName='Helvetica-Bold',
                            fontSize=8.2, leading=11, textColor=colors.HexColor('#1E293B'), spaceAfter=3)
    st_th = ParagraphStyle('TblTH', parent=styles['Normal'], fontName='Helvetica-Bold',
                           fontSize=7.2, leading=9.2, textColor=colors.white)
    st_td = ParagraphStyle('TblTD', parent=styles['Normal'], fontName='Helvetica',
                           fontSize=7.0, leading=9.0, textColor=colors.HexColor('#0F172A'),
                           wordWrap='CJK')
    st_kpi_val = ParagraphStyle('KpiVal', parent=styles['Normal'], fontName='Helvetica-Bold',
                                fontSize=14, leading=17, textColor=colors.HexColor('#0072B2'))
    st_kpi_lbl = ParagraphStyle('KpiLbl', parent=styles['Normal'], fontName='Helvetica-Bold',
                                fontSize=7.8, leading=10, textColor=colors.HexColor('#1E293B'))
    st_kpi_sub = ParagraphStyle('KpiSub', parent=styles['Normal'], fontName='Helvetica',
                                fontSize=7.0, leading=9, textColor=colors.HexColor('#64748B'))

    story = []

    # Cover Header Banner
    banner_left = [
        Paragraph(xml_escape(spec['report_title']), st_banner_title),
        Spacer(1, 3),
        Paragraph(xml_escape(spec['subtitle']), st_banner_sub),
        Spacer(1, 4),
        Paragraph(
            xml_escape(
                f"Run: {spec['run_meta'].get('run_name', 'local')}  |  "
                f"Assembler: {spec['run_meta'].get('assembler', 'megahit')}  |  "
                f"BLAST: {spec['run_meta'].get('blast_options', 'viruses')}  |  "
                f"Date: {spec['timestamp']}"
            ),
            st_banner_sub,
        ),
    ]
    if _is_valid_image(logo_path):
        logo_img = RLImage(str(logo_path), width=0.72 * inch, height=0.72 * inch)
        banner_tbl = Table([[banner_left, logo_img]], colWidths=[usable_w - 0.92 * inch, 0.92 * inch])
    else:
        banner_tbl = Table([[banner_left]], colWidths=[usable_w])
    banner_tbl.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#0F1E2E')),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 12),
        ('RIGHTPADDING', (0, 0), (-1, -1), 12),
        ('TOPPADDING', (0, 0), (-1, -1), 10),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
    ]))
    story.append(banner_tbl)
    story.append(Spacer(1, 8))

    # KPI Cards Row
    kpi_cells = [[
        Paragraph(xml_escape(lbl), st_kpi_lbl),
        Paragraph(xml_escape(val), st_kpi_val),
        Paragraph(xml_escape(sub), st_kpi_sub),
    ] for lbl, val, sub in spec['kpis']]
    kpi_w = usable_w / max(1, len(kpi_cells))
    kpi_tbl = Table([kpi_cells], colWidths=[kpi_w] * len(kpi_cells))
    kpi_tbl.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#F8FAFC')),
        ('BOX', (0, 0), (-1, -1), 0.6, colors.HexColor('#CBD5E1')),
        ('INNERGRID', (0, 0), (-1, -1), 0.6, colors.HexColor('#CBD5E1')),
        ('TOPPADDING', (0, 0), (-1, -1), 7),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ]))
    story.append(kpi_tbl)
    story.append(Spacer(1, 6))

    # Content Sections
    for sec in spec['sections']:
        story.append(Paragraph(xml_escape(sec['title']), st_h2))
        story.append(Paragraph(xml_escape(sec['intro']), st_body))

        if sec.get('figure'):
            png_path = sec['figure'][0]
            if os.path.isfile(png_path):
                from PIL import Image as PILImage
                with PILImage.open(png_path) as im:
                    iw, ih = im.size
                disp_w = usable_w
                disp_h = disp_w * (ih / max(1, iw))
                story.append(RLImage(png_path, width=disp_w, height=disp_h))
                story.append(Spacer(1, 6))

        for tbl_spec in sec.get('tables', []):
            story.append(Paragraph(xml_escape(tbl_spec['caption']), st_cap))
            weights = tbl_spec['col_weights']
            tot_w = sum(weights)
            col_widths = [usable_w * (w / tot_w) for w in weights]

            header_row = [Paragraph(xml_escape(h[0]), st_th) for h in tbl_spec['headers']]
            data_rows = [
                [Paragraph(xml_escape(str(cell[0])), st_td) for cell in r]
                for r in tbl_spec['rows']
            ]
            rl_tbl = Table([header_row] + data_rows, colWidths=col_widths, repeatRows=1)
            t_style = [
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1F4E78')),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('LEFTPADDING', (0, 0), (-1, -1), 4),
                ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                ('TOPPADDING', (0, 0), (-1, -1), 3.5),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 3.5),
                ('LINEBELOW', (0, 0), (-1, -1), 0.35, colors.HexColor('#E2E8F0')),
                ('BOX', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
            ]
            for r_idx in range(1, len(data_rows) + 1):
                if r_idx % 2 == 0:
                    t_style.append(('BACKGROUND', (0, r_idx), (-1, r_idx), colors.HexColor('#F8FAFC')))
            rl_tbl.setStyle(TableStyle(t_style))
            story.append(rl_tbl)
            story.append(Spacer(1, 8))

    # Methods & Guardrails Footer Section
    story.append(KeepTogether([
        Paragraph('Methods & Reproducibility Summary', st_h2),
        Paragraph(xml_escape(spec['methods']), st_body),
        Paragraph(xml_escape(spec['caveats']), ParagraphStyle(
            'CaveatBox', parent=st_body, backColor=colors.HexColor('#FFFBEB'),
            borderColor=colors.HexColor('#F59E0B'), borderWidth=0.6, borderPadding=6,
            textColor=colors.HexColor('#78350F'),
        )),
    ]))

    doc.build(story, canvasmaker=NumberedCanvas)


def _render_pdf_matplotlib_fallback(spec, pdf_path, logo_path=None):
    """Publication-styled vector multi-page PDF via Matplotlib PdfPages when reportlab is absent."""
    pages_plan = [('cover', None, None)]
    for sec in spec['sections']:
        tbls = sec.get('tables', [])
        if len(tbls) <= 1:
            pages_plan.append(('section', sec, tbls))
        else:
            pages_plan.append(('section', sec, tbls[:1]))
            for extra_tbl in tbls[1:]:
                pages_plan.append(('extra_table', sec, [extra_tbl]))
    total_pages = len(pages_plan)

    def _draw_running_chrome(fig, page_num):
        chrome_ax = fig.add_axes([0, 0, 1, 1], zorder=0)
        chrome_ax.set_xlim(0, 1)
        chrome_ax.set_ylim(0, 1)
        chrome_ax.axis('off')
        if page_num > 1:
            chrome_ax.plot([0.06, 0.94], [0.952, 0.952], color='#CBD5E1', linewidth=0.7)
            chrome_ax.text(0.06, 0.960, spec['report_title'], fontsize=8, fontweight='bold', color='#1E293B')
            chrome_ax.text(0.94, 0.960, f"MetaNextViro v{spec['run_meta'].get('version', '0.2.0')}",
                           fontsize=8, color='#64748B', ha='right')
        chrome_ax.plot([0.06, 0.94], [0.048, 0.048], color='#CBD5E1', linewidth=0.7)
        chrome_ax.text(0.06, 0.030, f"Generated: {spec['timestamp']}", fontsize=7.5, color='#64748B')
        chrome_ax.text(0.94, 0.030, f'Page {page_num} of {total_pages}', fontsize=7.5, color='#64748B', ha='right')
        return chrome_ax

    def _draw_styled_mpl_table(fig, box, tbl_spec, max_rows=20):
        rows_slice = tbl_spec['rows'][:max_rows]
        if not rows_slice:
            return
        t_ax = fig.add_axes(box)
        t_ax.axis('off')
        t_ax.set_title(tbl_spec['caption'], loc='left', fontsize=8.4, fontweight='bold', color='#1E293B', pad=8)
        weights = tbl_spec['col_weights']
        tot_w = sum(weights)
        col_widths = [w / tot_w for w in weights]
        ncols = len(col_widths)
        body_fs = 6.3 if ncols >= 9 else 6.8
        hdr_fs = 6.3 if ncols >= 9 else 6.8
        char_scale = 104 if ncols >= 9 else 94
        hdr_max_chars = [max(7, int(char_scale * cw)) for cw in col_widths]
        col_labels = [
            textwrap.fill(h[0], width=hmc, break_long_words=False, break_on_hyphens=False)
            for h, hmc in zip(tbl_spec['headers'], hdr_max_chars)
        ]
        max_hdr_lines = max((lbl.count('\n') + 1 for lbl in col_labels), default=1)
        max_chars = [max(7, int(char_scale * cw)) for cw in col_widths]
        cell_text = [
            [
                (str(c[0])[:mc - 1] + '…') if len(str(c[0])) > mc else str(c[0])
                for c, mc in zip(r, max_chars)
            ]
            for r in rows_slice
        ]
        mpl_tbl = t_ax.table(
            cellText=cell_text,
            colLabels=col_labels,
            colWidths=col_widths,
            loc='upper center',
            cellLoc='left',
            colLoc='left',
        )
        mpl_tbl.auto_set_font_size(False)
        mpl_tbl.set_fontsize(body_fs)
        mpl_tbl.scale(1.0, 1.30)
        for (row_i, col_i), cell in mpl_tbl.get_celld().items():
            cell.set_edgecolor('#CBD5E1')
            cell.set_linewidth(0.45)
            cell.PAD = 0.04
            if row_i == 0:
                cell.set_facecolor('#1F4E78')
                cell.get_text().set_color('#FFFFFF')
                cell.get_text().set_weight('bold')
                cell.set_fontsize(hdr_fs)
                if max_hdr_lines > 1:
                    cell.set_height(cell.get_height() * (1.0 + 0.58 * (max_hdr_lines - 1)))
            else:
                cell.set_facecolor('#F8FAFC' if row_i % 2 == 0 else '#FFFFFF')
                cell.get_text().set_color('#0F172A')

    with PdfPages(pdf_path) as pdf:
        for page_num, (kind, sec, tbl_list) in enumerate(pages_plan, 1):
            fig = plt.figure(figsize=(8.5, 11.0), facecolor='#FFFFFF')
            ax = _draw_running_chrome(fig, page_num)

            if kind == 'cover':
                ax.add_patch(plt.Rectangle((0.06, 0.845), 0.88, 0.105, facecolor='#0F1E2E', edgecolor='none'))
                ax.add_patch(plt.Rectangle((0.06, 0.845), 0.88, 0.006, facecolor='#0072B2', edgecolor='none'))
                ax.text(0.08, 0.918, spec['report_title'], color='white', fontsize=15.5, fontweight='bold')
                ax.text(0.08, 0.888, spec['subtitle'], color='#E2E8F0', fontsize=9.5)
                ax.text(
                    0.08, 0.864,
                    f"Run: {spec['run_meta'].get('run_name', 'local')}  |  "
                    f"Assembler: {spec['run_meta'].get('assembler', 'megahit')}  |  "
                    f"BLAST: {spec['run_meta'].get('blast_options', 'viruses')}  |  "
                    f"Date: {spec['timestamp']}",
                    color='#94A3B8', fontsize=7.8,
                )
                if _is_valid_image(logo_path):
                    logo_im = plt.imread(logo_path)
                    lax = fig.add_axes([0.845, 0.858, 0.078, 0.078])
                    lax.imshow(logo_im)
                    lax.axis('off')

                n_kpi = max(1, len(spec['kpis']))
                gap = 0.014
                kw = (0.88 - gap * (n_kpi - 1)) / n_kpi
                for idx, (lbl, val, sub) in enumerate(spec['kpis']):
                    x0 = 0.06 + idx * (kw + gap)
                    ax.add_patch(plt.Rectangle((x0, 0.742), kw, 0.082, facecolor='#F8FAFC', edgecolor='#CBD5E1', linewidth=0.7))
                    ax.add_patch(plt.Rectangle((x0, 0.742), 0.006, 0.082, facecolor='#0072B2', edgecolor='none'))
                    ax.text(x0 + 0.015, 0.804, lbl.upper(), fontsize=7.2, fontweight='bold', color='#475569')
                    ax.text(x0 + 0.015, 0.773, val, fontsize=14, fontweight='bold', color='#0F1E2E')
                    ax.text(x0 + 0.015, 0.752, sub, fontsize=7.2, color='#64748B')

                # Table of Contents / Report Roadmap on Page 1
                ax.text(0.06, 0.704, 'Report Sections Overview', fontsize=11, fontweight='bold', color='#0F1E2E')
                ax.plot([0.06, 0.94], [0.696, 0.696], color='#E2E8F0', linewidth=0.8)
                y_toc = 0.674
                for s_item in spec['sections']:
                    ax.text(0.075, y_toc, f"•  {s_item['title']}", fontsize=8.8, fontweight='bold', color='#1E293B')
                    wrapped_intro = textwrap.fill(s_item['intro'], width=106)
                    ax.text(0.095, y_toc - 0.017, wrapped_intro, fontsize=7.8, color='#475569', va='top')
                    y_toc -= 0.056

                y_meth = min(y_toc - 0.015, 0.41)
                ax.text(0.06, y_meth, 'Methods & Reproducibility Summary', fontsize=11, fontweight='bold', color='#0F1E2E')
                ax.plot([0.06, 0.94], [y_meth - 0.008, y_meth - 0.008], color='#E2E8F0', linewidth=0.8)
                wrapped_methods = textwrap.fill(spec['methods'], width=108)
                ax.text(0.06, y_meth - 0.022, wrapped_methods, fontsize=8.1, color='#334155', va='top', linespacing=1.38)

                wrapped_caveats = textwrap.fill(spec['caveats'], width=104)
                ax.add_patch(plt.Rectangle((0.06, 0.072), 0.88, 0.098, facecolor='#FFFBEB', edgecolor='#F59E0B', linewidth=0.8))
                ax.text(0.075, 0.156, wrapped_caveats, fontsize=7.7, color='#78350F', va='top', linespacing=1.35)

            elif kind == 'section':
                ax.text(0.06, 0.922, sec['title'], fontsize=12, fontweight='bold', color='#0F1E2E')
                ax.plot([0.06, 0.94], [0.913, 0.913], color='#CBD5E1', linewidth=0.8)
                ax.text(0.06, 0.900, textwrap.fill(sec['intro'], width=110),
                        fontsize=8.3, color='#475569', va='top', linespacing=1.3)

                top_y = 0.855
                if sec.get('figure') and os.path.isfile(sec['figure'][0]):
                    img = plt.imread(sec['figure'][0])
                    ih, iw = img.shape[:2]
                    fig_box_w = 0.88
                    # Preserve aspect ratio cleanly within 0.34 max vertical height
                    fig_box_h = min(0.34, fig_box_w * (8.5 / 11.0) * (ih / max(1, iw)))
                    im_ax = fig.add_axes([0.06, top_y - fig_box_h, fig_box_w, fig_box_h])
                    im_ax.imshow(img)
                    im_ax.axis('off')
                    top_y = top_y - fig_box_h - 0.032

                if tbl_list:
                    _draw_styled_mpl_table(fig, [0.06, 0.075, 0.88, max(0.18, top_y - 0.085)], tbl_list[0], max_rows=18)

            elif kind == 'extra_table':
                ax.text(0.06, 0.922, f"{sec['title']} (Continued)", fontsize=12, fontweight='bold', color='#0F1E2E')
                ax.plot([0.06, 0.94], [0.913, 0.913], color='#CBD5E1', linewidth=0.8)
                _draw_styled_mpl_table(fig, [0.06, 0.075, 0.88, 0.81], tbl_list[0], max_rows=28)

            pdf.savefig(fig)
            plt.close(fig)


def render_pdf(spec, pdf_path, logo_path=None, force_fallback=False):
    if not force_fallback:
        try:
            _render_pdf_reportlab(spec, pdf_path, logo_path=logo_path)
            return 'reportlab'
        except ImportError:
            pass
    _render_pdf_matplotlib_fallback(spec, pdf_path, logo_path=logo_path)
    return 'matplotlib'


def render_html(spec, html_path, logo_path=None):
    """Render standalone interactive scientific monograph HTML report."""
    logo_html = ''
    if _is_valid_image(logo_path):
        b64_logo = base64.b64encode(Path(logo_path).read_bytes()).decode('ascii')
        logo_html = f'<img src="data:image/png;base64,{b64_logo}" alt="MetaNextViro logo" class="brand-logo">'

    nav_links = ''.join(
        f'<a href="#{html.escape(sec["id"])}" class="nav-pill">{html.escape(sec["title"].split(".", 1)[-1].strip())}</a>'
        for sec in spec['sections']
    )

    sample_cards_html = ''
    if spec.get('sample_links'):
        pills = ''.join(
            f'<span class="sample-chip"><strong>{html.escape(item["sample_id"])}</strong>: '
            f'<a href="{html.escape(item["html"])}">HTML</a> &middot; '
            f'<a href="{html.escape(item["pdf"])}">PDF</a></span>'
            for item in spec['sample_links']
        )
        sample_cards_html = f'<section class="sample-bar" aria-label="Per-sample reports"><span class="sample-bar-label">Sample-Wise Reports:</span>{pills}</section>'

    kpi_html = ''.join(
        f'<article class="kpi-card"><span class="kpi-label">{html.escape(lbl)}</span>'
        f'<strong class="kpi-value">{html.escape(val)}</strong>'
        f'<span class="kpi-sub">{html.escape(sub)}</span></article>'
        for lbl, val, sub in spec['kpis']
    )

    sort_icon_svg = (
        '<svg class="sort-icon" aria-hidden="true" viewBox="0 0 12 14" width="11" height="13">'
        '<path class="arrow-up" d="M6 1L10 5H2L6 1Z" fill="currentColor"/>'
        '<path class="arrow-down" d="M6 13L2 9H10L6 13Z" fill="currentColor"/>'
        '</svg>'
    )

    sections_html = []
    for sec in spec['sections']:
        fig_block = ''
        if sec.get('figure'):
            fig_block = (
                f'<figure class="report-figure">'
                f'<img src="{sec["figure"][1]}" alt="{html.escape(sec["fig_alt"])}">'
                f'</figure>'
            )

        tables_block = []
        for tbl in sec.get('tables', []):
            tid = html.escape(tbl['id'])
            cap_id = f'{tid}-caption'
            css_vars = '; '.join(
                f'--label-{idx}: "{html.escape(h[0])}"'
                for idx, h in enumerate(tbl['headers'], 1)
            )
            stacked_rules = '\n'.join(
                f'#{tid} td:nth-child({idx})::before {{ content: var(--label-{idx}) ": "; font-weight: 600; color: #475569; }}'
                for idx in range(2, len(tbl['headers']) + 1)
            )
            th_cells = ''.join(
                f'<th scope="col" data-type="{html.escape(h_type)}">'
                f'<button type="button" commandfor="{tid}" command="--sort">'
                f'<span>{html.escape(h_lbl)}</span>{sort_icon_svg}</button></th>'
                for h_lbl, h_type in tbl['headers']
            )
            body_rows = []
            for r in tbl['rows']:
                first_disp, first_val = r[0]
                row_cells = [f'<th scope="row" data-value="{html.escape(str(first_val))}">{html.escape(str(first_disp))}</th>']
                for (disp, raw), (_, h_type) in zip(r[1:], tbl['headers'][1:]):
                    cls_num = ' class="num"' if h_type == 'number' else ''
                    row_cells.append(f'<td{cls_num} data-value="{html.escape(str(raw))}">{html.escape(str(disp))}</td>')
                body_rows.append(f'<tr>{"".join(row_cells)}</tr>')

            filter_bar = ''
            if len(tbl['rows']) > 5:
                filter_bar = (
                    f'<div class="table-controls">'
                    f'<label for="filter-{tid}" class="sr-only">Filter {html.escape(tbl["caption"])}</label>'
                    f'<input id="filter-{tid}" type="search" class="table-filter" data-target="{tid}" '
                    f'placeholder="Filter rows in this table...">'
                    f'</div>'
                )

            tables_block.append(
                f'<style>@container (width < 640px) {{ {stacked_rules} }}</style>'
                f'{filter_bar}'
                f'<div tabindex="0" role="region" aria-labelledby="{cap_id}" class="table-wrapper">'
                f'<table id="{tid}" class="sortable-data-table" style="{css_vars}">'
                f'<caption id="{cap_id}">{html.escape(tbl["caption"])}</caption>'
                f'<thead><tr>{th_cells}</tr></thead>'
                f'<tbody>{"".join(body_rows)}</tbody>'
                f'</table></div>'
            )

        sections_html.append(
            f'<section id="{html.escape(sec["id"])}" class="report-section">'
            f'<h2>{html.escape(sec["title"])}</h2>'
            f'<p class="section-intro">{html.escape(sec["intro"])}</p>'
            f'{fig_block}'
            f'{"".join(tables_block)}'
            f'</section>'
        )

    doc_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(spec['report_title'])}</title>
<style>
  :root {{
    --paper: #FAF9F5;
    --surface: #FFFFFF;
    --ink: #111927;
    --muted: #4B5563;
    --navy: #0F1E2E;
    --cobalt: #0072B2;
    --vermilion: #D55E00;
    --rule: #D6D3C9;
    --tint: #F3F2EC;
    --font-display: 'Iowan Old Style', 'Palatino Linotype', 'Book Antiqua', Georgia, serif;
    --font-sans: 'Avenir Next', 'Segoe UI', 'Helvetica Neue', sans-serif;
    --font-mono: 'SF Mono', 'JetBrains Mono', 'Menlo', Consolas, monospace;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--paper);
    color: var(--ink);
    font-family: var(--font-sans);
    line-height: 1.55;
    font-size: 0.95rem;
  }}
  .sr-only {{
    position: absolute;
    inline-size: 1px;
    block-size: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }}
  .masthead {{
    background: linear-gradient(135deg, #0B1622 0%, #162B42 100%);
    color: #F8FAFC;
    border-block-end: 4px solid var(--cobalt);
    padding: 2.2rem 1.5rem 1.8rem;
  }}
  .masthead-inner, .container {{
    max-inline-size: 1220px;
    margin-inline: auto;
  }}
  .masthead-top {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1.5rem;
  }}
  .brand-logo {{
    inline-size: 68px;
    block-size: 68px;
    object-fit: contain;
    border-radius: 10px;
    background: rgb(255 255 255 / 0.08);
    padding: 6px;
  }}
  h1 {{
    font-family: var(--font-display);
    font-size: clamp(1.55rem, 2.6vw, 2.25rem);
    font-weight: 700;
    letter-spacing: -0.015em;
    margin: 0 0 0.35rem;
  }}
  .subtitle {{
    margin: 0 0 0.75rem;
    color: #CBD5E1;
    font-size: 1.02rem;
  }}
  .meta-strip {{
    font-family: var(--font-mono);
    font-size: 0.78rem;
    color: #94A3B8;
  }}
  .nav-bar {{
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-block-start: 1.25rem;
  }}
  .nav-pill {{
    color: #E2E8F0;
    text-decoration: none;
    font-size: 0.8rem;
    padding: 0.32rem 0.75rem;
    border: 1px solid rgb(255 255 255 / 0.2);
    border-radius: 999px;
    transition: background 0.15s ease;
  }}
  .nav-pill:hover, .nav-pill:focus-visible {{
    background: var(--cobalt);
    border-color: var(--cobalt);
    color: #FFFFFF;
  }}
  .container {{
    padding: 1.6rem 1.5rem 3.5rem;
  }}
  .sample-bar {{
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.55rem;
    background: var(--surface);
    border: 1px solid var(--rule);
    padding: 0.75rem 1rem;
    border-radius: 6px;
    margin-block-end: 1.4rem;
    font-size: 0.84rem;
  }}
  .sample-bar-label {{
    font-weight: 700;
    color: var(--navy);
  }}
  .sample-chip {{
    background: var(--tint);
    padding: 0.22rem 0.6rem;
    border-radius: 4px;
    border: 1px solid var(--rule);
  }}
  .sample-chip a {{
    color: var(--cobalt);
    font-weight: 600;
    text-decoration: none;
  }}
  .kpi-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
    gap: 1rem;
    margin-block-end: 2rem;
  }}
  .kpi-card {{
    background: var(--surface);
    border: 1px solid var(--rule);
    border-inline-start: 4px solid var(--cobalt);
    padding: 1rem 1.15rem;
    border-radius: 4px;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }}
  .kpi-label {{
    font-size: 0.76rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    font-weight: 700;
  }}
  .kpi-value {{
    font-family: var(--font-mono);
    font-size: 1.65rem;
    color: var(--navy);
    font-variant-numeric: tabular-nums;
  }}
  .kpi-sub {{
    font-size: 0.8rem;
    color: var(--muted);
  }}
  .report-section {{
    background: var(--surface);
    border: 1px solid var(--rule);
    border-radius: 6px;
    padding: 1.5rem;
    margin-block-end: 1.75rem;
  }}
  h2 {{
    font-family: var(--font-display);
    font-size: 1.32rem;
    color: var(--navy);
    margin: 0 0 0.4rem;
    padding-block-end: 0.45rem;
    border-block-end: 1px solid var(--rule);
  }}
  .section-intro {{
    color: var(--muted);
    margin: 0 0 1.1rem;
  }}
  .report-figure {{
    margin: 0 0 1.35rem;
    padding: 0.75rem;
    background: #FFFFFF;
    border: 1px solid #E5E7EB;
    border-radius: 4px;
  }}
  .report-figure img {{
    display: block;
    max-inline-size: 100%;
    block-size: auto;
    margin-inline: auto;
  }}
  .table-controls {{
    display: flex;
    justify-content: flex-end;
    margin-block-end: 0.5rem;
  }}
  .table-filter {{
    padding: 0.4rem 0.7rem;
    border: 1px solid var(--rule);
    border-radius: 4px;
    font-size: 0.85rem;
    min-inline-size: 240px;
  }}
  .table-wrapper {{
    overflow: auto;
    max-inline-size: 100%;
    max-block-size: min(540px, 78vh);
    container-type: inline-size;
    border: 1px solid var(--rule);
    border-radius: 4px;
    margin-block-end: 1.1rem;
  }}
  table.sortable-data-table {{
    inline-size: 100%;
    min-inline-size: 680px;
    border-collapse: separate;
    border-spacing: 0;
    font-size: 0.83rem;
  }}
  caption {{
    caption-side: top;
    text-align: start;
    padding: 0.6rem 0.75rem;
    font-weight: 700;
    color: var(--navy);
    background: var(--tint);
    border-block-end: 1px solid var(--rule);
  }}
  thead {{
    position: sticky;
    inset-block-start: 0;
    z-index: 2;
    background: var(--navy);
    color: #FFFFFF;
  }}
  th, td {{
    padding: 0.52rem 0.68rem;
    text-align: start;
    border-block-end: 1px solid #E5E7EB;
    white-space: nowrap;
  }}
  th:has(> button) {{
    padding: 0;
  }}
  thead th > button {{
    appearance: none;
    background: transparent;
    border: 0;
    color: inherit;
    font: inherit;
    font-weight: 700;
    inline-size: 100%;
    min-block-size: 34px;
    padding: 0.52rem 0.68rem;
    display: inline-flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.4rem;
    cursor: pointer;
  }}
  thead th > button:focus-visible {{
    outline: 2px solid #56B4E9;
    outline-offset: -2px;
  }}
  .sort-icon {{
    opacity: 0.45;
    flex: none;
  }}
  th[aria-sort="ascending"] .sort-icon,
  th[aria-sort="descending"] .sort-icon {{
    opacity: 1;
    color: #56B4E9;
  }}
  th[aria-sort="ascending"] .arrow-down,
  th[aria-sort="descending"] .arrow-up {{
    opacity: 0.2;
  }}
  tbody th {{
    position: sticky;
    inset-inline-start: 0;
    z-index: 1;
    background: #FFFFFF;
    font-family: var(--font-mono);
    font-size: 0.79rem;
    font-weight: 600;
    border-inline-end: 1px solid #E5E7EB;
  }}
  tbody tr:nth-child(even) td,
  tbody tr:nth-child(even) th {{
    background: #F9FAFB;
  }}
  td.num {{
    font-family: var(--font-mono);
    font-variant-numeric: tabular-nums;
    text-align: end;
  }}
  @container (width < 640px) {{
    table.sortable-data-table {{ min-inline-size: 0; }}
    table.sortable-data-table,
    table.sortable-data-table thead,
    table.sortable-data-table tbody,
    table.sortable-data-table tr,
    table.sortable-data-table th,
    table.sortable-data-table td {{
      display: block;
      white-space: normal;
      text-align: start;
    }}
    table.sortable-data-table thead {{ display: none; }}
    table.sortable-data-table tr {{
      margin-block-end: 1rem;
      border: 1px solid var(--rule);
    }}
    table.sortable-data-table tbody th {{
      position: sticky;
      inset-block-start: 0;
      background: var(--tint);
    }}
  }}
  .caveat-box {{
    background: #FFFBEB;
    border: 1px solid #F59E0B;
    color: #78350F;
    padding: 0.9rem 1.1rem;
    border-radius: 5px;
    font-size: 0.85rem;
    margin-block-top: 1rem;
  }}
  @media print {{
    body {{ background: #FFFFFF; }}
    .table-wrapper {{ max-block-size: none; overflow: visible; }}
    .table-controls, .nav-bar {{ display: none; }}
  }}
</style>
</head>
<body>
<div id="sort-status" role="status" class="sr-only"></div>
<header class="masthead">
  <div class="masthead-inner">
    <div class="masthead-top">
      <div>
        <h1>{html.escape(spec['report_title'])}</h1>
        <p class="subtitle">{html.escape(spec['subtitle'])}</p>
        <div class="meta-strip">
          MetaNextViro v{html.escape(str(spec['run_meta'].get('version', '0.2.0')))} &bull;
          Assembler: {html.escape(str(spec['run_meta'].get('assembler', 'megahit')))} &bull;
          BLAST: {html.escape(str(spec['run_meta'].get('blast_options', 'viruses')))} &bull;
          Generated: {html.escape(spec['timestamp'])}
        </div>
      </div>
      {logo_html}
    </div>
    <nav class="nav-bar" aria-label="Report sections">{nav_links}</nav>
  </div>
</header>
<main class="container">
  {sample_cards_html}
  <section class="kpi-grid" aria-label="Key metrics">{kpi_html}</section>
  {"".join(sections_html)}
  <section class="report-section" id="methods">
    <h2>Methods &amp; Scientific Guardrails</h2>
    <p>{html.escape(spec['methods'])}</p>
    <div class="caveat-box">{html.escape(spec['caveats'])}</div>
  </section>
</main>
<script>
(() => {{
  const collator = new Intl.Collator(undefined, {{ numeric: true, sensitivity: 'base' }});
  const statusEl = document.getElementById('sort-status');

  function reorderRows(tbody, orderedRows) {{
    for (const row of orderedRows) {{
      if (typeof tbody.moveBefore === 'function') {{
        tbody.moveBefore(row, null);
      }} else {{
        tbody.appendChild(row);
      }}
    }}
  }}

  function handleSort(table, sourceBtn) {{
    const th = sourceBtn.closest('th');
    if (!th || !table.tBodies[0]) return;
    const tbody = table.tBodies[0];
    const direction = th.getAttribute('aria-sort') === 'ascending' ? 'descending' : 'ascending';
    for (const header of table.tHead.rows[0].cells) {{
      header.removeAttribute('aria-sort');
    }}
    th.setAttribute('aria-sort', direction);

    const colIdx = th.cellIndex;
    const colType = th.dataset.type || 'text';
    const factor = direction === 'ascending' ? 1 : -1;
    const keyed = [...tbody.rows].map((row) => {{
      const raw = row.cells[colIdx]?.dataset.value ?? row.cells[colIdx]?.textContent.trim() ?? '';
      return {{ row, val: colType === 'number' ? Number(raw) : raw }};
    }});
    keyed.sort((a, b) => factor * (colType === 'number' ? (a.val - b.val) : collator.compare(String(a.val), String(b.val))));
    reorderRows(tbody, keyed.map((item) => item.row));
    if (statusEl) {{
      statusEl.textContent = `Sorted by ${{sourceBtn.textContent.trim()}}, ${{direction}}, ${{keyed.length}} rows`;
    }}
  }}

  const supportsInvoker = 'commandForElement' in HTMLButtonElement.prototype;
  for (const table of document.querySelectorAll('table.sortable-data-table')) {{
    table.addEventListener('command', (event) => {{
      if (event.command === '--sort') handleSort(table, event.source);
    }});
    if (!supportsInvoker) {{
      for (const btn of table.querySelectorAll('thead th > button[command="--sort"]')) {{
        btn.addEventListener('click', () => handleSort(table, btn));
      }}
    }}
  }}

  for (const input of document.querySelectorAll('input.table-filter')) {{
    input.addEventListener('input', () => {{
      const table = document.getElementById(input.dataset.target);
      if (!table || !table.tBodies[0]) return;
      const needle = input.value.trim().toLowerCase();
      for (const row of table.tBodies[0].rows) {{
        row.hidden = needle.length > 0 && !row.textContent.toLowerCase().includes(needle);
      }}
    }});
  }}
}})();
</script>
</body>
</html>
"""
    Path(html_path).write_text(doc_html, encoding='utf-8')


def generate_all_reports(sample_ids, input_dir, output_dir, logo_path=None,
                         run_meta=None, force_pdf_fallback=False):
    out_root = Path(output_dir)
    out_root.mkdir(parents=True, exist_ok=True)
    per_sample_dir = out_root / 'per_sample'
    per_sample_dir.mkdir(parents=True, exist_ok=True)

    run_meta = run_meta or {}
    timestamp_str = datetime.now().strftime('%Y-%m-%d %H:%M')
    data = collect_cohort_data(sample_ids, input_dir, run_meta)

    with tempfile.TemporaryDirectory(prefix='metanextviro-figs-') as fig_tmp:
        cohort_figs = render_cohort_figures(data, fig_tmp)
        cohort_spec = build_cohort_spec(data, cohort_figs, timestamp_str)

        pdf_backend = render_pdf(
            cohort_spec,
            out_root / 'MetaNextViro_Summary_Report.pdf',
            logo_path=logo_path,
            force_fallback=force_pdf_fallback,
        )
        render_html(
            cohort_spec,
            out_root / 'MetaNextViro_Summary_Report.html',
            logo_path=logo_path,
        )

        for sid in data['sample_ids']:
            s_figs = render_sample_figures(data['samples'][sid], fig_tmp)
            s_spec = build_sample_spec(sid, data, s_figs, timestamp_str)
            render_pdf(
                s_spec,
                per_sample_dir / f'{sid}_Viral_Report.pdf',
                logo_path=logo_path,
                force_fallback=force_pdf_fallback,
            )
            render_html(
                s_spec,
                per_sample_dir / f'{sid}_Viral_Report.html',
                logo_path=logo_path,
            )

    print(
        f"Generated Cohort report + {len(data['sample_ids'])} sample-wise PDF/HTML reports "
        f"in {out_root} (PDF engine: {pdf_backend})."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples', nargs='+', required=True, help='Sample IDs in the cohort')
    parser.add_argument('--input-dir', required=True, help='Directory holding staged upstream outputs')
    parser.add_argument('--output-dir', default='.', help='Output directory for final reports')
    parser.add_argument('--logo', help='Optional path to MetaNextViro logo.png')
    parser.add_argument('--run-meta', help='Optional JSON file recording run metadata and parameters')
    parser.add_argument('--force-pdf-fallback', action='store_true')
    args = parser.parse_args()

    meta = {}
    if args.run_meta and os.path.isfile(args.run_meta):
        meta = json.loads(Path(args.run_meta).read_text())

    generate_all_reports(
        args.samples, args.input_dir, args.output_dir,
        logo_path=args.logo, run_meta=meta,
        force_pdf_fallback=args.force_pdf_fallback,
    )


if __name__ == '__main__':
    main()
