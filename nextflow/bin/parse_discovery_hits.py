#!/usr/bin/env python3
"""Parse HMMER, DIAMOND viral protein, and Foldseek hits with full ICTV taxonomic lineages."""

import argparse
import csv
import os
import re
import sys
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from process_blast_results import RANKS, TaxonomyResolver  # noqa: E402

TAX_RANKS = ['kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']

HMM_COLUMNS = [
    'query_id', 'orf_id', 'hmm_name', 'hmm_accession', 'hallmark_category',
    'evalue', 'domain_score', 'full_score', 'orf_length_aa', 'hmm_length',
    'env_start', 'env_end', 'orf_coverage_pct'
] + TAX_RANKS + ['hmm_description']

VP_COLUMNS = [
    'query_id', 'orf_id', 'subject_id', 'percent_identity', 'alignment_length',
    'orf_coverage_pct', 'evalue', 'bit_score', 'orf_length_aa', 'subject_length',
    'tax_id'
] + TAX_RANKS + ['taxonomy_status', 'subject_title']

FOLDSEEK_COLUMNS = [
    'query_id', 'orf_id', 'target_id', 'probability', 'bit_score', 'evalue',
    'percent_identity', 'alignment_length', 'target_header'
]

ORF_SUFFIX_RE = re.compile(r'^(.+)_orf\d+$')
BRACKET_ORG_RE = re.compile(r'\[([^\[\]]+)\]\s*$')

# Curated ICTV parent hierarchy for common viral clades embedded in RdRp/VOG/Pfam HMM names
ICTV_CLADE_HINTS = {
    'orthornavirae': {'kingdom': 'Orthornavirae'},
    'pararnavirae': {'kingdom': 'Pararnavirae'},
    'shotokuvirae': {'kingdom': 'Shotokuvirae'},
    'heunggongvirae': {'kingdom': 'Heunggongvirae'},
    'bamfordvirae': {'kingdom': 'Bamfordvirae'},
    'angermeiervirae': {'kingdom': 'Sangervirae'},
    'pisuviricota': {'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota'},
    'kitrinoviricota': {'kingdom': 'Orthornavirae', 'phylum': 'Kitrinoviricota'},
    'lenarviricota': {'kingdom': 'Orthornavirae', 'phylum': 'Lenarviricota'},
    'negarnaviricota': {'kingdom': 'Orthornavirae', 'phylum': 'Negarnaviricota'},
    'duplornaviricota': {'kingdom': 'Orthornavirae', 'phylum': 'Duplornaviricota'},
    'cressdnaviricota': {'kingdom': 'Shotokuvirae', 'phylum': 'Cressdnaviricota'},
    'uroviricota': {'kingdom': 'Heunggongvirae', 'phylum': 'Uroviricota'},
    'caudoviricetes': {'kingdom': 'Heunggongvirae', 'phylum': 'Uroviricota', 'class': 'Caudoviricetes'},
    'picornavirales': {'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota', 'class': 'Pisoniviricetes', 'order': 'Picornavirales'},
    'nidovirales': {'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota', 'class': 'Pisoniviricetes', 'order': 'Nidovirales'},
    'sobivirales': {'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota', 'order': 'Sobelivirales'},
    'martellivirales': {'kingdom': 'Orthornavirae', 'phylum': 'Kitrinoviricota', 'class': 'Alsuviricetes', 'order': 'Martellivirales'},
    'tymovirales': {'kingdom': 'Orthornavirae', 'phylum': 'Kitrinoviricota', 'class': 'Alsuviricetes', 'order': 'Tymovirales'},
    'amarillovirales': {'kingdom': 'Orthornavirae', 'phylum': 'Kitrinoviricota', 'class': 'Flasuviricetes', 'order': 'Amarillovirales'},
    'tolivirales': {'kingdom': 'Orthornavirae', 'phylum': 'Kitrinoviricota', 'class': 'Tolucaviricetes', 'order': 'Tolivirales'},
    'mononegavirales': {'kingdom': 'Orthornavirae', 'phylum': 'Negarnaviricota', 'class': 'Monjiviricetes', 'order': 'Mononegavirales'},
    'bunyavirales': {'kingdom': 'Orthornavirae', 'phylum': 'Negarnaviricota', 'class': 'Ellioviricetes', 'order': 'Bunyavirales'},
    'articulavirales': {'kingdom': 'Orthornavirae', 'phylum': 'Negarnaviricota', 'class': 'Insthoviricetes', 'order': 'Articulavirales'},
    'reovirales': {'kingdom': 'Orthornavirae', 'phylum': 'Duplornaviricota', 'class': 'Resentoviricetes', 'order': 'Reovirales'},
    'ghabrivirales': {'kingdom': 'Orthornavirae', 'phylum': 'Duplornaviricota', 'class': 'Chrymotiviricetes', 'order': 'Ghabrivirales'},
    'durnavirales': {'kingdom': 'Orthornavirae', 'phylum': 'Pisuviricota', 'class': 'Duplopiviricetes', 'order': 'Durnavirales'},
    'herpesvirales': {'kingdom': 'Heunggongvirae', 'phylum': 'Peploviricota', 'class': 'Herviviricetes', 'order': 'Herpesvirales'},
    'rowavirales': {'kingdom': 'Bamfordvirae', 'phylum': 'Preplasmiviricota', 'class': 'Tectiliviricetes', 'order': 'Rowavirales'},
    'chitovirales': {'kingdom': 'Bamfordvirae', 'phylum': 'Nucleocytoviricota', 'class': 'Pokkesviricetes', 'order': 'Chitovirales'},
}


