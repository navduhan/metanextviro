#!/usr/bin/env python3
# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""Collects quality control, host depletion, assembly, BLAST, Kraken2, coverage, and discovery outputs across samples and builds summary tables, dynamic methods text, and Matplotlib figures for reporting."""

import base64
import csv
import math
import os
import re
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
from Bio import SeqIO  # noqa: E402

# Okabe-Ito colorblind-safe qualitative palette paired with distinct marker shapes
OKABE_ITO = ['#0072B2', '#D55E00', '#009E73', '#CC79A7', '#E69F00', '#56B4E9', '#333333']
MARKERS = ['o', 's', 'D', '^', 'v', 'P', 'X']


def safe_float(val, default=0.0):
    if val is None or str(val).strip() in ('', 'NA', 'NaN', 'nan', 'None'):
        return default
    try:
        return float(val)
    except ValueError:
        return default


def safe_int(val, default=0):
    return int(safe_float(val, default))


def style_axes(ax, outward=6):
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.spines['left'].set_position(('outward', outward))
    ax.spines['bottom'].set_position(('outward', outward))
    ax.spines['left'].set_color('#334155')
    ax.spines['bottom'].set_color('#334155')
    ax.tick_params(axis='both', colors='#1E293B', labelsize=8.5, pad=3)
    ax.grid(axis='y', linestyle=':', alpha=0.35, color='#94A3B8')
    ax.set_axisbelow(True)


def compute_fasta_assembly_stats(fasta_path):
    lengths = []
    gc_bases = 0
    valid_bases = 0
    if fasta_path and os.path.exists(fasta_path) and os.path.getsize(fasta_path) > 0:
        with open(fasta_path) as handle:
            for rec in SeqIO.parse(handle, 'fasta'):
                seq_u = str(rec.seq).upper()
                ln = len(seq_u)
                if ln > 0:
                    lengths.append(ln)
                    n_cnt = seq_u.count('N')
                    gc_bases += seq_u.count('G') + seq_u.count('C')
                    valid_bases += max(0, ln - n_cnt)
    if not lengths:
        return {
            'total_contigs': 0, 'contigs_ge_1kb': 0, 'max_contig_bp': 0,
            'total_bp': 0, 'n50_bp': 0, 'gc_pct': 0.0, 'lengths': []
        }
    lengths.sort(reverse=True)
    total_bp = sum(lengths)
    half = total_bp / 2.0
    running = 0
    n50 = lengths[-1]
    for ln in lengths:
        running += ln
        if running >= half:
            n50 = ln
            break
    return {
        'total_contigs': len(lengths),
        'contigs_ge_1kb': sum(1 for ln in lengths if ln >= 1000),
        'max_contig_bp': lengths[0],
        'total_bp': total_bp,
        'n50_bp': n50,
        'gc_pct': round(100.0 * gc_bases / max(1, valid_bases), 2),
        'lengths': lengths,
    }


def parse_bowtie2_rate(log_path):
    if not log_path or not os.path.exists(log_path):
        return None
    text = Path(log_path).read_text(errors='replace')
    match = re.search(r'([0-9]+(?:\.[0-9]+)?)%\s+overall alignment rate', text)
    return round(float(match.group(1)), 2) if match else None


def parse_quast_tsv(quast_tsv):
    stats = {}
    if not quast_tsv or not os.path.exists(quast_tsv):
        return stats
    with open(quast_tsv, newline='') as handle:
        for row in csv.reader(handle, delimiter='\t'):
            if len(row) >= 2:
                stats[row[0].strip()] = row[1].strip()
    return stats


