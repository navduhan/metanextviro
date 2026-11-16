#!/usr/bin/env python3
"""Scan candidate contigs for 6-frame viral ORFs, coding density, DTR/ITR, and complexity/EVE signals."""

import argparse
import csv
import math
import os
from collections import Counter
from pathlib import Path

from Bio import SeqIO
from Bio.Seq import Seq

ARCH_COLUMNS = [
    'query_id', 'contig_length', 'orf_count', 'max_orf_aa', 'coding_bases',
    'coding_density', 'dominant_strand_fraction', 'min_frame_stops_per_kb',
    'terminal_repeat_type', 'terminal_repeat_length', 'gc_percent',
    'n_fraction', 'kmer_entropy', 'low_complexity_flag', 'fragmented_orfs_flag'
]

START_CODONS = {'ATG', 'GTG', 'TTG'}
STOP_CODONS = {'TAA', 'TAG', 'TGA'}


def reverse_complement_str(seq_str):
    return str(Seq(seq_str).reverse_complement())


def compute_sequence_qc(seq_upper):
    length = len(seq_upper)
    if length == 0:
        return 0.0, 0.0, 0.0
    gc_count = seq_upper.count('G') + seq_upper.count('C')
    n_count = seq_upper.count('N')
    valid_bases = max(1, length - n_count)
    gc_pct = round(100.0 * gc_count / valid_bases, 2)
    n_frac = round(n_count / length, 4)

    kmers = [seq_upper[i:i + 3] for i in range(max(0, length - 2))
             if set(seq_upper[i:i + 3]) <= {'A', 'C', 'G', 'T'}]
    if not kmers:
        return gc_pct, n_frac, 0.0
    counts = Counter(kmers)
    total = len(kmers)
    entropy = -sum((c / total) * math.log2(c / total) for c in counts.values())
    norm_entropy = round(entropy / 6.0, 4)  # log2(64) = 6.0
    return gc_pct, n_frac, norm_entropy


