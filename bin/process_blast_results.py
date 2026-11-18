#!/usr/bin/env python3
# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""Merges multi-HSP BLASTN, BLASTX, and DIAMOND intervals per contig using exact coordinate union, resolves NCBI lowest common ancestor lineages, and exports descending-sorted TSV and XLSX tables."""

import argparse
import csv
import math
import re
import zipfile
from contextlib import closing
from functools import lru_cache
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

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
ORDERED_TAX_RANKS = ['superkingdom', 'family', 'genus', 'species', 'kingdom', 'phylum', 'class', 'order']

HSP_COLUMNS = [
    'query_id', 'query_length', 'alignment_length', 'percent_identity', 'query_coverage',
    'bit_score', 'evalue', 'subject_id', 'subject_title'
] + ORDERED_TAX_RANKS + [
    'tax_id', 'taxonomy_status', 'query_start', 'query_end', 'subject_start', 'subject_end',
    'subject_length', 'query_strand', 'query_frame', 'subject_strand', 'mismatches',
    'gap_opens', 'search_database', 'query_coverage_type'
]

SUMMARY_COLUMNS = [
    'query_id', 'query_length', 'subject_rank', 'subject_id', 'subject_title',
    'hsp_count', 'best_hsp_alignment_length', 'best_hsp_percent_identity',
    'query_covered_bases', 'query_union_coverage', 'best_hsp_bit_score', 'min_evalue',
    'query_regions'
] + ORDERED_TAX_RANKS + ['tax_id', 'taxonomy_status', 'search_database']

BEST_COLUMNS = [
    'query_id', 'query_length', 'alignment_length', 'percent_identity',
    'query_coverage', 'query_union_coverage', 'hsp_count', 'bit_score', 'evalue',
    'subject_id', 'subject_title'
] + ORDERED_TAX_RANKS + [
    'tax_id', 'taxonomy_status', 'query_regions', 'query_start', 'query_end',
    'subject_start', 'subject_end', 'subject_length', 'query_strand', 'query_frame',
    'subject_strand', 'mismatches', 'gap_opens', 'search_database', 'query_coverage_type',
    'sequence'
]

INT_COLUMNS = {
    'query_length', 'alignment_length', 'hsp_count', 'query_start', 'query_end',
    'subject_start', 'subject_end', 'subject_length', 'mismatches', 'gap_opens',
    'subject_rank', 'best_hsp_alignment_length', 'query_covered_bases'
}
PCT_COLUMNS = {'percent_identity', 'query_coverage', 'query_union_coverage', 'best_hsp_percent_identity'}
SCORE_COLUMNS = {'bit_score', 'best_hsp_bit_score'}
EVALUE_COLUMNS = {'evalue', 'min_evalue'}
WIDTH_LIMITS = {
    'query_id': (18, 38),
    'subject_id': (14, 24),
    'subject_title': (22, 46),
    'superkingdom': (14, 18),
    'family': (14, 26),
    'genus': (14, 26),
    'species': (16, 32),
    'kingdom': (12, 20),
    'phylum': (12, 22),
    'class': (12, 22),
    'order': (12, 24),
    'tax_id': (10, 18),
    'taxonomy_status': (18, 24),
    'query_regions': (16, 24),
    'sequence': (28, 28),
}
EXCEL_MAX_CHARS = 32767
ILLEGAL_XML_RE = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f]')


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
    """Rank HSPs within a single query: strongest bit score first, then E-value and length."""
    return (
        -float(hit['bit_score']),
        float(hit['evalue']),
        -int(hit['alignment_length']),
        -float(hit['percent_identity']),
        hit['subject_id'],
        int(hit['query_start']),
        int(hit['query_end']),
    )


def best_row_order(row):
    """Sort queries across the final table in descending alignment length and match strength."""
    return (
        -int(row['alignment_length']),
        -float(row['bit_score']),
        float(row['evalue']),
        -float(row['percent_identity']),
        -int(row['query_length']),
        row['query_id'],
    )