def parse_kraken2_report(report_path):
    summary = {
        'unclassified_pct': 0.0, 'viruses_pct': 0.0, 'bacteria_pct': 0.0,
        'archaea_pct': 0.0, 'eukaryota_pct': 0.0, 'viral_families': []
    }
    if not report_path or not os.path.exists(report_path) or os.path.getsize(report_path) == 0:
        return None
    in_viruses = False
    virus_indent = 0
    with open(report_path) as handle:
        for line in handle:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 6:
                continue
            pct = safe_float(parts[0].strip())
            rank = parts[3].strip()
            taxid = safe_int(parts[4].strip(), -1)
            raw_name = parts[5]
            indent = len(raw_name) - len(raw_name.lstrip(' '))
            name = raw_name.strip()

            if rank == 'U' or taxid == 0:
                summary['unclassified_pct'] = pct
            elif taxid == 10239:
                summary['viruses_pct'] = pct
                in_viruses = True
                virus_indent = indent
                continue
            elif taxid == 2:
                summary['bacteria_pct'] = pct
                if in_viruses and indent <= virus_indent:
                    in_viruses = False
            elif taxid == 2157:
                summary['archaea_pct'] = pct
                if in_viruses and indent <= virus_indent:
                    in_viruses = False
            elif taxid == 2759:
                summary['eukaryota_pct'] = pct
                if in_viruses and indent <= virus_indent:
                    in_viruses = False
            elif in_viruses:
                if indent <= virus_indent:
                    in_viruses = False
                elif rank == 'F' and pct > 0:
                    summary['viral_families'].append((name, pct, safe_int(parts[1].strip())))

    summary['viral_families'].sort(key=lambda x: (-x[1], -x[2], x[0]))
    return summary


def match_sample_id(name_str, sorted_samples):
    """Match longest sample ID first with an underscore or dot boundary."""
    for sid in sorted_samples:
        patterns = (
            f'{sid}_', f'{sid}.', f'coverage_{sid}.', f'virfinder_{sid}_',
        )
        if any(name_str.startswith(p) for p in patterns) or name_str == sid:
            return sid
    return None