class FlexibleTaxonomyHelper:
    """Resolve taxids, organism names, and semicolon LCA strings using optional local ETE3 DB."""

    def __init__(self, taxonomy_db=None):
        self.resolver = None
        if taxonomy_db and os.path.isfile(taxonomy_db):
            self.resolver = TaxonomyResolver(taxonomy_db)
        else:
            default_ete = Path.home() / '.etetoolkit/taxa.sqlite'
            if default_ete.is_file():
                try:
                    self.resolver = TaxonomyResolver(str(default_ete))
                except Exception:
                    self.resolver = None

    @lru_cache(maxsize=50000)
    def by_taxid(self, tax_id_str):
        empty = {r: '' for r in TAX_RANKS}
        if not self.resolver or not tax_id_str or str(tax_id_str).strip() in ('', '0', 'N/A'):
            return {**empty, 'taxonomy_status': 'missing_taxid'}
        resolved = self.resolver.resolve(str(tax_id_str).strip())
        return {**{r: resolved.get(r, '') for r in TAX_RANKS}, 'taxonomy_status': resolved['taxonomy_status']}

    @lru_cache(maxsize=50000)
    def by_name(self, taxon_name):
        empty = {r: '' for r in TAX_RANKS}
        if not self.resolver or not taxon_name:
            return {**empty, 'taxonomy_status': 'unresolved_name'}
        name_map = self.resolver.ncbi.get_name_translator([taxon_name])
        if not name_map and ' ' in taxon_name:
            # Try stripping strain suffix after species binomial/trinomial
            tokens = taxon_name.split()
            for length in (3, 2):
                if len(tokens) >= length:
                    name_map = self.resolver.ncbi.get_name_translator([' '.join(tokens[:length])])
                    if name_map:
                        break
        if not name_map:
            return {**empty, 'taxonomy_status': 'unresolved_name'}
        taxid = next(iter(name_map.values()))[0]
        return self.by_taxid(str(taxid))

    def from_lca_string_or_text(self, lca_lineage='', text=''):
        result = {r: '' for r in TAX_RANKS}
        # 1. If semicolon lineage is supplied (e.g. VOGDB vog.lca.tsv or ICTV string), resolve deepest known taxon
        if lca_lineage:
            parts = [p.strip() for p in lca_lineage.split(';') if p.strip()]
            if self.resolver:
                for taxon in reversed(parts):
                    resolved = self.by_name(taxon)
                    if any(resolved[r] for r in TAX_RANKS):
                        return resolved
            # Pattern-based rank inference on ICTV suffixes (-virae, -viricota, -viricetes, -virales, -viridae, -virus)
            for p in parts:
                pl = p.lower()
                if pl in ICTV_CLADE_HINTS:
                    result.update(ICTV_CLADE_HINTS[pl])
                elif pl.endswith('virae'):
                    result['kingdom'] = p
                elif pl.endswith('viricota'):
                    result['phylum'] = p
                elif pl.endswith('viricetes'):
                    result['class'] = p
                elif pl.endswith('virales'):
                    result['order'] = p
                elif pl.endswith('viridae'):
                    result['family'] = p
                elif pl.endswith('virus') and not pl.endswith('viruses') and ' ' not in p:
                    result['genus'] = p
            if any(result.values()):
                return {**result, 'taxonomy_status': 'lca_lineage'}

        # 2. Scan HMM name/description tokens for ICTV clade or family/order names
        tokens = re.findall(r'[A-Za-z0-9_-]{4,}', text or '')
        for tok in tokens:
            tl = tok.lower()
            if tl in ICTV_CLADE_HINTS:
                result.update(ICTV_CLADE_HINTS[tl])
            elif tl.endswith('viridae') or tl.endswith('virales') or tl.endswith('viricetes') or tl.endswith('viricota') or tl.endswith('virae'):
                if self.resolver:
                    resolved = self.by_name(tok)
                    if any(resolved[r] for r in TAX_RANKS):
                        return resolved
                if tl.endswith('viridae'):
                    result['family'] = tok
                elif tl.endswith('virales'):
                    result['order'] = tok
                elif tl.endswith('viricetes'):
                    result['class'] = tok
                elif tl.endswith('viricota'):
                    result['phylum'] = tok
                elif tl.endswith('virae'):
                    result['kingdom'] = tok
        return {**result, 'taxonomy_status': 'clade_inferred' if any(result.values()) else 'unassigned'}


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


