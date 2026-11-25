#!/usr/bin/env python3
# Author: Naveen Duhan
# SPDX-License-Identifier: MIT
"""Combines architecture metrics, HMM, DIAMOND, Foldseek, geNomad, CheckV, VirFinder, and coverage evidence into a composite viral score and assigns identity-capped ICTV taxonomy to candidate contigs."""

import argparse
import csv
import os
import sys
from collections import defaultdict
from contextlib import closing
from pathlib import Path

from Bio import SeqIO

sys.path.insert(0, str(Path(__file__).resolve().parent))
from process_blast_results import WIDTH_LIMITS, write_formatted_xlsx  # noqa: E402

TAX_RANKS = ['kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']

CANDIDATE_COLUMNS = [
    'query_id', 'contig_length', 'discovery_classification', 'discovery_score',
    'putative_kingdom', 'putative_phylum', 'putative_class', 'putative_order',
    'putative_family', 'putative_genus', 'taxonomic_assignment_level',
    'taxonomy_evidence_source', 'evidence_sources', 'triage_reason',
    'mean_read_depth', 'coverage_breadth_pct', 'orf_count', 'max_orf_aa',
    'coding_density', 'terminal_repeat_type', 'terminal_repeat_length',
    'hallmark_category', 'best_hmm_name', 'best_hmm_evalue', 'best_hmm_score',
    'viral_protein_subject', 'viral_protein_title', 'viral_protein_identity',
    'viral_protein_evalue', 'foldseek_target', 'foldseek_probability',
    'foldseek_evalue', 'virfinder_score', 'virfinder_qvalue', 'virfinder_tier',
    'genomad_virus_score', 'genomad_plasmid_score', 'genomad_taxonomy',
    'checkv_quality', 'checkv_completeness', 'checkv_viral_genes',
    'checkv_host_genes', 'blast_viral_subject', 'blast_viral_family',
    'blast_viral_identity', 'blast_viral_union_coverage', 'gc_percent',
    'kmer_entropy', 'low_complexity_flag', 'fragmented_orfs_flag', 'sequence'
]