def collect_cohort_data(sample_ids, input_dir, run_meta):
    sorted_sids = sorted(set(sample_ids), key=lambda s: (-len(s), s))
    ordered_sids = sorted(set(sample_ids))

    files_by_sample = {sid: defaultdict(list) for sid in ordered_sids}
    root = Path(input_dir)
    if root.exists():
        discovered = []
        for dirpath, _dirnames, filenames in os.walk(root, followlinks=True):
            for fname in filenames:
                discovered.append(Path(dirpath) / fname)
        for path in sorted(discovered):
            fname = path.name
            parent_name = path.parent.name
            if fname == 'report.tsv' and parent_name.endswith('_quast'):
                sid = parent_name[:-6]
                if sid in files_by_sample:
                    files_by_sample[sid]['quast'].append(path)
                continue

            sid = match_sample_id(fname, sorted_sids)
            if not sid:
                continue
            if '_metanextviro_' in fname and fname.endswith('_contigs.fa'):
                files_by_sample[sid]['contigs'].append(path)
            elif fname.endswith('_host_depletion_stats.txt'):
                files_by_sample[sid]['host_log'].append(path)
            elif fname == f'coverage_{sid}.txt':
                files_by_sample[sid]['coverage'].append(path)
            elif fname == f'{sid}.mapping.log':
                files_by_sample[sid]['mapping_log'].append(path)
            elif fname == f'{sid}_kraken2_report.txt':
                files_by_sample[sid]['kraken'].append(path)
            elif '_best_hits_' in fname and fname.endswith('.tsv'):
                files_by_sample[sid]['blast_best'].append(path)
            elif fname == f'{sid}_triage_manifest.tsv':
                files_by_sample[sid]['triage'].append(path)
            elif fname == f'{sid}_novel_virus_candidates.tsv':
                files_by_sample[sid]['novel'].append(path)
            elif fname == f'virfinder_{sid}_full.txt':
                files_by_sample[sid]['virfinder'].append(path)

    samples_data = {}
    all_viral_hits = []
    all_novel_candidates = []
    family_matrix = defaultdict(lambda: defaultdict(lambda: {'count': 0, 'max_depth': 0.0}))

    for sid in ordered_sids:
        sfiles = files_by_sample[sid]
        contigs_fa = sfiles['contigs'][0] if sfiles['contigs'] else None
        asm = compute_fasta_assembly_stats(contigs_fa)
        if asm['total_contigs'] == 0 and sfiles['quast']:
            q = parse_quast_tsv(sfiles['quast'][0])
            asm['total_contigs'] = safe_int(q.get('# contigs (>= 0 bp)', q.get('# contigs', 0)))
            asm['contigs_ge_1kb'] = safe_int(q.get('# contigs (>= 1000 bp)', 0))
            asm['max_contig_bp'] = safe_int(q.get('Largest contig', 0))
            asm['total_bp'] = safe_int(q.get('Total length (>= 0 bp)', q.get('Total length', 0)))
            asm['n50_bp'] = safe_int(q.get('N50', 0))
            asm['gc_pct'] = safe_float(q.get('GC (%)', 0.0))

        host_pct = parse_bowtie2_rate(sfiles['host_log'][0]) if sfiles['host_log'] else None
        map_pct = parse_bowtie2_rate(sfiles['mapping_log'][0]) if sfiles['mapping_log'] else None

        cov_map = {}
        cov_rows = []
        if sfiles['coverage']:
            with open(sfiles['coverage'][0], newline='') as handle:
                for r in csv.DictReader(handle, delimiter='\t'):
                    cid = r.get('Contig', '').strip()
                    if cid:
                        entry = {
                            'contig': cid,
                            'depth': safe_float(r.get('Average_Coverage')),
                            'reads': safe_int(r.get('Total_Reads')),
                            'covered_bp': safe_int(r.get('Covered_Bases')),
                            'breadth': safe_float(r.get('Coverage_Breadth')),
                        }
                        cov_map[cid] = entry
                        cov_rows.append(entry)
            cov_rows.sort(key=lambda x: (-x['depth'], -x['breadth'], x['contig']))

        kraken = parse_kraken2_report(sfiles['kraken'][0]) if sfiles['kraken'] else None

        # Join BLAST best hits across databases (deduplicating per contig by highest bit_score for summary)
        best_by_contig = {}
        for bpath in sfiles['blast_best']:
            with open(bpath, newline='') as handle:
                for r in csv.DictReader(handle, delimiter='\t'):
                    qid = r['query_id']
                    bscore = safe_float(r.get('bit_score'))
                    # Prefer viral hit or higher bit_score
                    prev = best_by_contig.get(qid)
                    is_vir = r.get('superkingdom') == 'Viruses'
                    prev_vir = prev and prev.get('superkingdom') == 'Viruses'
                    if prev is None or (is_vir and not prev_vir) or (is_vir == prev_vir and bscore > safe_float(prev.get('bit_score'))):
                        best_by_contig[qid] = r

        viral_hits = []
        non_viral_count = 0
        for qid, hit in best_by_contig.items():
            cov = cov_map.get(qid, {})
            enriched = {
                **hit,
                'sample_id': sid,
                'mean_depth': cov.get('depth', 0.0),
                'breadth_pct': cov.get('breadth', 0.0),
                'mapped_reads': cov.get('reads', 0),
            }
            if hit.get('superkingdom') == 'Viruses':
                viral_hits.append(enriched)
                fam = hit.get('family', '').strip() or 'Unclassified_Viruses'
                family_matrix[fam][sid]['count'] += 1
                family_matrix[fam][sid]['max_depth'] = max(
                    family_matrix[fam][sid]['max_depth'], enriched['mean_depth']
                )
            else:
                non_viral_count += 1

        viral_hits.sort(key=lambda r: (
            -safe_int(r.get('alignment_length')),
            -safe_float(r.get('bit_score')),
            -safe_float(r.get('mean_depth')),
            r['query_id'],
        ))
        all_viral_hits.extend(viral_hits)

        triage_counts = {}
        if sfiles['triage']:
            with open(sfiles['triage'][0], newline='') as handle:
                for r in csv.DictReader(handle, delimiter='\t'):
                    cat = r.get('triage_category', 'unknown')
                    triage_counts[cat] = triage_counts.get(cat, 0) + 1

        novel_rows = []
        if sfiles['novel']:
            with open(sfiles['novel'][0], newline='') as handle:
                for r in csv.DictReader(handle, delimiter='\t'):
                    r_copy = {**r, 'sample_id': sid}
                    novel_rows.append(r_copy)
                    all_novel_candidates.append(r_copy)
        elif sfiles['virfinder']:
            tier_map = {
                'high_confidence': 'putative_novel_virus_high_confidence',
                'moderate_confidence': 'putative_novel_virus_moderate_confidence',
                'low_complexity_suspect': 'plasmid_or_low_complexity_artifact',
            }
            with open(sfiles['virfinder'][0], newline='') as handle:
                for r in csv.DictReader(handle, delimiter='\t'):
                    vf_cls = tier_map.get(r.get('confidence_tier', ''), 'unconfirmed_dark_matter')
                    r_copy = {
                        'sample_id': sid,
                        'query_id': r.get('name', ''),
                        'contig_length': r.get('length', '0'),
                        'discovery_classification': vf_cls,
                        'discovery_score': f"{safe_float(r.get('score')) * 100.0:.1f}",
                        'virfinder_score': r.get('score', ''),
                        'coding_density': '0.0',
                        'putative_order': '',
                        'putative_family': '',
                        'taxonomy_evidence_source': 'virfinder_kmer_only',
                        'hallmark_category': '',
                        'terminal_repeat_type': 'none',
                        'coverage_breadth_pct': str(cov_map.get(r.get('name', ''), {}).get('breadth', '')),
                    }
                    novel_rows.append(r_copy)
                    all_novel_candidates.append(r_copy)

        samples_data[sid] = {
            'sample_id': sid,
            'assembly': asm,
            'host_depleted_pct': host_pct,
            'contig_mapping_pct': map_pct,
            'coverage_rows': cov_rows,
            'kraken': kraken,
            'viral_hits': viral_hits,
            'non_viral_blast_count': non_viral_count,
            'triage_counts': triage_counts,
            'novel_rows': novel_rows,
        }

    all_viral_hits.sort(key=lambda r: (
        -safe_int(r.get('alignment_length')),
        -safe_float(r.get('bit_score')),
        -safe_float(r.get('mean_depth')),
        r['sample_id'],
        r['query_id'],
    ))

    tier_rank = {
        'putative_novel_virus_high_confidence': 1,
        'putative_novel_virus_moderate_confidence': 2,
        'possible_eve_or_provirus_needs_review': 3,
        'unconfirmed_dark_matter': 4,
        'plasmid_or_low_complexity_artifact': 5,
    }
    all_novel_candidates.sort(key=lambda r: (
        tier_rank.get(r.get('discovery_classification', ''), 99),
        -safe_float(r.get('discovery_score')),
        -safe_int(r.get('contig_length')),
        r['sample_id'],
        r['query_id'],
    ))

    promoted_novel = [
        r for r in all_novel_candidates
        if r.get('discovery_classification') in (
            'putative_novel_virus_high_confidence',
            'putative_novel_virus_moderate_confidence',
        )
    ]

    return {
        'sample_ids': ordered_sids,
        'samples': samples_data,
        'all_viral_hits': all_viral_hits,
        'all_novel_candidates': all_novel_candidates,
        'promoted_novel': promoted_novel,
        'family_matrix': dict(family_matrix),
        'run_meta': run_meta,
    }