def detect_terminal_repeats(seq_upper, min_repeat=20, max_repeat=500):
    """Detect exact Direct Terminal Repeats (DTR) or Inverted Terminal Repeats (ITR)."""
    length = len(seq_upper)
    limit = min(max_repeat, length // 2)
    if limit < min_repeat:
        return 'none', 0

    best_dtr = 0
    for rlen in range(limit, min_repeat - 1, -1):
        prefix = seq_upper[:rlen]
        if 'N' in prefix:
            continue
        if prefix == seq_upper[length - rlen:]:
            best_dtr = rlen
            break
    if best_dtr >= min_repeat:
        return 'DTR', best_dtr

    rc_suffix_window = reverse_complement_str(seq_upper[length - limit:])
    # For an ITR of length rlen, prefix[:rlen] matches reverse_complement(seq[length - rlen:]),
    # which is the prefix of rc_suffix_window[:rlen]!
    best_itr = 0
    for rlen in range(limit, min_repeat - 1, -1):
        prefix = seq_upper[:rlen]
        if 'N' in prefix:
            continue
        if prefix == rc_suffix_window[:rlen]:
            best_itr = rlen
            break
    if best_itr >= min_repeat:
        return 'ITR', best_itr

    return 'none', 0


def translate_codons(nuc_seq):
    aa = []
    for i in range(0, len(nuc_seq) - 2, 3):
        codon = nuc_seq[i:i + 3]
        if set(codon) <= {'A', 'C', 'G', 'T'}:
            res = str(Seq(codon).translate(table=1))
            aa.append(res)
        else:
            aa.append('X')
    return ''.join(aa)


def find_orfs_6frame(seq_upper, min_orf_aa=60):
    """Find viral ORFs across all 6 frames (including 5'/3' partial edge ORFs) and stop density."""
    length = len(seq_upper)
    rc_upper = reverse_complement_str(seq_upper)
    orfs = []
    frame_stop_rates = []

    for strand, template in [('+', seq_upper), ('-', rc_upper)]:
        for frame in range(3):
            stops_in_frame = 0
            run_start_nt = frame  # Allow 5'-partial ORF starting at contig edge
            first_start_codon_nt = frame
            saw_start = True  # Edge-open until first stop codon

            pos = frame
            while pos + 3 <= length:
                codon = template[pos:pos + 3]
                if codon in START_CODONS and not saw_start:
                    saw_start = True
                    first_start_codon_nt = pos
                elif codon in STOP_CODONS:
                    stops_in_frame += 1
                    if saw_start:
                        orf_nt_len = pos - first_start_codon_nt
                        aa_len = orf_nt_len // 3
                        if aa_len >= min_orf_aa:
                            prot = translate_codons(template[first_start_codon_nt:pos])
                            if strand == '+':
                                g_start = first_start_codon_nt + 1
                                g_end = pos
                            else:
                                g_start = length - pos + 1
                                g_end = length - first_start_codon_nt
                            orfs.append({
                                'start': min(g_start, g_end),
                                'end': max(g_start, g_end),
                                'strand': strand,
                                'frame': frame + 1 if strand == '+' else -(frame + 1),
                                'aa_len': aa_len,
                                'protein': prot,
                            })
                    saw_start = False
                    run_start_nt = pos + 3
                pos += 3

            # Handle 3'-partial ORF running off the end of the contig
            if saw_start:
                usable_end = pos
                orf_nt_len = usable_end - first_start_codon_nt
                aa_len = orf_nt_len // 3
                if aa_len >= min_orf_aa:
                    prot = translate_codons(template[first_start_codon_nt:usable_end])
                    if strand == '+':
                        g_start = first_start_codon_nt + 1
                        g_end = usable_end
                    else:
                        g_start = length - usable_end + 1
                        g_end = length - first_start_codon_nt
                    orfs.append({
                        'start': min(g_start, g_end),
                        'end': max(g_start, g_end),
                        'strand': strand,
                        'frame': frame + 1 if strand == '+' else -(frame + 1),
                        'aa_len': aa_len,
                        'protein': prot,
                    })
            frame_stop_rates.append(1000.0 * stops_in_frame / max(1, length))

    # Select non-heavily-overlapping primary ORFs (allow <= 60 bp viral gene overlap)
    orfs.sort(key=lambda item: (-item['aa_len'], item['start'], item['end']))
    selected = []
    for cand in orfs:
        c_len = cand['end'] - cand['start'] + 1
        overlaps_existing = False
        for kept in selected:
            ov = min(cand['end'], kept['end']) - max(cand['start'], kept['start']) + 1
            if ov > 60 and ov > 0.25 * c_len:
                overlaps_existing = True
                break
        if not overlaps_existing:
            selected.append(cand)

    selected.sort(key=lambda item: (item['start'], -item['aa_len']))
    min_stops_kb = round(min(frame_stop_rates) if frame_stop_rates else 0.0, 2)
    return selected, min_stops_kb


def merge_orf_spans(orfs):
    if not orfs:
        return 0
    merged = []
    for start, end in sorted((o['start'], o['end']) for o in orfs):
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return sum(e - s + 1 for s, e in merged)


def scan_viral_architecture(fasta_file, prefix, min_orf_aa=60):
    arch_rows = []
    orf_fasta_lines = []

    if os.path.exists(fasta_file) and os.path.getsize(fasta_file) > 0:
        with open(fasta_file) as fasta_handle:
            records = list(SeqIO.parse(fasta_handle, 'fasta'))
        for rec in records:
            seq_upper = str(rec.seq).upper()
            length = len(seq_upper)
            gc_pct, n_frac, entropy = compute_sequence_qc(seq_upper)
            rep_type, rep_len = detect_terminal_repeats(seq_upper)
            orfs, min_stops_kb = find_orfs_6frame(seq_upper, min_orf_aa=min_orf_aa)

            coding_bases = merge_orf_spans(orfs)
            coding_density = round(100.0 * coding_bases / max(1, length), 2)
            max_orf_aa = max((o['aa_len'] for o in orfs), default=0)

            if orfs:
                plus_aa = sum(o['aa_len'] for o in orfs if o['strand'] == '+')
                total_aa = max(1, sum(o['aa_len'] for o in orfs))
                dom_strand = round(max(plus_aa, total_aa - plus_aa) / total_aa, 3)
            else:
                dom_strand = 0.0

            low_complexity = entropy < 0.65 or n_frac > 0.10
            fragmented_orfs = (length >= 1500 and (coding_density < 40.0 or max_orf_aa < 90) and min_stops_kb > 8.0)

            for idx, orf in enumerate(orfs, 1):
                orf_id = f"{rec.id}_orf{idx}"
                header = (
                    f">{orf_id} contig={rec.id} start={orf['start']} end={orf['end']} "
                    f"strand={orf['strand']} frame={orf['frame']} length_aa={orf['aa_len']}"
                )
                orf_fasta_lines.append(f"{header}\n{orf['protein']}\n")

            arch_rows.append({
                'query_id': rec.id,
                'contig_length': length,
                'orf_count': len(orfs),
                'max_orf_aa': max_orf_aa,
                'coding_bases': coding_bases,
                'coding_density': coding_density,
                'dominant_strand_fraction': dom_strand,
                'min_frame_stops_per_kb': min_stops_kb,
                'terminal_repeat_type': rep_type,
                'terminal_repeat_length': rep_len,
                'gc_percent': gc_pct,
                'n_fraction': n_frac,
                'kmer_entropy': entropy,
                'low_complexity_flag': 'yes' if low_complexity else 'no',
                'fragmented_orfs_flag': 'yes' if fragmented_orfs else 'no',
            })

    arch_rows.sort(key=lambda r: (-r['coding_density'], -r['max_orf_aa'], -r['contig_length'], r['query_id']))

    with open(f'{prefix}_architecture_metrics.tsv', 'w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=ARCH_COLUMNS, delimiter='\t')
        writer.writeheader()
        writer.writerows(arch_rows)

    with open(f'{prefix}_candidate_orfs.faa', 'w') as faa_out:
        faa_out.writelines(orf_fasta_lines)

    print(f'Scanned {len(arch_rows)} candidate contigs; wrote {len(orf_fasta_lines)} predicted viral ORFs.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-f', '--fasta_file', required=True)
    parser.add_argument('-p', '--prefix', required=True)
    parser.add_argument('--min_orf_aa', type=int, default=60)
    args = parser.parse_args()
    scan_viral_architecture(args.fasta_file, args.prefix, args.min_orf_aa)


if __name__ == '__main__':
    main()