def subject_summary_order(subject_entry, query_length):
    """Sort candidate subjects within one query from strongest to weakest."""
    best = subject_entry['best']
    regions = subject_entry['regions']
    covered = subject_entry['covered']
    return (
        -float(best['bit_score']),
        float(subject_entry['min_evalue']),
        -covered,
        -int(best['alignment_length']),
        -float(best['percent_identity']),
        best['subject_id'],
        regions[0][0] if regions else 0,
        query_length,
    )


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


def excel_col_letter(index):
    letters = []
    while index > 0:
        index, rem = divmod(index - 1, 26)
        letters.append(chr(65 + rem))
    return ''.join(reversed(letters))


def sanitize_excel_text(value, is_sequence=False):
    text = ILLEGAL_XML_RE.sub(' ; ', str(value))
    if len(text) <= EXCEL_MAX_CHARS:
        return text
    if is_sequence:
        suffix = f'...[truncated at Excel {EXCEL_MAX_CHARS}-char limit; full {len(text)} bp in TSV/FASTA]'
        return text[:EXCEL_MAX_CHARS - len(suffix)] + suffix
    return text[:EXCEL_MAX_CHARS - 3] + '...'


def typed_excel_value(col, raw_value, int_cols=INT_COLUMNS, pct_cols=PCT_COLUMNS,
                      score_cols=SCORE_COLUMNS, evalue_cols=EVALUE_COLUMNS):
    if raw_value == '' or raw_value is None:
        return '', 'text'
    if col in int_cols or col == 'query_frame':
        return int(raw_value), 'int'
    if col in pct_cols:
        return float(raw_value), 'pct'
    if col in score_cols:
        return float(raw_value), 'score'
    if col in evalue_cols:
        return float(raw_value), 'evalue'
    if col == 'sequence':
        return sanitize_excel_text(raw_value, is_sequence=True), 'seq'
    return sanitize_excel_text(raw_value), 'text'


def compute_column_widths(columns, rows, int_cols=INT_COLUMNS, pct_cols=PCT_COLUMNS,
                          score_cols=SCORE_COLUMNS, evalue_cols=EVALUE_COLUMNS,
                          width_limits=WIDTH_LIMITS):
    widths = {}
    for col in columns:
        # Leave room for bold header text plus the AutoFilter dropdown arrow.
        header_width = math.ceil(len(col) * 1.12) + 5
        min_w, max_w = width_limits.get(col, (max(11, header_width), max(24, header_width)))
        if col == 'sequence':
            widths[col] = min_w
            continue
        max_len = 0
        for row in rows:
            val = row.get(col, '')
            if val == '' or val is None:
                continue
            if col in int_cols or col == 'query_frame':
                disp = len(f'{int(val):,}')
            elif col in pct_cols:
                disp = len(f'{float(val):.2f}')
            elif col in score_cols:
                disp = len(f'{float(val):.1f}')
            elif col in evalue_cols:
                fval = float(val)
                disp = 1 if fval == 0 else len(f'{fval:.2E}')
            else:
                disp = len(sanitize_excel_text(val))
            if disp > max_len:
                max_len = disp
        widths[col] = min(max_w, max(min_w, header_width, max_len + 3))
    return widths


def _write_xlsx_openpyxl(output_path, columns, rows, widths, sheet_title, type_kwargs):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

    wb = Workbook()
    ws = wb.active
    ws.title = sheet_title[:31]
    ws.freeze_panes = 'A2'

    header_font = Font(name='Arial', size=10, bold=True, color='FFFFFF')
    header_fill = PatternFill(fill_type='solid', start_color='1F4E78', end_color='1F4E78')
    header_align = Alignment(horizontal='left', vertical='center', wrap_text=False)

    text_font = Font(name='Arial', size=10)
    seq_font = Font(name='Consolas', size=9)
    left_align = Alignment(horizontal='left', vertical='center', wrap_text=False)
    right_align = Alignment(horizontal='right', vertical='center', wrap_text=False)
    row_border = Border(bottom=Side(style='thin', color='D9D9D9'))

    num_formats = {
        'int': '#,##0',
        'pct': '0.00',
        'score': '0.0',
        'evalue': '[=0]0;0.00E+00',
    }

    ws.row_dimensions[1].height = 24
    for col_idx, col in enumerate(columns, 1):
        cell = ws.cell(row=1, column=col_idx, value=col)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_align
        ws.column_dimensions[excel_col_letter(col_idx)].width = widths[col]

    for row_idx, row in enumerate(rows, 2):
        ws.row_dimensions[row_idx].height = 18
        for col_idx, col in enumerate(columns, 1):
            val, kind = typed_excel_value(col, row.get(col, ''), **type_kwargs)
            cell = ws.cell(row=row_idx, column=col_idx)
            if kind in ('text', 'seq') and isinstance(val, str) and val.startswith(('=', '+', '-', '@')):
                cell.value = val
                cell.data_type = 's'
            else:
                cell.value = val
            cell.font = seq_font if kind == 'seq' else text_font
            cell.alignment = right_align if kind in num_formats else left_align
            cell.border = row_border
            if kind in num_formats:
                cell.number_format = num_formats[kind]
            elif col == 'query_frame' and kind == 'int':
                cell.number_format = '0'

    last_col = excel_col_letter(len(columns))
    last_row = max(1, len(rows) + 1)
    ws.auto_filter.ref = f'A1:{last_col}{last_row}'
    wb.save(output_path)