def build_methods_paragraph(data):
    meta = data['run_meta']
    parts = [
        f"Sequencing reads across {len(data['sample_ids'])} sample(s) were processed with "
        f"MetaNextViro v{meta.get('version', '0.2.0')} (Nextflow {meta.get('nextflow_version', '')})."
    ]
    if not meta.get('skip_trimming'):
        parts.append(
            f"Adapter and quality trimming were performed using {meta.get('trimming_tool', 'trim_galore')} "
            f"(minimum Phred quality {meta.get('quality', '30')})."
        )
    if meta.get('deplete_host'):
        parts.append("Host-derived reads were subtracted prior to assembly with Bowtie2 (--very-sensitive) and SAMtools.")
    if not meta.get('skip_assembly'):
        parts.append(
            f"De novo metagenomic assembly was conducted with {meta.get('assembler', 'megahit')} "
            f"(minimum contig length {meta.get('min_contig_length', 200)} bp)."
        )
    if not meta.get('skip_taxonomic_profiling'):
        parts.append("Read-level taxonomic profiling was performed using Kraken2.")
    if not meta.get('skip_blast_annotation'):
        parts.append(
            f"Assembled contigs were annotated against {meta.get('blast_options', 'viruses')} "
            f"(up to {meta.get('blast_max_target_seqs', 50)} target subjects per contig), retaining all "
            "high-scoring segment pairs (HSPs), computing merged query union coverage, and resolving multi-taxid "
            "subjects by lowest common ancestor (LCA) in NCBI Taxonomy."
        )
    if not meta.get('skip_coverage_analysis'):
        parts.append(
            "Contig-level read depth and coverage breadth were quantified by mapping trimmed reads back to "
            "assembled contigs with Bowtie2 and computing single-pass per-base depth across full contig lengths via SAMtools."
        )
    if data['all_novel_candidates']:
        parts.append(
            f"For novel and divergent virus discovery, contigs already confidently classified by BLAST "
            f"(>= {meta.get('known_virus_identity', 80.0)}% identity and >= {meta.get('known_virus_coverage', 50.0)}% union coverage) "
            f"or shorter than {meta.get('novel_min_contig_length', 500)} bp were filtered out automatically. "
            "Candidate contigs were evaluated for 6-frame ORF coding density, terminal repeats (DTR/ITR), "
            "3-mer Shannon entropy low-complexity artifacts, Endogenous Viral Element (EVE) fragmentation warnings, "
            "and putative higher-rank ICTV taxonomy (Order/Family) via multi-ORF protein LCA and profile-HMM lineage mapping."
        )
    return ' '.join(parts)


