#!/usr/bin/env python3
"""Partition assembled contigs after BLAST so novel-virus tools skip confident known hits."""

import argparse
import csv
import os
import sys
from pathlib import Path

from Bio import SeqIO

sys.path.insert(0, str(Path(__file__).resolve().parent))
from process_blast_results import hit_order, merge_intervals  # noqa: E402


TRIAGE_COLUMNS = [
    'query_id', 'contig_length', 'triage_category', 'triage_reason', 'send_to_discovery',
    'best_viral_database', 'best_viral_subject', 'best_viral_title',
    'best_viral_kingdom', 'best_viral_phylum', 'best_viral_class',
    'best_viral_order', 'best_viral_family', 'best_viral_genus', 'best_viral_species',
    'best_viral_identity', 'best_viral_union_coverage',
    'best_viral_bit_score', 'best_viral_evalue', 'best_cellular_superkingdom',
    'best_cellular_identity', 'best_cellular_union_coverage'
]


def summarize_blast_for_triage(blast_files):
    """Collect best viral and cellular BLAST evidence per contig across searched DBs."""
    per_contig = {}
    for path in blast_files or []:
        if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
            continue
        with open(path, newline='') as handle:
            for row in csv.DictReader(handle, delimiter='\t'):
                qid = row['query_id']
                qlen = int(row['query_length'])
                start, end = sorted((int(row['query_start']), int(row['query_end'])))
                superkingdom = row.get('superkingdom', '').strip()
                entry = per_contig.setdefault(qid, {
                    'qlen': qlen,
                    'viral_subjects': {},
                    'cellular_intervals': [],
                    'best_cellular': None,
                    'any_hit': False,
                })
                entry['any_hit'] = True
                if superkingdom == 'Viruses':
                    key = (row.get('search_database', ''), row['subject_id'])
                    subj = entry['viral_subjects'].setdefault(key, {'best': row, 'intervals': []})
                    subj['intervals'].append((start, end))
                    if hit_order(row) < hit_order(subj['best']):
                        subj['best'] = row
                elif superkingdom in ('Bacteria', 'Archaea', 'Eukaryota'):
                    entry['cellular_intervals'].append((start, end))
                    if entry['best_cellular'] is None or hit_order(row) < hit_order(entry['best_cellular']):
                        entry['best_cellular'] = row

    summaries = {}
    for qid, entry in per_contig.items():
        qlen = entry['qlen']
        best_viral = None
        best_viral_cov = 0.0
        for (_, _), subj in entry['viral_subjects'].items():
            merged = merge_intervals(subj['intervals'])
            cov = round(100.0 * sum(e - s + 1 for s, e in merged) / qlen, 2)
            cand = subj['best']
            if best_viral is None or hit_order(cand) < hit_order(best_viral):
                best_viral = cand
                best_viral_cov = cov

        cell_cov = 0.0
        if entry['cellular_intervals']:
            merged_cell = merge_intervals(entry['cellular_intervals'])
            cell_cov = round(100.0 * sum(e - s + 1 for s, e in merged_cell) / qlen, 2)

        summaries[qid] = {
            'any_hit': entry['any_hit'],
            'best_viral': best_viral,
            'viral_cov': best_viral_cov,
            'best_cellular': entry['best_cellular'],
            'cellular_cov': cell_cov,
        }
    return summaries


