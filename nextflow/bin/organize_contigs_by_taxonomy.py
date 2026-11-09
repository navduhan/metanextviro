#!/usr/bin/env python3

import argparse
import pandas as pd
from Bio import SeqIO
from pathlib import Path
import os

def create_directory_structure(output_dir, sample_id):
    """Create the directory structure for organizing contigs."""
    base_dir = Path(output_dir) / sample_id
    virus_dir = base_dir / "viruses"
    bacteria_dir = base_dir / "bacteria"
    
    # Create main directories
    for dir_path in [virus_dir, bacteria_dir]:
        dir_path.mkdir(parents=True, exist_ok=True)
        # Create unclassified directory in each
        (dir_path / "unclassified").mkdir(exist_ok=True)
    
    return base_dir, virus_dir, bacteria_dir

def create_enhanced_header(record, taxonomy_info, sample_id):
    """Create an enhanced FASTA header with taxonomic information."""
    original_id = record.id
    original_desc = record.description.replace(record.id, '').strip()
    
    # Extract taxonomic information
    superkingdom = taxonomy_info.get('superkingdom', 'Unknown')
    phylum = taxonomy_info.get('phylum', 'Unknown')
    class_taxon = taxonomy_info.get('class', 'Unknown')
    order = taxonomy_info.get('order', 'Unknown')
    family = taxonomy_info.get('family', 'Unknown')
    genus = taxonomy_info.get('genus', 'Unknown')
    species = taxonomy_info.get('species', 'Unknown')
    subject_title = taxonomy_info.get('subject_title', 'Unknown')
    
    # Create enhanced header (no leading '>')
    enhanced_header = f"{original_id}|sample={sample_id}|superkingdom={superkingdom}|phylum={phylum}|class={class_taxon}|order={order}|family={family}|genus={genus}|species={species}|subject={subject_title}"
    
    # Add original description if available
    if original_desc:
        enhanced_header += f" {original_desc}"
    
    return enhanced_header

def write_fasta(sequence_record, output_file, enhanced_header=None):
    """Write a sequence record to a FASTA file with optional enhanced header."""
    with open(output_file, 'w') as f:
        if enhanced_header:
            # Create a new record with enhanced header
            from Bio.SeqRecord import SeqRecord
            enhanced_record = SeqRecord(
                seq=sequence_record.seq,
                id=enhanced_header,
                description=""
            )
            SeqIO.write(enhanced_record, f, 'fasta')
        else:
            SeqIO.write(sequence_record, f, 'fasta')