def fig_to_png_and_b64(fig, out_path):
    fig.savefig(out_path, dpi=300, facecolor='#FFFFFF', edgecolor='none')
    plt.close(fig)
    b64 = base64.b64encode(Path(out_path).read_bytes()).decode('ascii')
    return str(out_path), f'data:image/png;base64,{b64}'


def render_cohort_figures(data, fig_dir):
    fig_dir = Path(fig_dir)
    fig_dir.mkdir(parents=True, exist_ok=True)
    figs = {}
    sids = data['sample_ids']
    samples = data['samples']

    # 1. Assembly & Mapping QC Figure
    if sids:
        h = max(2.8, min(6.2, 1.4 + 0.42 * len(sids)))
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(7.4, h), layout='constrained')
        y_pos = list(range(len(sids)))
        n50s = [samples[s]['assembly']['n50_bp'] for s in sids]
        counts = [samples[s]['assembly']['total_contigs'] for s in sids]

        bars1 = ax1.barh(y_pos, n50s, color=OKABE_ITO[0], height=0.58, edgecolor='#0F1E2E', linewidth=0.5)
        ax1.set_yticks(y_pos, sids)
        ax1.invert_yaxis()
        ax1.set_xlim(left=0, right=max(max(n50s, default=0) * 1.22, 100))
        ax1.set_xlabel('Assembly N50 (bp, baseline = 0)', fontsize=9, fontweight='bold', color='#1E293B')
        ax1.set_title('A. Contig Assembly Contiguity (N50)', fontsize=9.5, fontweight='bold', color='#0F1E2E', loc='left')
        style_axes(ax1, outward=5)
        for bar, val in zip(bars1, n50s):
            ax1.text(val + max(max(n50s, default=1) * 0.02, 2), bar.get_y() + bar.get_height() / 2,
                     f'{val:,}', va='center', ha='left', fontsize=7.5, color='#1E293B')

        bars2 = ax2.barh(y_pos, counts, color=OKABE_ITO[2], height=0.58, edgecolor='#0F1E2E', linewidth=0.5)
        ax2.set_yticks(y_pos, ['' for _ in sids])
        ax2.invert_yaxis()
        ax2.set_xlim(left=0, right=max(max(counts, default=0) * 1.22, 10))
        ax2.set_xlabel('Assembled Contigs (count, baseline = 0)', fontsize=9, fontweight='bold', color='#1E293B')
        ax2.set_title('B. Total Assembled Contig Count', fontsize=9.5, fontweight='bold', color='#0F1E2E', loc='left')
        style_axes(ax2, outward=5)
        for bar, val in zip(bars2, counts):
            ax2.text(val + max(max(counts, default=1) * 0.02, 0.2), bar.get_y() + bar.get_height() / 2,
                     f'{val:,}', va='center', ha='left', fontsize=7.5, color='#1E293B')

        figs['qc'] = fig_to_png_and_b64(fig, fig_dir / 'cohort_assembly_qc.png')

    # 2. Kraken2 Read Composition Figure
    kraken_sids = [s for s in sids if samples[s]['kraken'] is not None]
    if kraken_sids:
        h = max(2.6, min(6.0, 1.3 + 0.42 * len(kraken_sids)))
        fig, ax = plt.subplots(figsize=(7.4, h), layout='constrained')
        cats = [
            ('viruses_pct', 'Viruses', OKABE_ITO[1]),
            ('bacteria_pct', 'Bacteria', OKABE_ITO[0]),
            ('eukaryota_pct', 'Eukaryota', OKABE_ITO[2]),
            ('archaea_pct', 'Archaea', OKABE_ITO[4]),
            ('unclassified_pct', 'Unclassified', '#CBD5E1'),
        ]
        y_pos = list(range(len(kraken_sids)))
        lefts = [0.0] * len(kraken_sids)
        for key, label, color in cats:
            vals = [samples[s]['kraken'][key] for s in kraken_sids]
            ax.barh(y_pos, vals, left=lefts, label=label, color=color, height=0.6, edgecolor='#FFFFFF', linewidth=0.6)
            lefts = [l + v for l, v in zip(lefts, vals)]
        ax.set_yticks(y_pos, kraken_sids)
        ax.invert_yaxis()
        ax.set_xlim(0, 100)
        ax.set_xlabel('Read Classification Percentage (%)', fontsize=9, fontweight='bold', color='#1E293B')
        ax.set_title('Read-Level Taxonomic Composition (Kraken2)', fontsize=10, fontweight='bold', color='#0F1E2E', loc='left')
        ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.18), ncol=5, frameon=False, fontsize=8)
        style_axes(ax, outward=5)
        figs['kraken'] = fig_to_png_and_b64(fig, fig_dir / 'cohort_kraken_composition.png')

    # 3. Known Viral Contigs Landscape (Contig Length vs log10(Mean Read Depth + 1))
    if data['all_viral_hits']:
        fig, ax = plt.subplots(figsize=(7.4, 3.6), layout='constrained')
        fam_counts = defaultdict(int)
        for hit in data['all_viral_hits']:
            fam_counts[hit.get('family', '').strip() or 'Unclassified_Viruses'] += 1
        top_fams = [f for f, _ in sorted(fam_counts.items(), key=lambda x: (-x[1], x[0]))[:6]]

        grouped_pts = defaultdict(list)
        for hit in data['all_viral_hits']:
            fam = hit.get('family', '').strip() or 'Unclassified_Viruses'
            grp = fam if fam in top_fams else 'Other_Viral_Families'
            grouped_pts[grp].append(hit)

        ordered_grps = [g for g in top_fams + ['Other_Viral_Families'] if g in grouped_pts]
        for idx, grp in enumerate(ordered_grps):
            pts = grouped_pts[grp]
            xs = [safe_int(p.get('query_length')) for p in pts]
            ys = [math.log10(max(0.0, safe_float(p.get('mean_depth'))) + 1.0) for p in pts]
            # Scale marker area linearly with Coverage Breadth % (min 36 pt^2 so 0% breadth stays visible)
            areas = [36.0 + 1.5 * max(0.0, safe_float(p.get('breadth_pct'))) for p in pts]
            ax.scatter(
                xs, ys, s=areas,
                c=OKABE_ITO[idx % len(OKABE_ITO)],
                marker=MARKERS[idx % len(MARKERS)],
                alpha=0.82, edgecolors='#0F1E2E', linewidths=0.6,
                label=grp.replace('_', ' '),
            )
        ax.set_xlabel('Assembled Contig Length (bp)', fontsize=9, fontweight='bold', color='#1E293B')
        ax.set_ylabel('log10(Mean Read Depth + 1)', fontsize=9, fontweight='bold', color='#1E293B')
        ax.set_title('Known Viral Contigs: Length vs. Read Depth (marker area = Coverage Breadth %)',
                     fontsize=9.5, fontweight='bold', color='#0F1E2E', loc='left')
        ax.legend(loc='best', frameon=True, facecolor='#FFFFFF', framealpha=0.9, fontsize=7.5)
        style_axes(ax, outward=6)
        figs['blast'] = fig_to_png_and_b64(fig, fig_dir / 'cohort_viral_landscape.png')

    # 4. Novel Virus Discovery Landscape (Coding Density vs Contig Length)
    if data['all_novel_candidates']:
        fig, ax = plt.subplots(figsize=(7.4, 3.6), layout='constrained')
        tier_specs = [
            ('putative_novel_virus_high_confidence', 'High-Confidence Novel', OKABE_ITO[1], 'D', 75),
            ('putative_novel_virus_moderate_confidence', 'Moderate-Confidence Novel', OKABE_ITO[0], 'o', 60),
            ('possible_eve_or_provirus_needs_review', 'EVE / Provirus Review', OKABE_ITO[4], 's', 52),
            ('unconfirmed_dark_matter', 'Unconfirmed Dark Matter', '#64748B', '^', 40),
            ('plasmid_or_low_complexity_artifact', 'Plasmid / Low Complexity', '#94A3B8', 'X', 40),
        ]
        for cls_key, label, color, marker, sz in tier_specs:
            pts = [r for r in data['all_novel_candidates'] if r.get('discovery_classification') == cls_key]
            if not pts:
                continue
            xs = [safe_int(p.get('contig_length')) for p in pts]
            ys = [safe_float(p.get('coding_density')) for p in pts]
            ax.scatter(xs, ys, s=sz, c=color, marker=marker, alpha=0.85,
                       edgecolors='#0F1E2E', linewidths=0.5, label=f'{label} (n={len(pts)})')

        # Label up to 4 top high-confidence candidates
        for cand in data['promoted_novel'][:4]:
            x = safe_int(cand.get('contig_length'))
            y = safe_float(cand.get('coding_density'))
            tag = cand.get('putative_family') or cand.get('putative_order') or cand.get('hallmark_category') or cand['query_id'][:14]
            ax.annotate(tag, (x, y), xytext=(5, 4), textcoords='offset points', fontsize=7, color='#0F1E2E')

        ax.set_ylim(0, 105)
        ax.set_xlabel('Candidate Contig Length (bp)', fontsize=9, fontweight='bold', color='#1E293B')
        ax.set_ylabel('6-Frame ORF Coding Density (%)', fontsize=9, fontweight='bold', color='#1E293B')
        ax.set_title('Novel Virus Candidate Screening: Coding Density vs. Contig Length',
                     fontsize=9.5, fontweight='bold', color='#0F1E2E', loc='left')
        ax.legend(loc='best', frameon=True, facecolor='#FFFFFF', framealpha=0.9, fontsize=7.5)
        style_axes(ax, outward=6)
        figs['novel'] = fig_to_png_and_b64(fig, fig_dir / 'cohort_novel_candidates.png')

    return figs