def triage_contigs(fasta_file, blast_files, prefix, min_candidate_length=500,
                   known_virus_identity=80.0, known_virus_coverage=50.0,
                   non_viral_identity=75.0, non_viral_coverage=40.0,
                   include_all_contigs=False):
    blast_summary = summarize_blast_for_triage(blast_files)
    with open(fasta_file) as fasta_handle:
        records = list(SeqIO.parse(fasta_handle, 'fasta'))
    records.sort(key=lambda rec: (-len(rec.seq), rec.id))

    manifest_rows = []
    candidate_records = []
    counts = {
        'known_virus': 0,
        'known_non_viral': 0,
        'short_unassigned': 0,
        'novel_candidate': 0,
    }
    reason_counts = {}

    for rec in records:
        length = len(rec.seq)
        ev = blast_summary.get(rec.id)
        best_v = ev['best_viral'] if ev else None
        v_cov = ev['viral_cov'] if ev else 0.0
        best_c = ev['best_cellular'] if ev else None
        c_cov = ev['cellular_cov'] if ev else 0.0
        v_pident = float(best_v['percent_identity']) if best_v else 0.0
        c_pident = float(best_c['percent_identity']) if best_c else 0.0

        if include_all_contigs:
            category = 'novel_candidate'
            reason = 'all_contigs_requested'
            send = True
        elif best_v and not best_c and v_pident >= known_virus_identity and v_cov >= known_virus_coverage:
            category = 'known_virus'
            reason = 'confident_blast_viral_match'
            send = False
        elif best_c and not best_v and c_pident >= non_viral_identity and c_cov >= non_viral_coverage:
            category = 'known_non_viral'
            reason = f"confident_blast_{best_c['superkingdom'].lower()}_match"
            send = False
        elif length < min_candidate_length:
            category = 'short_unassigned'
            reason = f'below_min_length_{min_candidate_length}bp'
            send = False
        else:
            category = 'novel_candidate'
            send = True
            if not ev or not ev['any_hit']:
                reason = 'no_blast_hit'
            elif best_v and best_c:
                reason = 'conflicting_viral_and_cellular_hits'
            elif best_v:
                reason = 'divergent_or_partial_viral_hit'
            else:
                reason = 'weak_cellular_or_unresolved_hit'

        counts[category] += 1
        reason_counts[reason] = reason_counts.get(reason, 0) + 1
        if send:
            candidate_records.append(rec)

        manifest_rows.append({
            'query_id': rec.id,
            'contig_length': length,
            'triage_category': category,
            'triage_reason': reason,
            'send_to_discovery': 'yes' if send else 'no',
            'best_viral_database': best_v.get('search_database', '') if best_v else '',
            'best_viral_subject': best_v['subject_id'] if best_v else '',
            'best_viral_title': best_v['subject_title'] if best_v else '',
            'best_viral_kingdom': best_v.get('kingdom', '') if best_v else '',
            'best_viral_phylum': best_v.get('phylum', '') if best_v else '',
            'best_viral_class': best_v.get('class', '') if best_v else '',
            'best_viral_order': best_v.get('order', '') if best_v else '',
            'best_viral_family': best_v.get('family', '') if best_v else '',
            'best_viral_genus': best_v.get('genus', '') if best_v else '',
            'best_viral_species': best_v.get('species', '') if best_v else '',
            'best_viral_identity': round(v_pident, 2) if best_v else '',
            'best_viral_union_coverage': v_cov if best_v else '',
            'best_viral_bit_score': best_v['bit_score'] if best_v else '',
            'best_viral_evalue': best_v['evalue'] if best_v else '',
            'best_cellular_superkingdom': best_c['superkingdom'] if best_c else '',
            'best_cellular_identity': round(c_pident, 2) if best_c else '',
            'best_cellular_union_coverage': c_cov if best_c else '',
        })

    with open(f'{prefix}_candidate_contigs.fa', 'w') as fasta_out:
        if candidate_records:
            SeqIO.write(candidate_records, fasta_out, 'fasta')

    with open(f'{prefix}_triage_manifest.tsv', 'w', newline='') as tsv_out:
        writer = csv.DictWriter(tsv_out, fieldnames=TRIAGE_COLUMNS, delimiter='\t')
        writer.writeheader()
        writer.writerows(manifest_rows)

    with open(f'{prefix}_triage_summary.txt', 'w') as summary_out:
        summary_out.write(f'Contig Discovery Triage Summary for {prefix}\n')
        summary_out.write('=' * 52 + '\n')
        summary_out.write(f'Total assembled contigs:              {len(records)}\n')
        summary_out.write(f'Confident known viruses (skipped):    {counts["known_virus"]}\n')
        summary_out.write(f'Confident cellular/host (skipped):    {counts["known_non_viral"]}\n')
        summary_out.write(f'Short contigs < {min_candidate_length} bp (skipped): {counts["short_unassigned"]}\n')
        summary_out.write(f'Sent to novel virus discovery:        {counts["novel_candidate"]}\n\n')
        summary_out.write('Breakdown by triage reason:\n')
        for reason_key, cnt in sorted(reason_counts.items(), key=lambda item: (-item[1], item[0])):
            summary_out.write(f'  - {reason_key}: {cnt}\n')

    print(
        f'Triage complete for {prefix}: {counts["novel_candidate"]}/{len(records)} contigs '
        f'selected for novel-virus discovery ({counts["known_virus"]} known viral and '
        f'{counts["known_non_viral"]} cellular contigs skipped).'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-f', '--fasta_file', required=True)
    parser.add_argument('-b', '--blast_hsps', nargs='*', default=[])
    parser.add_argument('-p', '--prefix', required=True)
    parser.add_argument('--min_candidate_length', type=int, default=500)
    parser.add_argument('--known_virus_identity', type=float, default=80.0)
    parser.add_argument('--known_virus_coverage', type=float, default=50.0)
    parser.add_argument('--non_viral_identity', type=float, default=75.0)
    parser.add_argument('--non_viral_coverage', type=float, default=40.0)
    parser.add_argument('--include_all_contigs', action='store_true')
    args = parser.parse_args()
    triage_contigs(
        args.fasta_file, args.blast_hsps, args.prefix,
        args.min_candidate_length, args.known_virus_identity,
        args.known_virus_coverage, args.non_viral_identity,
        args.non_viral_coverage, args.include_all_contigs,
    )


if __name__ == '__main__':
    main()