VIRFINDER_TAX_COLUMNS = [
    'query_id', 'contig_length', 'virfinder_score', 'virfinder_qvalue',
    'virfinder_pvalue', 'virfinder_tier', 'putative_kingdom', 'putative_phylum',
    'putative_class', 'putative_order', 'putative_family', 'putative_genus',
    'taxonomic_assignment_level', 'taxonomy_evidence_source',
    'discovery_classification', 'hallmark_category', 'best_hmm_name',
    'viral_protein_subject', 'viral_protein_title', 'viral_protein_identity',
    'viral_protein_evalue', 'mean_read_depth', 'coverage_breadth_pct',
    'orf_count', 'max_orf_aa', 'coding_density', 'terminal_repeat_type',
    'low_complexity_flag', 'sequence'
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
NOVEL_EVALUE_COLS = {
    'best_hmm_evalue', 'viral_protein_evalue', 'foldseek_evalue',
    'virfinder_qvalue', 'virfinder_pvalue'
}
NOVEL_WIDTH_LIMITS = {
    **WIDTH_LIMITS,
    'discovery_classification': (28, 38),
    'putative_kingdom': (16, 24),
    'putative_phylum': (16, 24),
    'putative_class': (16, 24),
    'putative_order': (18, 26),
    'putative_family': (18, 28),
    'putative_genus': (16, 26),
    'taxonomic_assignment_level': (24, 34),
    'taxonomy_evidence_source': (24, 38),
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
    keys = (key_col,) if isinstance(key_col, str) else tuple(key_col)
    mapping = {}
    with open(path, newline='') as handle:
        for row in csv.DictReader(handle, delimiter='\t'):
            key = ''
            for k in keys:
                val = row.get(k, '')
                if val and val.strip():
                    key = val.strip()
                    break
            if key and key not in mapping:
                mapping[key] = row
    return mapping


def read_tsv_grouped(path, key_col):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return {}
    grouped = defaultdict(list)
    with open(path, newline='') as handle:
        for row in csv.DictReader(handle, delimiter='\t'):
            key = row.get(key_col, '').strip()
            if key:
                grouped[key].append(row)
    return dict(grouped)


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


def parse_genomad_lineage(tax_str):
    """Parse geNomad 7-field ICTV lineage (Viruses;Realm;Kingdom;Phylum;Class;Order;Family)."""
    out = {r: '' for r in TAX_RANKS[:6]}
    if not tax_str or str(tax_str).strip() in ('', 'Unclassified'):
        return out
    parts = [p.strip() for p in str(tax_str).split(';')]
    # Standard geNomad slots: 0=Viruses, 1=Realm, 2=Kingdom, 3=Phylum, 4=Class, 5=Order, 6=Family
    slot_map = [(2, 'kingdom'), (3, 'phylum'), (4, 'class'), (5, 'order'), (6, 'family')]
    for idx, rank in slot_map:
        if idx < len(parts) and parts[idx] and not parts[idx].lower().startswith('unclassified'):
            out[rank] = parts[idx]
    # Also scan suffixes if non-standard slot count
    if not any(out.values()):
        for p in parts:
            pl = p.lower()
            if pl.endswith('virae'):
                out['kingdom'] = p
            elif pl.endswith('viricota'):
                out['phylum'] = p
            elif pl.endswith('viricetes'):
                out['class'] = p
            elif pl.endswith('virales'):
                out['order'] = p
            elif pl.endswith('viridae'):
                out['family'] = p
    return out


def infer_putative_viral_taxonomy(triage, vp_rows, hmm_rows, gm_vir):
    """Infer putative viral Kingdom..Genus via multi-ORF protein LCA, geNomad, HMM LCA, or BLAST."""
    empty_tax = {f'putative_{r}': '' for r in TAX_RANKS[:6]}

    # 1. Multi-ORF Viral Protein Bitscore-Weighted LCA + AA Identity Calibration
    best_per_orf = {}
    for row in vp_rows or []:
        if safe_float(row.get('evalue'), 1.0) > 1e-4:
            continue
        oid = row.get('orf_id', '')
        if oid not in best_per_orf or safe_float(row.get('bit_score'), 0.0) > safe_float(best_per_orf[oid].get('bit_score'), 0.0):
            best_per_orf[oid] = row

    tax_orfs = [r for r in best_per_orf.values() if any(r.get(rk, '').strip() for rk in TAX_RANKS[:6])]
    if tax_orfs:
        total_bits = sum(max(1.0, safe_float(r.get('bit_score'), 1.0)) for r in tax_orfs)
        weighted_pident = sum(
            safe_float(r.get('percent_identity'), 0.0) * max(1.0, safe_float(r.get('bit_score'), 1.0))
            for r in tax_orfs
        ) / total_bits

        consensus = {}
        for rk in TAX_RANKS[:6]:
            votes = defaultdict(float)
            for r in tax_orfs:
                val = r.get(rk, '').strip()
                if val:
                    votes[val] += max(1.0, safe_float(r.get('bit_score'), 1.0))
            if not votes:
                consensus[rk] = ''
                continue
            top_taxon, top_weight = max(votes.items(), key=lambda item: item[1])
            if top_weight / total_bits >= 0.60:
                consensus[rk] = top_taxon
            else:
                # Conflicting lower ranks stop downward assignment
                for lower_rk in TAX_RANKS[TAX_RANKS.index(rk):6]:
                    consensus[lower_rk] = ''
                break

        # Identity-calibrated deepest rank cap (prevents over-claiming genus/family on twilight AA hits)
        if weighted_pident < 25.0:
            consensus['family'] = ''
            consensus['genus'] = ''
            level = f'order_or_class_distant({weighted_pident:.1f}%_aa)'
        elif weighted_pident < 40.0:
            consensus['genus'] = ''
            level = f'family_putative_divergent({weighted_pident:.1f}%_aa)'
        elif weighted_pident < 65.0:
            consensus['genus'] = ''
            level = f'family_confident_novel_genus({weighted_pident:.1f}%_aa)'
        else:
            level = f'genus_confident({weighted_pident:.1f}%_aa)'

        if any(consensus.values()):
            return {
                **{f'putative_{rk}': consensus.get(rk, '') for rk in TAX_RANKS[:6]},
                'taxonomic_assignment_level': level,
                'taxonomy_evidence_source': f'viral_protein_lca({len(tax_orfs)}_orf{"s" if len(tax_orfs) != 1 else ""})',
            }

    # 2. geNomad Marker Taxonomy
    if gm_vir and safe_float(gm_vir.get('virus_score'), 0.0) >= 0.7:
        gm_lin = parse_genomad_lineage(gm_vir.get('taxonomy', ''))
        if any(gm_lin.values()):
            deepest = next((rk for rk in reversed(TAX_RANKS[:5]) if gm_lin.get(rk)), 'kingdom')
            return {
                **{f'putative_{rk}': gm_lin.get(rk, '') for rk in TAX_RANKS[:6]},
                'taxonomic_assignment_level': f'{deepest}_marker_taxonomy',
                'taxonomy_evidence_source': 'genomad_marker_lca',
            }

    # 3. Hallmark Profile-HMM Lineage (VOGDB LCA or RdRp/Viral clade)
    valid_hmms = [r for r in (hmm_rows or []) if safe_float(r.get('evalue'), 1.0) <= 1e-5]
    for h_row in valid_hmms:
        if any(h_row.get(rk, '').strip() for rk in TAX_RANKS[:6]):
            deepest = next((rk for rk in reversed(TAX_RANKS[:6]) if h_row.get(rk, '').strip()), 'kingdom')
            return {
                **{f'putative_{rk}': h_row.get(rk, '').strip() for rk in TAX_RANKS[:6]},
                'taxonomic_assignment_level': f'{deepest}_hallmark_hmm_clade',
                'taxonomy_evidence_source': f"hallmark_hmm:{h_row.get('hmm_name', '')}",
            }

    # 4. Divergent / Partial BLAST Viral Lineage
    if triage.get('triage_reason') in ('divergent_or_partial_viral_hit', 'conflicting_viral_and_cellular_hits'):
        b_tax = {rk: triage.get(f'best_viral_{rk}', '').strip() for rk in TAX_RANKS[:6]}
        if any(b_tax.values()):
            b_id = safe_float(triage.get('best_viral_identity'), 0.0)
            if b_id < 70.0:
                b_tax['genus'] = ''
            return {
                **{f'putative_{rk}': b_tax.get(rk, '') for rk in TAX_RANKS[:6]},
                'taxonomic_assignment_level': f'divergent_blast_lineage({b_id:.1f}%_nt)',
                'taxonomy_evidence_source': f"blast_{triage.get('best_viral_database', 'viral')}",
            }

    return {
        **empty_tax,
        'taxonomic_assignment_level': 'unassigned_no_homolog',
        'taxonomy_evidence_source': 'none_kmer_or_architecture_only',
    }


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
        gated_eve_score = min(44.0, max(0.0, round(score * 0.50, 1)))
        return 'possible_eve_or_provirus_needs_review', gated_eve_score, ';'.join(sources)

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
                             hmm_tsv=None, viral_protein_tsv=None, foldseek_tsv=None,
                             virfinder_tax_prefix=None):
    triage_rows = []
    if os.path.exists(triage_manifest) and os.path.getsize(triage_manifest) > 0:
        with open(triage_manifest, newline='') as handle:
            triage_rows = list(csv.DictReader(handle, delimiter='\t'))

    arch_map = read_tsv_map(architecture_tsv, 'query_id')
    cov_map = read_tsv_map(coverage_tsv, 'Contig')
    vf_map = read_tsv_map(virfinder_tsv, ('name', 'query_id'))
    cv_map = read_tsv_map(checkv_tsv, 'contig_id')
    gm_vir_map, gm_plas_map, provirus_set = read_genomad_summaries(genomad_virus_tsv, genomad_plasmid_tsv)
    hmm_grouped = read_tsv_grouped(hmm_tsv, 'query_id')
    vp_grouped = read_tsv_grouped(viral_protein_tsv, 'query_id')
    fs_map = read_tsv_map(foldseek_tsv, 'query_id')

    candidate_rows = []
    vf_tax_rows = []
    promoted_ids = {}
    class_counts = {k: 0 for k in TIER_PRIORITY}
    triage_counts = {}
    tax_assigned_count = 0

    def _clean(val):
        return '' if val is None or str(val).strip() in ('', 'NA', 'NaN', 'nan', 'None') else val

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
            hmm_list = hmm_grouped.get(qid, [])
            vp_list = vp_grouped.get(qid, [])
            hmm = hmm_list[0] if hmm_list else {}
            vp = vp_list[0] if vp_list else {}
            fs = fs_map.get(qid, {})

            tax_assignment = infer_putative_viral_taxonomy(triage, vp_list, hmm_list, gm_vir)
            if tax_assignment['taxonomic_assignment_level'] != 'unassigned_no_homolog':
                tax_assigned_count += 1

            classification, score, evidence_str = classify_candidate(
                triage, arch, cov, vf, cv, gm_vir, gm_plas, qid in provirus_set, hmm, vp, fs
            )
            class_counts[classification] = class_counts.get(classification, 0) + 1
            if classification in ('putative_novel_virus_high_confidence', 'putative_novel_virus_moderate_confidence'):
                promoted_ids[qid] = (classification, score, evidence_str, tax_assignment)

            seq_str = str(seq_index[qid].seq) if qid in seq_index else ''
            row = {
                'query_id': qid,
                'contig_length': safe_int(triage.get('contig_length'), 0),
                'discovery_classification': classification,
                'discovery_score': score,
                **tax_assignment,
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
                'virfinder_score': _clean(vf.get('score', '')),
                'virfinder_qvalue': _clean(vf.get('qvalue', '')),
                'virfinder_tier': _clean(vf.get('confidence_tier', '')),
                'genomad_virus_score': _clean(gm_vir.get('virus_score', '')),
                'genomad_plasmid_score': _clean(gm_plas.get('plasmid_score', '')),
                'genomad_taxonomy': _clean(gm_vir.get('taxonomy', '')),
                'checkv_quality': _clean(cv.get('checkv_quality', '')),
                'checkv_completeness': _clean(cv.get('completeness', '')),
                'checkv_viral_genes': _clean(cv.get('viral_genes', '')),
                'checkv_host_genes': _clean(cv.get('host_genes', '')),
                'blast_viral_subject': triage.get('best_viral_subject', ''),
                'blast_viral_family': triage.get('best_viral_family', ''),
                'blast_viral_identity': triage.get('best_viral_identity', ''),
                'blast_viral_union_coverage': triage.get('best_viral_union_coverage', ''),
                'gc_percent': arch.get('gc_percent', ''),
                'kmer_entropy': arch.get('kmer_entropy', ''),
                'low_complexity_flag': arch.get('low_complexity_flag', 'no'),
                'fragmented_orfs_flag': arch.get('fragmented_orfs_flag', 'no'),
                'sequence': seq_str,
            }
            candidate_rows.append(row)

            if vf and vf.get('confidence_tier') in ('high_confidence', 'moderate_confidence'):
                vf_tax_rows.append({
                    **{col: row.get(col, '') for col in VIRFINDER_TAX_COLUMNS if col != 'virfinder_pvalue'},
                    'virfinder_pvalue': vf.get('pvalue', ''),
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

        # Dedicated VirFinder + Putative Order/Family report when VirFinder was run
        if virfinder_tax_prefix:
            vf_tax_rows.sort(key=lambda r: (
                -safe_float(r['virfinder_score'], 0.0),
                safe_float(r['virfinder_qvalue'], 1.0),
                -int(r['contig_length']),
                r['query_id'],
            ))
            with open(f'{virfinder_tax_prefix}.tsv', 'w', newline='') as vf_out:
                writer = csv.DictWriter(vf_out, fieldnames=VIRFINDER_TAX_COLUMNS, delimiter='\t')
                writer.writeheader()
                writer.writerows(vf_tax_rows)
            write_formatted_xlsx(
                f'{virfinder_tax_prefix}.xlsx',
                VIRFINDER_TAX_COLUMNS,
                vf_tax_rows,
                f'vf_tax_{Path(prefix).name}',
                int_cols=NOVEL_INT_COLS,
                pct_cols=NOVEL_PCT_COLS,
                score_cols=NOVEL_SCORE_COLS,
                evalue_cols=NOVEL_EVALUE_COLS,
                width_limits=NOVEL_WIDTH_LIMITS,
            )

        # Write promoted candidate nucleotide FASTA with putative order/family in header
        with open(f'{prefix}_novel_virus_candidates.fasta', 'w') as fa_out:
            for row in candidate_rows:
                qid = row['query_id']
                if qid in promoted_ids and qid in seq_index:
                    cls, sc, ev, tax_info = promoted_ids[qid]
                    order_lbl = tax_info.get('putative_order') or 'Unassigned'
                    family_lbl = tax_info.get('putative_family') or 'Unassigned'
                    fa_out.write(
                        f">{qid} classification={cls} score={sc} length={row['contig_length']} "
                        f"putative_order={order_lbl} putative_family={family_lbl} "
                        f"tax_source={tax_info['taxonomy_evidence_source']} evidence={ev}\n{row['sequence']}\n"
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
        rep.write(f'\n3. Putative Higher-Rank Viral Taxonomy Assigned (Order/Family/Kingdom): {tax_assigned_count}/{len(candidate_rows)}\n')
        if tax_assigned_count == 0 and len(candidate_rows) > 0:
            rep.write('   Tip: Run `nextflow run navduhan/metanextviro --setup_databases --db_dir ~/.metanextviro/dbs -profile conda`\n')
            rep.write('   and pass `--run_viral_protein_blast --run_viral_hmm` to\n')
            rep.write('   assign viral Order and Family to VirFinder and dark-matter candidates.\n')
        rep.write('\nNote: Candidate classifications separate sequence detection from confirmed\n')
        rep.write('host infection. Inspect read breadth, EVE/provirus flags, and phylogenies before\n')
        rep.write('making taxonomic or host-association claims.\n')

    print(
        f'Synthesized {len(candidate_rows)} candidate contigs for {prefix}: '
        f'{class_counts["putative_novel_virus_high_confidence"]} high-confidence, '
        f'{class_counts["putative_novel_virus_moderate_confidence"]} moderate-confidence, '
        f'{tax_assigned_count} assigned putative viral taxonomy.'
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
    parser.add_argument('--virfinder_tax_prefix', help='Optional output prefix for VirFinder+Taxonomy TSV/XLSX')
    args = parser.parse_args()
    synthesize_novel_viruses(
        args.contigs_fasta, args.candidate_orfs, args.triage_manifest,
        args.architecture, args.prefix, args.coverage, args.virfinder,
        args.checkv, args.genomad_virus, args.genomad_plasmid,
        args.hmm_hits, args.viral_protein_hits, args.foldseek_hits,
        args.virfinder_tax_prefix,
    )


if __name__ == '__main__':
    main()