def render_sample_figures(sample_entry, fig_dir):
    fig_dir = Path(fig_dir)
    fig_dir.mkdir(parents=True, exist_ok=True)
    sid = sample_entry['sample_id']
    figs = {}

    cov_rows = sample_entry['coverage_rows'][:15]
    if cov_rows:
        h = max(2.6, 1.1 + 0.28 * len(cov_rows))
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(7.4, h), layout='constrained')
        labels = [r['contig'][-24:] if len(r['contig']) > 24 else r['contig'] for r in cov_rows]
        depths = [r['depth'] for r in cov_rows]
        breadths = [r['breadth'] for r in cov_rows]
        y_pos = list(range(len(cov_rows)))

        ax1.barh(y_pos, depths, color=OKABE_ITO[0], height=0.62, edgecolor='#0F1E2E', linewidth=0.5)
        ax1.set_yticks(y_pos, labels)
        ax1.invert_yaxis()
        ax1.set_xlim(left=0, right=max(max(depths, default=1.0) * 1.18, 1.0))
        ax1.set_xlabel('Mean Read Depth (x)', fontsize=8.5, fontweight='bold')
        ax1.set_title('A. Top Contigs by Read Depth', fontsize=9.5, fontweight='bold', loc='left')
        style_axes(ax1, outward=5)

        ax2.barh(y_pos, breadths, color=OKABE_ITO[2], height=0.62, edgecolor='#0F1E2E', linewidth=0.5)
        ax2.set_yticks(y_pos, ['' for _ in cov_rows])
        ax2.invert_yaxis()
        ax2.set_xlim(0, 105)
        ax2.set_xlabel('Coverage Breadth (%)', fontsize=8.5, fontweight='bold')
        ax2.set_title('B. Whole-Contig Breadth (%)', fontsize=9.5, fontweight='bold', loc='left')
        style_axes(ax2, outward=5)

        figs['coverage'] = fig_to_png_and_b64(fig, fig_dir / f'{sid}_coverage_top.png')

    return figs
