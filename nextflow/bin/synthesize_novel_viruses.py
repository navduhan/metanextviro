#!/usr/bin/env python3
"""Integrate multi-evidence layers to rank novel/divergent virus candidates in descending order."""

import argparse
import csv
import os
import sys
from contextlib import closing
from pathlib import Path

from Bio import SeqIO

sys.path.insert(0, str(Path(__file__).resolve().parent))
from process_blast_results import WIDTH_LIMITS, write_formatted_xlsx  # noqa: E402

CANDIDATE_COLUMNS = [
    'query_id', 'contig_length', 'discovery_classification', 'discovery_score',
    'evidence_sources', 'triage_reason', 'mean_read_depth', 'coverage_breadth_pct',
    'orf_count', 'max_orf_aa', 'coding_density', 'terminal_repeat_type',
    'terminal_repeat_length', 'hallmark_category', 'best_hmm_name', 'best_hmm_evalue',
    'best_hmm_score', 'viral_protein_subject', 'viral_protein_title',
    'viral_protein_identity', 'viral_protein_evalue', 'foldseek_target',
    'foldseek_probability', 'foldseek_evalue', 'virfinder_score', 'virfinder_qvalue',
    'virfinder_tier', 'genomad_virus_score', 'genomad_plasmid_score',
    'genomad_taxonomy', 'checkv_quality', 'checkv_completeness', 'checkv_viral_genes',
    'checkv_host_genes', 'blast_viral_subject', 'blast_viral_family',
    'blast_viral_identity', 'blast_viral_union_coverage', 'gc_percent',
    'kmer_entropy', 'low_complexity_flag', 'fragmented_orfs_flag', 'sequence'
]

NOVEL_INT_COLS = {
    'contig_length', 'orf_count', 'max_orf_aa', 'terminal_repeat_length',
    'checkv_viral_genes', 'checkv_host_genes'
}
NOVEL_PCT_COLS = {
    'mean_read_depth', 'coverage_breadth_pct', 'coding_density',
    'viral_protein_identity', 'foldseek_probability', 'virfinder_score',
    'genomad_virus_score', 'genomad_plasmid_score', 'checkv_completeness',
    'blast_viral_identity', 'blast_viral_union_coverage', 'gc_percent', 'kmer_entropy'
}
NOVEL_SCORE_COLS = {'discovery_score', 'best_hmm_score'}
NOVEL_EVALUE_COLS = {'best_hmm_evalue', 'viral_protein_evalue', 'foldseek_evalue', 'virfinder_qvalue'}
NOVEL_WIDTH_LIMITS = {
    **WIDTH_LIMITS,
    'discovery_classification': (28, 38),
    'evidence_sources': (26, 48),
    'triage_reason': (22, 34),
    'viral_protein_title': (22, 44),
    'genomad_taxonomy': (20, 40),
    'sequence': (28, 28),
}

TIER_PRIORITY = {
    'putative_novel_virus_high_confidence': 1,
    'putative_novel_virus_moderate_confidence': 2,
    'possible_eve_or_provirus_needs_review': 3,
    'unconfirmed_dark_matter': 4,
    'plasmid_or_low_complexity_artifact': 5,
}


def read_tsv_map(path, key_col):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return {}
    mapping = {}
    with open(path, newline='') as handle:
        for row in csv.DictReader(handle, delimiter='\t'):
            key = row.get(key_col, '').strip()
            if key and key not in mapping:
                mapping[key] = row
    return mapping


def safe_float(val, default=None):
    if val is None or str(val).strip() in ('', 'NA', 'NaN', 'nan', 'None'):
        return default
    try:
        return float(val)
    except ValueError:
        return default


def safe_int(val, default=0):
    fval = safe_float(val, None)
    return int(fval) if fval is not None else default


def strip_provirus_suffix(seq_name):
    return seq_name.split('|provirus_')[0]