def organize_contigs(blast_results_list, fasta_file, output_dir, sample_id):
    """Organize contigs based on BLAST results and taxonomy."""
    
    # Create directory structure
    base_dir, virus_dir, bacteria_dir = create_directory_structure(output_dir, sample_id)
    
    # Read and merge BLAST results
    dfs = []
    for br in blast_results_list:
        if os.path.exists(br) and os.path.getsize(br) > 0:
            try:
                tdf = pd.read_csv(br, sep='\t', dtype={'query_id': str, 'subject_id': str})
                if not tdf.empty:
                    dfs.append(tdf)
            except Exception as e:
                print(f"Warning: Could not read BLAST result {br}: {e}")
    
    if not dfs:
        print("No BLAST results found to process.")
        # Just copy all contigs to unclassified
        unclass_dir = base_dir / "unclassified"
        unclass_dir.mkdir(exist_ok=True)
        with open(fasta_file) as fasta_handle:
            for record in SeqIO.parse(fasta_handle, 'fasta'):
                write_fasta(record, unclass_dir / f"{record.id}.fasta")
        
        with open(base_dir / "classification_summary.txt", 'w') as f:
            f.write(f"Classification Summary for {sample_id}\n")
            f.write("=" * 50 + "\n\n")
            f.write("No BLAST hits found. All contigs are unclassified.\n")
        return

    df = pd.concat(dfs, ignore_index=True)
    
    # Normalize column names (strip whitespace, lower-case for robust matching)
    df.columns = [col.strip().lower() for col in df.columns]
    
    # Preserve every local alignment, including conflicting regions/databases.
    df.to_csv(base_dir / "classification_evidence.tsv", sep='\t', index=False)
    if 'bit_score' in df.columns:
        df['bit_score'] = pd.to_numeric(df['bit_score'], errors='raise')
        df = df.sort_values(by=['query_id', 'bit_score'], ascending=[True, False])

    contig_info = {}
    review_reasons = {}
    ranks = ['superkingdom', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']

    def is_known(value):
        return pd.notna(value) and str(value).strip().lower() not in [
            '', 'nan', 'none', 'na', 'n/a', 'unknown']

    def known_values(group, rank):
        if rank not in group:
            return set()
        return {str(value).strip() for value in group[rank] if is_known(value)}

    for contig_id, group in df.groupby('query_id', sort=False):
        values = {rank: known_values(group, rank) for rank in ranks}
        # Conflicts can represent ambiguity, shared genes, or an assembly chimera.
        # Never infer a confirmed chimera or split sequence automatically.
        conflicts = [rank for rank in ranks[:6] if len(values[rank]) > 1]
        if conflicts:
            review_reasons[contig_id] = 'conflicting_taxonomy:' + ','.join(conflicts)
            continue
        superkingdom = next(iter(values['superkingdom']), '').lower()
        if superkingdom not in ['viruses', 'bacteria']:
            continue
        if 'taxonomy_status' in group and group['taxonomy_status'].isin(
                ['invalid_taxid', 'missing_taxid', 'unresolved_taxid']).any():
            review_reasons[contig_id] = 'unresolved_taxonomy_among_hits'
            continue
        info = {'type': superkingdom}
        for rank in ranks:
            # Do not borrow a species/genus from one alternative hit.
            all_known = rank in group and all(is_known(value) for value in group[rank])
            value = next(iter(values[rank])) if len(values[rank]) == 1 and all_known else ''
            info[rank] = value.replace(' ', '_').replace('/', '_').replace('\\', '_') or (
                'unclassified' if rank == 'family' else 'Unknown')
        titles = sorted(known_values(group, 'subject_title'))
        info['subject_title'] = ';'.join(titles).replace(' ', '_') or 'Unknown'
        contig_info[contig_id] = info

    with open(base_dir / "classification_review.tsv", 'w') as handle:
        handle.write("query_id\treview_reason\n")
        for contig_id, reason in sorted(review_reasons.items()):
            handle.write(f"{contig_id}\t{reason}\n")

    # Process FASTA file and organize contigs
    unclassified_contigs = []
    taxonomy_summary = {'viruses': {}, 'bacteria': {}}
    
    with open(fasta_file) as fasta_handle:
        for record in SeqIO.parse(fasta_handle, 'fasta'):
            if record.id in review_reasons:
                review_dir = base_dir / 'needs_review'
                review_dir.mkdir(exist_ok=True)
                write_fasta(record, review_dir / f"{record.id}.fasta")
            elif record.id in contig_info:
                info = contig_info[record.id]
                org_type = info['type']
                family = info['family']
            
                # Create family directory if it doesn't exist
                if family != 'unclassified':
                    family_dir = virus_dir if org_type == 'viruses' else bacteria_dir
                    family_dir = family_dir / family
                    family_dir.mkdir(exist_ok=True)
                
                    # Track taxonomy for summary
                    if family not in taxonomy_summary[org_type]:
                        taxonomy_summary[org_type][family] = {
                            'count': 0,
                            'species': set(),
                            'genera': set()
                        }
                    taxonomy_summary[org_type][family]['count'] += 1
                    taxonomy_summary[org_type][family]['species'].add(info['species'])
                    taxonomy_summary[org_type][family]['genera'].add(info['genus'])
            
                # Determine output directory
                if family == 'unclassified':
                    output_dir_path = virus_dir / 'unclassified' if org_type == 'viruses' else bacteria_dir / 'unclassified'
                else:
                    output_dir_path = virus_dir / family if org_type == 'viruses' else bacteria_dir / family
            
                # Create enhanced header
                enhanced_header = create_enhanced_header(record, info, sample_id)
            
                # Write contig to appropriate file with enhanced header
                output_file = output_dir_path / f"{record.id}.fasta"
                write_fasta(record, output_file, enhanced_header)
            else:
                unclassified_contigs.append(record)
    
    # Write unclassified contigs
    if unclassified_contigs:
        unclass_dir = base_dir / "unclassified"
        unclass_dir.mkdir(exist_ok=True)
        for record in unclassified_contigs:
            write_fasta(record, unclass_dir / f"{record.id}.fasta")
    
    # Create detailed summary file
    with open(base_dir / "classification_summary.txt", 'w') as f:
        f.write(f"Classification Summary for {sample_id}\n")
        f.write("=" * 50 + "\n\n")
        
        f.write("VIRAL CONTIGS:\n")
        f.write("-" * 20 + "\n")
        if taxonomy_summary['viruses']:
            for family in sorted(taxonomy_summary['viruses'].keys()):
                info = taxonomy_summary['viruses'][family]
                f.write(f"\nFamily: {family}\n")
                f.write(f"  Contig Count: {info['count']}\n")
                f.write(f"  Genera: {', '.join(sorted(info['genera']))}\n")
                f.write(f"  Species: {', '.join(sorted(info['species']))}\n")
        else:
            f.write("No viral contigs found.\n")
        
        f.write("\n\nBACTERIAL CONTIGS:\n")
        f.write("-" * 20 + "\n")
        if taxonomy_summary['bacteria']:
            for family in sorted(taxonomy_summary['bacteria'].keys()):
                info = taxonomy_summary['bacteria'][family]
                f.write(f"\nFamily: {family}\n")
                f.write(f"  Contig Count: {info['count']}\n")
                f.write(f"  Genera: {', '.join(sorted(info['genera']))}\n")
                f.write(f"  Species: {', '.join(sorted(info['species']))}\n")
        else:
            f.write("No bacterial contigs found.\n")
        
        f.write(f"\n\nUnclassified Contigs: {len(unclassified_contigs)}\n")
        f.write(f"Contigs requiring review: {len(review_reasons)}\n")
        f.write("Review includes conflicting/ambiguous hits; this is not a confirmed chimera call.\n")
        
        # Add header format explanation
        f.write("\n\nFASTA HEADER FORMAT:\n")
        f.write("-" * 20 + "\n")
        f.write(">contig_id|sample=sample_id|superkingdom=...|phylum=...|class=...|order=...|family=...|genus=...|species=...|subject=subject_title\n")

def main():
    parser = argparse.ArgumentParser(description="Organize contigs based on BLAST results and taxonomy")
    parser.add_argument("-b", "--blast_results", required=True, nargs='+', help="Path to one or more BLAST results files")
    parser.add_argument("-f", "--fasta_file", required=True, help="Path to input FASTA file")
    parser.add_argument("-o", "--output_dir", required=True, help="Output directory")
    parser.add_argument("-s", "--sample_id", required=True, help="Sample ID")
    
    args = parser.parse_args()
    
    organize_contigs(args.blast_results, args.fasta_file, args.output_dir, args.sample_id)

if __name__ == "__main__":
    main()