def _write_xlsx_stdlib(output_path, columns, rows, widths, sheet_title, type_kwargs):
    style_index = {'text': 0, 'header': 1, 'int': 2, 'pct': 3, 'score': 4, 'evalue': 5, 'seq': 6}
    last_col = excel_col_letter(len(columns))
    last_row = max(1, len(rows) + 1)
    dimension_ref = f'A1:{last_col}{last_row}'

    cols_xml = ''.join(
        f'<col min="{idx}" max="{idx}" width="{widths[col]}" customWidth="1"/>'
        for idx, col in enumerate(columns, 1)
    )
    sheet_rows = []
    header_cells = ''.join(
        f'<c r="{excel_col_letter(idx)}1" s="1" t="inlineStr">'
        f'<is><t xml:space="preserve">{xml_escape(col)}</t></is></c>'
        for idx, col in enumerate(columns, 1)
    )
    sheet_rows.append(f'<row r="1" ht="24" customHeight="1">{header_cells}</row>')

    for row_idx, row in enumerate(rows, 2):
        cells = []
        for col_idx, col in enumerate(columns, 1):
            ref = f'{excel_col_letter(col_idx)}{row_idx}'
            val, kind = typed_excel_value(col, row.get(col, ''), **type_kwargs)
            s_idx = style_index[kind]
            if val == '':
                cells.append(f'<c r="{ref}" s="{s_idx}"/>')
            elif kind in ('int', 'pct', 'score', 'evalue'):
                cells.append(f'<c r="{ref}" s="{s_idx}"><v>{val}</v></c>')
            else:
                cells.append(
                    f'<c r="{ref}" s="{s_idx}" t="inlineStr">'
                    f'<is><t xml:space="preserve">{xml_escape(str(val))}</t></is></c>'
                )
        sheet_rows.append(f'<row r="{row_idx}" ht="18" customHeight="1">{"".join(cells)}</row>')

    sheet_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f'<dimension ref="{dimension_ref}"/>'
        '<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="18" customHeight="1"/>'
        f'<cols>{cols_xml}</cols>'
        f'<sheetData>{"".join(sheet_rows)}</sheetData>'
        f'<autoFilter ref="{dimension_ref}"/>'
        '</worksheet>'
    )
    styles_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="4">'
        '<numFmt numFmtId="164" formatCode="#,##0"/>'
        '<numFmt numFmtId="165" formatCode="0.00"/>'
        '<numFmt numFmtId="166" formatCode="0.0"/>'
        '<numFmt numFmtId="167" formatCode="[=0]0;0.00E+00"/>'
        '</numFmts>'
        '<fonts count="3">'
        '<font><sz val="10"/><name val="Arial"/></font>'
        '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>'
        '<font><sz val="9"/><name val="Consolas"/></font>'
        '</fonts>'
        '<fills count="3">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/></patternFill></fill>'
        '</fills>'
        '<borders count="2">'
        '<border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left/><right/><top/><bottom style="thin"><color rgb="FFD9D9D9"/></bottom><diagonal/></border>'
        '</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="7">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="left" vertical="center" wrapText="0"/></xf>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1">'
        '<alignment horizontal="left" vertical="center" wrapText="0"/></xf>'
        '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="right" vertical="center" wrapText="0"/></xf>'
        '<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="right" vertical="center" wrapText="0"/></xf>'
        '<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="right" vertical="center" wrapText="0"/></xf>'
        '<xf numFmtId="167" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="right" vertical="center" wrapText="0"/></xf>'
        '<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="left" vertical="center" wrapText="0"/></xf>'
        '</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>'
    )
    workbook_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        f'<sheets><sheet name="{xml_escape(sheet_title[:31])}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>'
    )
    workbook_rels_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>'
    )
    root_rels_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>'
    )
    content_types_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>'
    )

    with zipfile.ZipFile(output_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('[Content_Types].xml', content_types_xml)
        archive.writestr('_rels/.rels', root_rels_xml)
        archive.writestr('xl/workbook.xml', workbook_xml)
        archive.writestr('xl/_rels/workbook.xml.rels', workbook_rels_xml)
        archive.writestr('xl/styles.xml', styles_xml)
        archive.writestr('xl/worksheets/sheet1.xml', sheet_xml)


def write_formatted_xlsx(output_path, columns, rows, sheet_title, int_cols=INT_COLUMNS,
                         pct_cols=PCT_COLUMNS, score_cols=SCORE_COLUMNS,
                         evalue_cols=EVALUE_COLUMNS, width_limits=WIDTH_LIMITS,
                         force_stdlib=False):
    safe_title = re.sub(r'[\\/*?:\[\]]+', '_', str(sheet_title)).strip('_')[:31] or 'Results'
    type_kwargs = {
        'int_cols': int_cols,
        'pct_cols': pct_cols,
        'score_cols': score_cols,
        'evalue_cols': evalue_cols,
    }
    widths = compute_column_widths(columns, rows, width_limits=width_limits, **type_kwargs)
    if not force_stdlib:
        try:
            _write_xlsx_openpyxl(output_path, columns, rows, widths, safe_title, type_kwargs)
            return
        except ImportError:
            pass
    _write_xlsx_stdlib(output_path, columns, rows, widths, safe_title, type_kwargs)


def write_best_hits_xlsx(output_path, rows, suffix, force_stdlib=False):
    write_formatted_xlsx(output_path, BEST_COLUMNS, rows, f'best_hits_{suffix}',
                         force_stdlib=force_stdlib)


def process_blast_results(blast_file, fasta_file, prefix, suffix, query_coverage_type='qcovs',
                          taxonomy_db=None, strand_field='subject_strand'):
    """Process BLAST HSPs, sort all outputs in descending order, and write TSV + XLSX reports."""
    subjects_by_query = {}
    best_hits = {}
    hsp_records = []
    resolver = None
    hsp_count = 0

    with closing(SeqIO.index(str(fasta_file), 'fasta')) as sequences:
        for hit, interval in read_hits(blast_file, sequences):
            if resolver is None:
                resolver = TaxonomyResolver(taxonomy_db)
            taxonomy = resolver.resolve(hit['tax_id'])
            row = {
                **hit,
                **taxonomy,
                'search_database': suffix,
                'query_coverage_type': query_coverage_type,
                'query_frame': '',
                'query_strand': 'plus' if int(hit['query_start']) <= int(hit['query_end']) else 'minus',
            }
            if strand_field == 'qframe':
                frame = int(hit['subject_strand'])
                if frame not in [-3, -2, -1, 1, 2, 3]:
                    raise ValueError(f'Invalid translated query frame: {frame}')
                row.update(
                    subject_strand='',
                    query_frame=frame,
                    query_strand='plus' if frame > 0 else 'minus',
                )
            hsp_count += 1
            query = hit['query_id']
            order_key = hit_order(hit)
            hsp_records.append((query, order_key, row))

            if query not in best_hits or order_key < hit_order(best_hits[query]):
                best_hits[query] = row

            query_subjects = subjects_by_query.setdefault(query, {})
            subject_id = hit['subject_id']
            if subject_id not in query_subjects:
                query_subjects[subject_id] = {
                    'best': row,
                    'intervals': [],
                    'count': 0,
                    'min_evalue': float(hit['evalue']),
                }
            subject_entry = query_subjects[subject_id]
            subject_entry['intervals'].append(interval)
            subject_entry['count'] += 1
            subject_entry['min_evalue'] = min(subject_entry['min_evalue'], float(hit['evalue']))
            if order_key < hit_order(subject_entry['best']):
                subject_entry['best'] = row

        # Precompute merged query intervals per (query, subject)
        for query, query_subjects in subjects_by_query.items():
            for subject_entry in query_subjects.values():
                regions = merge_intervals(subject_entry['intervals'])
                covered = sum(end - start + 1 for start, end in regions)
                qlen = int(subject_entry['best']['query_length'])
                subject_entry['regions'] = regions
                subject_entry['regions_str'] = ';'.join(f'{start}-{end}' for start, end in regions)
                subject_entry['covered'] = covered
                subject_entry['union_coverage'] = round(100.0 * covered / qlen, 2)

        # Sort queries descending by best alignment length, bit score, E-value, identity, and query length.
        sorted_queries = sorted(best_hits, key=lambda q: best_row_order(best_hits[q]))
        query_rank = {query: idx for idx, query in enumerate(sorted_queries)}

        # 1. Detail file: all HSPs sorted by descending contig rank, then descending HSP strength.
        hsp_records.sort(key=lambda item: (query_rank[item[0]], item[1]))
        with open(f'{prefix}_all_hsps_{suffix}.tsv', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=HSP_COLUMNS, delimiter='\t')
            writer.writeheader()
            for _, _, hsp_row in hsp_records:
                writer.writerow({col: hsp_row[col] for col in HSP_COLUMNS})

        # 2. Detail file: per-(query, subject) summary ranked 1..N within each descending contig.
        total_subjects = 0
        with open(f'{prefix}_subject_summary_{suffix}.tsv', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=SUMMARY_COLUMNS, delimiter='\t')
            writer.writeheader()
            for query in sorted_queries:
                qlen = int(best_hits[query]['query_length'])
                ordered_subjects = sorted(
                    subjects_by_query[query].values(),
                    key=lambda entry: subject_summary_order(entry, qlen),
                )
                for rank_idx, subject_entry in enumerate(ordered_subjects, 1):
                    total_subjects += 1
                    best = subject_entry['best']
                    summary_row = {
                        column: best[column]
                        for column in (
                            ['query_id', 'query_length', 'subject_id', 'subject_title',
                             'tax_id', 'taxonomy_status', 'search_database'] + ORDERED_TAX_RANKS
                        )
                    }
                    summary_row.update(
                        subject_rank=rank_idx,
                        hsp_count=subject_entry['count'],
                        best_hsp_alignment_length=best['alignment_length'],
                        best_hsp_percent_identity=best['percent_identity'],
                        query_covered_bases=subject_entry['covered'],
                        query_union_coverage=subject_entry['union_coverage'],
                        best_hsp_bit_score=best['bit_score'],
                        min_evalue=subject_entry['min_evalue'],
                        query_regions=subject_entry['regions_str'],
                    )
                    writer.writerow(summary_row)

        # 3. Primary user files: 1 best hit per contig, sorted descending, with full sequence at end.
        best_rows = []
        for query in sorted_queries:
            best = best_hits[query]
            winning_subject = subjects_by_query[query][best['subject_id']]
            final_row = {
                column: best[column]
                for column in BEST_COLUMNS
                if column not in ('sequence', 'query_union_coverage', 'hsp_count', 'query_regions')
            }
            final_row.update(
                query_union_coverage=winning_subject['union_coverage'],
                hsp_count=winning_subject['count'],
                query_regions=winning_subject['regions_str'],
                sequence=str(sequences[query].seq),
            )
            best_rows.append(final_row)

        with open(f'{prefix}_best_hits_{suffix}.tsv', 'w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=BEST_COLUMNS, delimiter='\t')
            writer.writeheader()
            writer.writerows(best_rows)

        write_best_hits_xlsx(f'{prefix}_best_hits_{suffix}.xlsx', best_rows, suffix)

    print(f'Retained {hsp_count} HSPs, {total_subjects} query-subject pairs, {len(best_rows)} queries.')


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