def read_genomad_summaries(virus_path, plasmid_path):
    viruses = {}
    is_provirus = set()
    if virus_path and os.path.exists(virus_path) and os.path.getsize(virus_path) > 0:
        with open(virus_path, newline='') as handle:
            for row in csv.DictReader(handle, delimiter='\t'):
                raw_name = row.get('seq_name', '').strip()
                contig_id = strip_provirus_suffix(raw_name)
                if '|provirus_' in raw_name or 'provirus' in row.get('topology', '').lower():
                    is_provirus.add(contig_id)
                score = safe_float(row.get('virus_score'), 0.0)
                if contig_id not in viruses or score > safe_float(viruses[contig_id].get('virus_score'), 0.0):
                    viruses[contig_id] = row

    plasmids = {}
    if plasmid_path and os.path.exists(plasmid_path) and os.path.getsize(plasmid_path) > 0:
        with open(plasmid_path, newline='') as handle:
            for row in csv.DictReader(handle, delimiter='\t'):
                contig_id = strip_provirus_suffix(row.get('seq_name', '').strip())
                score = safe_float(row.get('plasmid_score'), 0.0)
                if contig_id not in plasmids or score > safe_float(plasmids[contig_id].get('plasmid_score'), 0.0):
                    plasmids[contig_id] = row
    return viruses, plasmids, is_provirus


def classify_candidate(triage, arch, cov, vf, checkv, gm_vir, gm_plas, provirus_flag, hmm, vp, fs):
    sources = []
    score = 0.0

    low_comp = arch.get('low_complexity_flag') == 'yes' or (vf and vf.get('low_complexity_flag') == 'yes')
    frag_orfs = arch.get('fragmented_orfs_flag') == 'yes'
    coding_density = safe_float(arch.get('coding_density'), 0.0)
    max_orf_aa = safe_int(arch.get('max_orf_aa'), 0)
    rep_type = arch.get('terminal_repeat_type', 'none')

    breadth = safe_float(cov.get('Coverage_Breadth'), None) if cov else None
    depth = safe_float(cov.get('Average_Coverage'), None) if cov else None

    has_hmm = bool(hmm and safe_float(hmm.get('evalue'), 1.0) <= 1e-5)
    if has_hmm:
        cat = hmm.get('hallmark_category', 'Viral_HMM')
        sources.append(f'hallmark_hmm:{cat}')
        score += 40.0 if cat in ('RdRp', 'Capsid_Coat', 'Portal_Terminase', 'Helicase_Rep') else 30.0

    has_vp = bool(vp and safe_float(vp.get('evalue'), 1.0) <= 1e-4)
    if has_vp:
        vp_id = safe_float(vp.get('percent_identity'), 0.0)
        sources.append(f'viral_protein:{vp_id:.1f}%id')
        score += 28.0 if safe_float(vp.get('evalue'), 1.0) <= 1e-10 else 18.0

    has_fs = bool(fs and (safe_float(fs.get('probability'), 0.0) >= 0.85 or safe_float(fs.get('evalue'), 1.0) <= 1e-4))
    if has_fs:
        sources.append(f"foldseek_3d:prob={safe_float(fs.get('probability'), 0.0):.2f}")
        score += 22.0

    triage_reason = triage.get('triage_reason', '')
    if triage_reason == 'divergent_or_partial_viral_hit':
        b_id = safe_float(triage.get('best_viral_identity'), 0.0)
        sources.append(f'divergent_blast:{b_id:.1f}%id')
        score += 20.0

    gm_vscore = safe_float(gm_vir.get('virus_score'), None) if gm_vir else None
    gm_pscore = safe_float(gm_plas.get('plasmid_score'), None) if gm_plas else None
    is_plasmid = bool(gm_pscore is not None and gm_pscore >= 0.7 and (gm_vscore is None or gm_pscore > gm_vscore))
    has_gm_viral = bool(gm_vscore is not None and gm_vscore >= 0.7 and not is_plasmid)
    if has_gm_viral:
        sources.append(f'genomad:{gm_vscore:.2f}')
        score += 24.0

    vf_tier = vf.get('confidence_tier', '') if vf else ''
    if vf_tier == 'high_confidence':
        sources.append(f"virfinder:high({safe_float(vf.get('score'), 0.0):.2f})")
        score += 18.0
    elif vf_tier == 'moderate_confidence':
        sources.append(f"virfinder:moderate({safe_float(vf.get('score'), 0.0):.2f})")
        score += 10.0

    cv_vgenes = safe_int(checkv.get('viral_genes'), 0) if checkv else 0
    cv_hgenes = safe_int(checkv.get('host_genes'), 0) if checkv else 0
    cv_qual = checkv.get('checkv_quality', '') if checkv else ''
    has_checkv_viral = cv_vgenes > 0 or cv_qual in ('Complete', 'High-quality', 'Medium-quality')
    if has_checkv_viral:
        sources.append(f'checkv:{cv_qual or "viral_genes"}')
        score += 20.0

    if coding_density >= 75.0 and max_orf_aa >= 150:
        sources.append(f'dense_orfs:{coding_density:.0f}%')
        score += 10.0
    if rep_type in ('DTR', 'ITR'):
        sources.append(f'terminal_repeat:{rep_type}')
        score += 10.0
    if breadth is not None and breadth >= 85.0 and (depth is None or depth >= 2.0):
        sources.append(f'read_support:{breadth:.0f}%breadth')
        score += 8.0

    score = round(min(100.0, score), 1)

    if low_comp or is_plasmid:
        if is_plasmid:
            sources.append(f'plasmid_call:{gm_pscore:.2f}')
        if low_comp:
            sources.append('low_complexity_warning')
        return 'plasmid_or_low_complexity_artifact', max(0.0, round(score * 0.25, 1)), ';'.join(sources)

    has_any_viral_signal = any([
        has_hmm, has_vp, has_fs, has_gm_viral, has_checkv_viral,
        vf_tier in ('high_confidence', 'moderate_confidence'),
        triage_reason in ('divergent_or_partial_viral_hit', 'conflicting_viral_and_cellular_hits'),
    ])

    eve_or_chimera_warning = (
        cv_hgenes > 0
        or provirus_flag
        or triage_reason == 'conflicting_viral_and_cellular_hits'
        or frag_orfs
        or (breadth is not None and depth is not None and depth > 0 and breadth < 50.0)
    )

    if has_any_viral_signal and eve_or_chimera_warning:
        if cv_hgenes > 0:
            sources.append(f'host_genes:{cv_hgenes}')
        if provirus_flag:
            sources.append('provirus_region')
        if frag_orfs:
            sources.append('fragmented_orfs')
        if breadth is not None and breadth < 50.0:
            sources.append(f'partial_breadth:{breadth:.1f}%')
        return 'possible_eve_or_provirus_needs_review', score, ';'.join(sources)

    strong_coverage_ok = (breadth is None or breadth >= 70.0)
    independent_signals = sum([
        has_hmm, has_vp, has_fs, has_gm_viral, has_checkv_viral,
        vf_tier == 'high_confidence',
        triage_reason == 'divergent_or_partial_viral_hit',
    ])

    if strong_coverage_ok and (
        has_hmm
        or (has_vp and (coding_density >= 55.0 or independent_signals >= 2))
        or (has_fs and independent_signals >= 2)
        or (independent_signals >= 2 and coding_density >= 60.0)
    ):
        return 'putative_novel_virus_high_confidence', score, ';'.join(sources)

    if has_any_viral_signal or (rep_type in ('DTR', 'ITR') and coding_density >= 75.0 and max_orf_aa >= 150):
        return 'putative_novel_virus_moderate_confidence', score, ';'.join(sources)

    return 'unconfirmed_dark_matter', score, ';'.join(sources) or 'unassigned_no_homology'