def load_hmm_taxonomy_table(hmm_taxonomy_path):
    """Load optional HMM -> (description, lca_lineage) mapping (e.g. built from VOGDB)."""
    mapping = {}
    if not hmm_taxonomy_path or not os.path.exists(hmm_taxonomy_path) or os.path.getsize(hmm_taxonomy_path) == 0:
        return mapping
    with open(hmm_taxonomy_path, newline='') as handle:
        for row in csv.DictReader(handle, delimiter='\t'):
            name = (row.get('hmm_name') or row.get('#GroupName') or row.get('GroupName') or '').strip()
            if name:
                mapping[name] = {
                    'description': (row.get('description') or row.get('ConsensusFunctionalDescription') or '').strip(),
                    'lca_lineage': (row.get('lca_lineage') or row.get('LastCommonAncestor') or '').strip(),
                }
    return mapping


def parse_hmmer_domtblout(input_path, output_path, taxonomy_db=None, hmm_taxonomy_path=None):
    tax_helper = FlexibleTaxonomyHelper(taxonomy_db)
    hmm_meta = load_hmm_taxonomy_table(hmm_taxonomy_path)
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
                full_score = float(parts[7])
                i_evalue = float(parts[12])
                dom_score = float(parts[13])
                env_from = int(parts[19])
                env_to = int(parts[20])
                raw_desc = parts[22].strip() if len(parts) > 22 and parts[22] != '-' else ''
                meta = hmm_meta.get(hmm_name, {})
                desc = meta.get('description') or raw_desc
                lca_str = meta.get('lca_lineage', '')

                contig_id = orf_to_contig(orf_id, raw_desc)
                cov_pct = round(100.0 * max(0, env_to - env_from + 1) / max(1, orf_len), 2)
                tax_info = tax_helper.from_lca_string_or_text(lca_str, f'{hmm_name} {hmm_acc} {desc}')

                row = {
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
                }
                for rank in TAX_RANKS:
                    row[rank] = tax_info.get(rank, '')
                rows.append(row)

    rows.sort(key=lambda r: (-float(r['domain_score']), float(r['evalue']), -float(r['orf_coverage_pct']), r['query_id']))
    with open(output_path, 'w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=HMM_COLUMNS, delimiter='\t')
        writer.writeheader()
        writer.writerows(rows)


def parse_viral_protein_tsv(input_path, output_path, taxonomy_db=None):
    raw_cols = [
        'orf_id', 'subject_id', 'percent_identity', 'alignment_length', 'mismatches',
        'gap_opens', 'qstart', 'qend', 'sstart', 'send', 'orf_coverage_pct',
        'evalue', 'bit_score', 'orf_length_aa', 'subject_length', 'subject_title', 'tax_id'
    ]
    tax_helper = FlexibleTaxonomyHelper(taxonomy_db)
    rows = []
    if os.path.exists(input_path) and os.path.getsize(input_path) > 0:
        with open(input_path, newline='') as handle:
            for vals in csv.reader(handle, delimiter='\t'):
                if not vals or vals[0].startswith('#') or len(vals) < 16:
                    continue
                padded = vals[:17] if len(vals) >= 17 else vals[:16] + ['']
                rec = dict(zip(raw_cols, padded))
                tax_id_str = rec['tax_id'].strip()
                tax_info = tax_helper.by_taxid(tax_id_str)
                if tax_info['taxonomy_status'] != 'resolved' and tax_info['taxonomy_status'] != 'lowest_common_ancestor':
                    org_match = BRACKET_ORG_RE.search(rec['subject_title'])
                    if org_match:
                        by_org = tax_helper.by_name(org_match.group(1).strip())
                        if any(by_org[r] for r in TAX_RANKS):
                            tax_info = by_org
                    if not any(tax_info[r] for r in TAX_RANKS):
                        tax_info = tax_helper.from_lca_string_or_text('', rec['subject_title'])

                row = {
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
                    'tax_id': tax_id_str,
                    'taxonomy_status': tax_info.get('taxonomy_status', ''),
                    'subject_title': rec['subject_title'],
                }
                for rank in TAX_RANKS:
                    row[rank] = tax_info.get(rank, '')
                rows.append(row)

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
    parser.add_argument('--taxonomy_db', help='Optional local ETE3 NCBI taxonomy SQLite DB')
    parser.add_argument('--hmm_taxonomy', help='Optional HMM-to-LCA taxonomy TSV (e.g. from VOGDB)')
    args = parser.parse_args()
    if args.mode == 'hmm':
        parse_hmmer_domtblout(args.input, args.output, args.taxonomy_db, args.hmm_taxonomy)
    elif args.mode == 'viral_protein':
        parse_viral_protein_tsv(args.input, args.output, args.taxonomy_db)
    else:
        parse_foldseek_tsv(args.input, args.output)


if __name__ == '__main__':
    main()
