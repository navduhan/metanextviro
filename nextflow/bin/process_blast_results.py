#!/usr/bin/env python3
"""Retain BLAST HSPs and summarize query intervals without discarding local hits."""

import argparse
import csv
import math
from contextlib import closing
from functools import lru_cache
from pathlib import Path

from Bio import SeqIO


# Coordinates are 1-based and inclusive. For BLASTX, query coordinates and
# lengths are nucleotides; alignment_length is amino acids.
COL = [
    'query_id', 'subject_id', 'percent_identity', 'alignment_length', 'mismatches',
    'gap_opens', 'query_start', 'query_end', 'subject_start', 'subject_end',
    'query_coverage', 'evalue', 'bit_score', 'query_length', 'subject_length',
    'subject_title', 'tax_id', 'subject_strand'
]
RANKS = ['superkingdom', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']
HSP_COLUMNS = COL + ['search_database', 'query_coverage_type', 'sequence_length',
                     'query_frame', 'query_strand'] + RANKS + ['taxonomy_status']
SUMMARY_COLUMNS = [
    'query_id', 'subject_id', 'search_database', 'query_length', 'hsp_count',
    'query_regions', 'query_covered_bases', 'query_union_coverage',
    'best_hsp_bit_score', 'min_evalue', 'subject_title', 'tax_id'
] + RANKS + ['taxonomy_status']
BEST_COLUMNS = COL + ['sequence_length'] + RANKS + [
    'sequence', 'search_database', 'query_coverage_type', 'taxonomy_status',
    'query_frame', 'query_strand'
]


class TaxonomyResolver:
    """Reuse one local taxonomy connection and resolve multi-taxid hits by LCA."""

    def __init__(self, dbfile=None):
        from ete3 import NCBITaxa
        from ete3.ncbi_taxonomy.ncbiquery import DEFAULT_TAXADB
        dbfile = str(dbfile or DEFAULT_TAXADB)
        if not Path(dbfile).is_file():
            raise FileNotFoundError(
                f'Local NCBI taxonomy database missing: {dbfile}. '
                'Prepare it separately or provide --taxonomy_db; no automatic download is performed.')
        self.ncbi = NCBITaxa(dbfile=dbfile, update=False)

    @lru_cache(maxsize=100000)
    def lineage(self, tax_id):
        try:
            return tuple(self.ncbi.get_lineage(tax_id))
        except ValueError:
            return ()

    @lru_cache(maxsize=100000)
    def resolve(self, tax_ids):
        result = dict.fromkeys(RANKS, '')
        try:
            ids = sorted({int(value) for value in tax_ids.split(';') if int(value) > 0})
        except ValueError:
            return {**result, 'taxonomy_status': 'invalid_taxid'}
        if not ids:
            return {**result, 'taxonomy_status': 'missing_taxid'}
        lineages = [self.lineage(tax_id) for tax_id in ids]
        if not all(lineages):
            return {**result, 'taxonomy_status': 'unresolved_taxid'}
        common = set(lineages[0]).intersection(*lineages[1:])
        lineage = [tax_id for tax_id in lineages[0] if tax_id in common]
        names = self.ncbi.get_taxid_translator(lineage)
        ranks = self.ncbi.get_rank(lineage)
        for tax_id in lineage:
            rank = ranks.get(tax_id)
            if rank in result:
                result[rank] = names.get(tax_id, '')
        # These roots can be assigned newer ranks such as domain/acellular root.
        for root_id, category in [(10239, 'Viruses'), (2, 'Bacteria'),
                                  (2157, 'Archaea'), (2759, 'Eukaryota')]:
            if root_id in lineage:
                result['superkingdom'] = category
        return {**result, 'taxonomy_status': 'resolved' if len(ids) == 1 else 'lowest_common_ancestor'}


def merge_intervals(intervals):
    """Return the union of inclusive intervals, counting overlaps only once."""
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def hit_order(hit):
    return (-float(hit['bit_score']), float(hit['evalue']), -int(hit['alignment_length']),
            hit['subject_id'], int(hit['query_start']), int(hit['query_end']))


def read_hits(blast_file, sequences):
    lengths = {}
    with open(blast_file, newline='') as handle:
        for line_number, values in enumerate(csv.reader(handle, delimiter='\t'), 1):
            if not values or values[0].startswith('#'):
                continue
            if len(values) != len(COL):
                raise ValueError(f'{blast_file}:{line_number}: expected {len(COL)} columns, got {len(values)}')
            hit = dict(zip(COL, values))
            try:
                if hit['query_id'] not in lengths:
                    lengths[hit['query_id']] = len(sequences[hit['query_id']])
                query_length = int(hit['query_length'])
                start, end = sorted((int(hit['query_start']), int(hit['query_end'])))
                valid = (query_length == lengths[hit['query_id']] and
                         1 <= start <= end <= query_length and
                         int(hit['alignment_length']) > 0 and
                         int(hit['subject_length']) > 0 and
                         0 <= float(hit['percent_identity']) <= 100 and
                         0 <= float(hit['query_coverage']) <= 100 and
                         math.isfinite(float(hit['bit_score'])) and float(hit['bit_score']) >= 0 and
                         math.isfinite(float(hit['evalue'])) and float(hit['evalue']) >= 0)
                if not valid:
                    raise ValueError('invalid coordinates, lengths, or scores')
            except (KeyError, ValueError) as exc:
                raise ValueError(f'{blast_file}:{line_number}: invalid hit: {exc}') from exc
            yield hit, (start, end)


def process_blast_results(blast_file, fasta_file, prefix, suffix, query_coverage_type='qcovs',
                          taxonomy_db=None, strand_field='subject_strand'):
    """Stream HSPs to TSV; keep per-subject intervals and best rows in memory."""
    subjects = {}
    best_hits = {}
    resolver = None
    hsp_count = 0
    # Index sequences rather than repeating full contig strings for every HSP.
    with closing(SeqIO.index(str(fasta_file), 'fasta')) as sequences:
        with open(f'{prefix}_hits_{suffix}.tsv', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=HSP_COLUMNS, delimiter='\t')
            writer.writeheader()
            for hit, interval in read_hits(blast_file, sequences):
                if resolver is None:
                    resolver = TaxonomyResolver(taxonomy_db)
                taxonomy = resolver.resolve(hit['tax_id'])
                row = {**hit, **taxonomy, 'search_database': suffix,
                       'query_coverage_type': query_coverage_type,
                       'sequence_length': int(hit['query_length']), 'query_frame': '',
                       'query_strand': 'plus' if int(hit['query_start']) <= int(hit['query_end']) else 'minus'}
                if strand_field == 'qframe':
                    frame = int(hit['subject_strand'])
                    if frame not in [-3, -2, -1, 1, 2, 3]:
                        raise ValueError(f'Invalid translated query frame: {frame}')
                    row.update(subject_strand='', query_frame=frame,
                               query_strand='plus' if frame > 0 else 'minus')
                writer.writerow(row)
                hsp_count += 1
                query = hit['query_id']
                if query not in best_hits or hit_order(hit) < hit_order(best_hits[query]):
                    best_hits[query] = row
                key = (query, hit['subject_id'])
                if key not in subjects:
                    subjects[key] = {'best': row, 'intervals': [], 'count': 0,
                                     'min_evalue': float(hit['evalue'])}
                subject = subjects[key]
                subject['intervals'].append(interval)
                subject['count'] += 1
                subject['min_evalue'] = min(subject['min_evalue'], float(hit['evalue']))
                if hit_order(hit) < hit_order(subject['best']):
                    subject['best'] = row

        with open(f'{prefix}_hit_summary_{suffix}.tsv', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=SUMMARY_COLUMNS, delimiter='\t')
            writer.writeheader()
            for key in sorted(subjects):
                subject = subjects[key]
                best = subject['best']
                regions = merge_intervals(subject['intervals'])
                covered = sum(end - start + 1 for start, end in regions)
                row = {column: best[column] for column in (
                    ['query_id', 'subject_id', 'search_database', 'query_length',
                     'subject_title', 'tax_id'] + RANKS + ['taxonomy_status'])}
                row.update(hsp_count=subject['count'],
                           query_regions=';'.join(f'{start}-{end}' for start, end in regions),
                           query_covered_bases=covered,
                           query_union_coverage=100.0 * covered / int(best['query_length']),
                           best_hsp_bit_score=best['bit_score'], min_evalue=subject['min_evalue'])
                writer.writerow(row)

        # Compatibility report only: downstream classification uses all HSPs.
        with open(f'{prefix}_best_hits_{suffix}.xls', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=BEST_COLUMNS, delimiter='\t')
            writer.writeheader()
            for query in sorted(best_hits):
                row = {column: best_hits[query][column] for column in BEST_COLUMNS if column != 'sequence'}
                row['sequence'] = str(sequences[query].seq)
                writer.writerow(row)
    print(f'Retained {hsp_count} HSPs, {len(subjects)} query-subject pairs, {len(best_hits)} queries.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-b', '--blast_file', required=True)
    parser.add_argument('-f', '--fasta_file', required=True)
    parser.add_argument('-p', '--prefix', required=True)
    parser.add_argument('-s', '--suffix', required=True)
    parser.add_argument('--taxonomy_db', help='Existing local ETE NCBI taxonomy SQLite database.')
    parser.add_argument('--strand_field', choices=['subject_strand', 'qframe'], default='subject_strand',
                        help='Meaning of the last raw column; protein searches use qframe.')
    parser.add_argument('--query_coverage_type', choices=['qcovs', 'qcovhsp'], default='qcovs',
                        help='Meaning of column 11 in the input (legacy files use qcovs).')
    args = parser.parse_args()
    process_blast_results(args.blast_file, args.fasta_file, args.prefix, args.suffix,
                          args.query_coverage_type, args.taxonomy_db, args.strand_field)


if __name__ == '__main__':
    main()