def synthesize_novel_viruses(contigs_fasta, candidate_orfs, triage_manifest, architecture_tsv,
                             prefix, coverage_tsv=None, virfinder_tsv=None, checkv_tsv=None,
                             genomad_virus_tsv=None, genomad_plasmid_tsv=None,
                             hmm_tsv=None, viral_protein_tsv=None, foldseek_tsv=None):
    triage_rows = []
    if os.path.exists(triage_manifest) and os.path.getsize(triage_manifest) > 0:
        with open(triage_manifest, newline='') as handle:
            triage_rows = list(csv.DictReader(handle, delimiter='\t'))

    arch_map = read_tsv_map(architecture_tsv, 'query_id')
    cov_map = read_tsv_map(coverage_tsv, 'Contig')
    vf_map = read_tsv_map(virfinder_tsv, 'name')
    cv_map = read_tsv_map(checkv_tsv, 'contig_id')
    gm_vir_map, gm_plas_map, provirus_set = read_genomad_summaries(genomad_virus_tsv, genomad_plasmid_tsv)
    hmm_map = read_tsv_map(hmm_tsv, 'query_id')
    vp_map = read_tsv_map(viral_protein_tsv, 'query_id')
    fs_map = read_tsv_map(foldseek_tsv, 'query_id')

    candidate_rows = []
    promoted_ids = {}
    class_counts = {k: 0 for k in TIER_PRIORITY}
    triage_counts = {}

    with closing(SeqIO.index(str(contigs_fasta), 'fasta')) as seq_index:
        for triage in triage_rows:
            cat = triage['triage_category']
            triage_counts[cat] = triage_counts.get(cat, 0) + 1
            if triage['send_to_discovery'] != 'yes':
                continue

            qid = triage['query_id']
            arch = arch_map.get(qid, {})
            cov = cov_map.get(qid, {})
            vf = vf_map.get(qid, {})
            cv = cv_map.get(qid, {})
            gm_vir = gm_vir_map.get(qid, {})
            gm_plas = gm_plas_map.get(qid, {})
            hmm = hmm_map.get(qid, {})
            vp = vp_map.get(qid, {})
            fs = fs_map.get(qid, {})

            classification, score, evidence_str = classify_candidate(
                triage, arch, cov, vf, cv, gm_vir, gm_plas, qid in provirus_set, hmm, vp, fs
            )
            class_counts[classification] = class_counts.get(classification, 0) + 1
            if classification in ('putative_novel_virus_high_confidence', 'putative_novel_virus_moderate_confidence'):
                promoted_ids[qid] = (classification, score, evidence_str)

            candidate_rows.append({
                'query_id': qid,
                'contig_length': safe_int(triage.get('contig_length'), 0),
                'discovery_classification': classification,
                'discovery_score': score,
                'evidence_sources': evidence_str,
                'triage_reason': triage.get('triage_reason', ''),
                'mean_read_depth': cov.get('Average_Coverage', ''),
                'coverage_breadth_pct': cov.get('Coverage_Breadth', ''),
                'orf_count': arch.get('orf_count', 0),
                'max_orf_aa': arch.get('max_orf_aa', 0),
                'coding_density': arch.get('coding_density', 0.0),
                'terminal_repeat_type': arch.get('terminal_repeat_type', 'none'),
                'terminal_repeat_length': arch.get('terminal_repeat_length', 0),
                'hallmark_category': hmm.get('hallmark_category', ''),
                'best_hmm_name': hmm.get('hmm_name', ''),
                'best_hmm_evalue': hmm.get('evalue', ''),
                'best_hmm_score': hmm.get('domain_score', ''),
                'viral_protein_subject': vp.get('subject_id', ''),
                'viral_protein_title': vp.get('subject_title', ''),
                'viral_protein_identity': vp.get('percent_identity', ''),
                'viral_protein_evalue': vp.get('evalue', ''),
                'foldseek_target': fs.get('target_id', ''),
                'foldseek_probability': fs.get('probability', ''),
                'foldseek_evalue': fs.get('evalue', ''),
                'virfinder_score': vf.get('score', ''),
                'virfinder_qvalue': vf.get('qvalue', ''),
                'virfinder_tier': vf.get('confidence_tier', ''),
                'genomad_virus_score': gm_vir.get('virus_score', ''),
                'genomad_plasmid_score': gm_plas.get('plasmid_score', ''),
                'genomad_taxonomy': gm_vir.get('taxonomy', ''),
                'checkv_quality': cv.get('checkv_quality', ''),
                'checkv_completeness': cv.get('completeness', ''),
                'checkv_viral_genes': cv.get('viral_genes', ''),
                'checkv_host_genes': cv.get('host_genes', ''),
                'blast_viral_subject': triage.get('best_viral_subject', ''),
                'blast_viral_family': triage.get('best_viral_family', ''),
                'blast_viral_identity': triage.get('best_viral_identity', ''),
                'blast_viral_union_coverage': triage.get('best_viral_union_coverage', ''),
                'gc_percent': arch.get('gc_percent', ''),
                'kmer_entropy': arch.get('kmer_entropy', ''),
                'low_complexity_flag': arch.get('low_complexity_flag', 'no'),
                'fragmented_orfs_flag': arch.get('fragmented_orfs_flag', 'no'),
                'sequence': str(seq_index[qid].seq) if qid in seq_index else '',
            })

        candidate_rows.sort(key=lambda r: (
            TIER_PRIORITY.get(r['discovery_classification'], 99),
            -float(r['discovery_score']),
            -int(r['contig_length']),
            -safe_int(r['max_orf_aa'], 0),
            r['query_id'],
        ))

        with open(f'{prefix}_novel_virus_candidates.tsv', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=CANDIDATE_COLUMNS, delimiter='\t')
            writer.writeheader()
            writer.writerows(candidate_rows)

        write_formatted_xlsx(
            f'{prefix}_novel_virus_candidates.xlsx',
            CANDIDATE_COLUMNS,
            candidate_rows,
            f'novel_{Path(prefix).name}',
            int_cols=NOVEL_INT_COLS,
            pct_cols=NOVEL_PCT_COLS,
            score_cols=NOVEL_SCORE_COLS,
            evalue_cols=NOVEL_EVALUE_COLS,
            width_limits=NOVEL_WIDTH_LIMITS,
        )

        # Write promoted candidate nucleotide FASTA in descending rank order
        with open(f'{prefix}_novel_virus_candidates.fasta', 'w') as fa_out:
            for row in candidate_rows:
                qid = row['query_id']
                if qid in promoted_ids and qid in seq_index:
                    cls, sc, ev = promoted_ids[qid]
                    fa_out.write(
                        f">{qid} classification={cls} score={sc} length={row['contig_length']} "
                        f"evidence={ev}\n{row['sequence']}\n"
                    )

    # Write promoted candidate ORFs FASTA (for downstream phylogeny or domain inspection)
    with open(f'{prefix}_novel_virus_orfs.faa', 'w') as orf_out:
        if candidate_orfs and os.path.exists(candidate_orfs) and os.path.getsize(candidate_orfs) > 0:
            with open(candidate_orfs) as orf_handle:
                for rec in SeqIO.parse(orf_handle, 'fasta'):
                    contig_id = rec.id.rsplit('_orf', 1)[0]
                    if contig_id in promoted_ids:
                        SeqIO.write(rec, orf_out, 'fasta')

    with open(f'{prefix}_novel_discovery_summary.txt', 'w') as rep:
        rep.write(f'Novel Virus Discovery Summary for {prefix}\n')
        rep.write('=' * 56 + '\n\n')
        rep.write('1. Post-BLAST Contig Triage:\n')
        rep.write(f'   - Known viruses skipped (already identified by BLAST): {triage_counts.get("known_virus", 0)}\n')
        rep.write(f'   - Known cellular/host contigs skipped:                 {triage_counts.get("known_non_viral", 0)}\n')
        rep.write(f'   - Short contigs skipped:                               {triage_counts.get("short_unassigned", 0)}\n')
        rep.write(f'   - Candidate contigs evaluated for novel viruses:       {len(candidate_rows)}\n\n')
        rep.write('2. Candidate Classification Breakdown:\n')
        for cls_name in TIER_PRIORITY:
            rep.write(f'   - {cls_name}: {class_counts.get(cls_name, 0)}\n')
        rep.write('\nNote: Candidate classifications separate sequence detection from confirmed\n')
        rep.write('host infection. Inspect read breadth, EVE/provirus flags, and phylogenies before\n')
        rep.write('making taxonomic or host-association claims.\n')

    print(
        f'Synthesized {len(candidate_rows)} candidate contigs for {prefix}: '
        f'{class_counts["putative_novel_virus_high_confidence"]} high-confidence and '
        f'{class_counts["putative_novel_virus_moderate_confidence"]} moderate-confidence novel candidates.'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contigs_fasta', required=True)
    parser.add_argument('--candidate_orfs', required=True)
    parser.add_argument('--triage_manifest', required=True)
    parser.add_argument('--architecture', required=True)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--coverage')
    parser.add_argument('--virfinder')
    parser.add_argument('--checkv')
    parser.add_argument('--genomad_virus')
    parser.add_argument('--genomad_plasmid')
    parser.add_argument('--hmm_hits')
    parser.add_argument('--viral_protein_hits')
    parser.add_argument('--foldseek_hits')
    args = parser.parse_args()
    synthesize_novel_viruses(
        args.contigs_fasta, args.candidate_orfs, args.triage_manifest,
        args.architecture, args.prefix, args.coverage, args.virfinder,
        args.checkv, args.genomad_virus, args.genomad_plasmid,
        args.hmm_hits, args.viral_protein_hits, args.foldseek_hits,
    )


if __name__ == '__main__':
    main()
