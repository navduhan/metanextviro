#!/usr/bin/env python3
"""Parse HMMER domtblout, DIAMOND viral protein, and Foldseek structural hits into sorted TSVs."""

import argparse
import csv
import os
import re

HMM_COLUMNS = [
    'query_id', 'orf_id', 'hmm_name', 'hmm_accession', 'hallmark_category',
    'evalue', 'domain_score', 'full_score', 'orf_length_aa', 'hmm_length',
    'env_start', 'env_end', 'orf_coverage_pct', 'hmm_description'
]

VP_COLUMNS = [
    'query_id', 'orf_id', 'subject_id', 'percent_identity', 'alignment_length',
    'orf_coverage_pct', 'evalue', 'bit_score', 'orf_length_aa', 'subject_length',
    'subject_title'
]

FOLDSEEK_COLUMNS = [
    'query_id', 'orf_id', 'target_id', 'probability', 'bit_score', 'evalue',
    'percent_identity', 'alignment_length', 'target_header'
]

ORF_SUFFIX_RE = re.compile(r'^(.+)_orf\d+$')


def orf_to_contig(orf_id, description=''):
    match = re.search(r'\bcontig=([^\s]+)', description or '')
    if match:
        return match.group(1)
    suffix_match = ORF_SUFFIX_RE.match(orf_id)
    if suffix_match:
        return suffix_match.group(1)
    return orf_id


def classify_hallmark(name, desc):
    text = f'{name} {desc}'.lower()
    if any(k in text for k in ('rdrp', 'rna-dependent rna polymerase', 'rna_dep_rnapol', 'pol_rna', 'rvt_')):
        return 'RdRp'
    if any(k in text for k in ('capsid', 'coat', 'cp_', 'mcp', 'virion', 'jelly-roll', 'hk97')):
        return 'Capsid_Coat'
    if any(k in text for k in ('terminase', 'terl', 'portal')):
        return 'Portal_Terminase'
    if any(k in text for k in ('helicase', 'rep_', 'repa', 'rolling-circle', 'ns1', 'sf3')):
        return 'Helicase_Rep'
    if any(k in text for k in ('protease', 'peptidase', '3c-like')):
        return 'Protease'
    return 'Viral_HMM'


def parse_hmmer_domtblout(input_path, output_path):
    rows = []
    if os.path.exists(input_path) and os.path.getsize(input_path) > 0:
        with open(input_path) as handle:
            for line in handle:
                if not line.strip() or line.startswith('#'):
                    continue
                parts = line.rstrip('\n').split(None, 22)
                if len(parts) < 22:
                    continue
                orf_id = parts[0]
                orf_len = int(parts[2])
                hmm_name = parts[3]
                hmm_acc = '' if parts[4] == '-' else parts[4]
                hmm_len = int(parts[5])
                i_evalue = float(parts[12])
                full_score = float(parts[7])
                dom_score = float(parts[13])
                env_from = int(parts[19])
                env_to = int(parts[20])
                desc = parts[22].strip() if len(parts) > 22 and parts[22] != '-' else ''
                contig_id = orf_to_contig(orf_id, desc)
                cov_pct = round(100.0 * max(0, env_to - env_from + 1) / max(1, orf_len), 2)
                rows.append({
                    'query_id': contig_id,
                    'orf_id': orf_id,
                    'hmm_name': hmm_name,
                    'hmm_accession': hmm_acc,
                    'hallmark_category': classify_hallmark(hmm_name, desc),
                    'evalue': i_evalue,
                    'domain_score': dom_score,
                    'full_score': full_score,
                    'orf_length_aa': orf_len,
                    'hmm_length': hmm_len,
                    'env_start': env_from,
                    'env_end': env_to,
                    'orf_coverage_pct': cov_pct,
                    'hmm_description': desc,
                })

    rows.sort(key=lambda r: (-float(r['domain_score']), float(r['evalue']), -float(r['orf_coverage_pct']), r['query_id']))
    with open(output_path, 'w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=HMM_COLUMNS, delimiter='\t')
        writer.writeheader()
        writer.writerows(rows)


def parse_viral_protein_tsv(input_path, output_path):
    raw_cols = [
        'orf_id', 'subject_id', 'percent_identity', 'alignment_length', 'mismatches',
        'gap_opens', 'qstart', 'qend', 'sstart', 'send', 'orf_coverage_pct',
        'evalue', 'bit_score', 'orf_length_aa', 'subject_length', 'subject_title'
    ]
    rows = []
    if os.path.exists(input_path) and os.path.getsize(input_path) > 0:
        with open(input_path, newline='') as handle:
            for vals in csv.reader(handle, delimiter='\t'):
                if not vals or vals[0].startswith('#') or len(vals) < 16:
                    continue
                rec = dict(zip(raw_cols, vals[:16]))
                rows.append({
                    'query_id': orf_to_contig(rec['orf_id']),
                    'orf_id': rec['orf_id'],
                    'subject_id': rec['subject_id'],
                    'percent_identity': float(rec['percent_identity']),
                    'alignment_length': int(rec['alignment_length']),
                    'orf_coverage_pct': float(rec['orf_coverage_pct']),
                    'evalue': float(rec['evalue']),
                    'bit_score': float(rec['bit_score']),
                    'orf_length_aa': int(rec['orf_length_aa']),
                    'subject_length': int(rec['subject_length']),
                    'subject_title': rec['subject_title'],
                })

    rows.sort(key=lambda r: (-r['bit_score'], r['evalue'], -r['alignment_length'], r['query_id']))
    with open(output_path, 'w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=VP_COLUMNS, delimiter='\t')
        writer.writeheader()
        writer.writerows(rows)


def parse_foldseek_tsv(input_path, output_path):
    raw_cols = [
        'orf_id', 'target_id', 'percent_identity', 'alignment_length',
        'qstart', 'qend', 'tstart', 'tend', 'evalue', 'bit_score', 'probability', 'target_header'
    ]
    rows = []
    if os.path.exists(input_path) and os.path.getsize(input_path) > 0:
        with open(input_path, newline='') as handle:
            for vals in csv.reader(handle, delimiter='\t'):
                if not vals or vals[0].startswith('#') or len(vals) < 12:
                    continue
                rec = dict(zip(raw_cols, vals[:12]))
                rows.append({
                    'query_id': orf_to_contig(rec['orf_id']),
                    'orf_id': rec['orf_id'],
                    'target_id': rec['target_id'],
                    'probability': float(rec['probability']),
                    'bit_score': float(rec['bit_score']),
                    'evalue': float(rec['evalue']),
                    'percent_identity': float(rec['percent_identity']),
                    'alignment_length': int(rec['alignment_length']),
                    'target_header': rec['target_header'],
                })

    rows.sort(key=lambda r: (-r['probability'], -r['bit_score'], r['evalue'], r['query_id']))
    with open(output_path, 'w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=FOLDSEEK_COLUMNS, delimiter='\t')
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', required=True, choices=['hmm', 'viral_protein', 'foldseek'])
    parser.add_argument('-i', '--input', required=True)
    parser.add_argument('-o', '--output', required=True)
    args = parser.parse_args()
    if args.mode == 'hmm':
        parse_hmmer_domtblout(args.input, args.output)
    elif args.mode == 'viral_protein':
        parse_viral_protein_tsv(args.input, args.output)
    else:
        parse_foldseek_tsv(args.input, args.output)


if __name__ == '__main__':
    main()
