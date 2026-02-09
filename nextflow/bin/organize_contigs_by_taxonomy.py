#!/usr/bin/env python3

import argparse
import pandas as pd
from Bio import SeqIO
from pathlib import Path
import shutil
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
                tdf = pd.read_csv(br, sep='\t')
                if not tdf.empty:
                    dfs.append(tdf)
            except Exception as e:
                print(f"Warning: Could not read BLAST result {br}: {e}")
    
    if not dfs:
        print("No BLAST results found to process.")
        # Just copy all contigs to unclassified
        unclass_dir = base_dir / "unclassified"
        unclass_dir.mkdir(exist_ok=True)
        for record in SeqIO.parse(fasta_file, 'fasta'):
            write_fasta(record, unclass_dir / f"{record.id}.fasta")
        
        with open(base_dir / "classification_summary.txt", 'w') as f:
            f.write(f"Classification Summary for {sample_id}\n")
            f.write("=" * 50 + "\n\n")
            f.write("No BLAST hits found. All contigs are unclassified.\n")
        return

    df = pd.concat(dfs, ignore_index=True)
    
    # Normalize column names (strip whitespace, lower-case for robust matching)
    df.columns = [col.strip().lower() for col in df.columns]
    
    # If multiple hits for same contig across files, pick the one with highest bit_score
    if 'bit_score' in df.columns:
        df = df.sort_values(by=['query_id', 'bit_score'], ascending=[True, False])
    
    df = df.groupby('query_id').first().reset_index()
    
    # Create a dictionary to store contig classifications with full taxonomy
    contig_info = {}
    for _, row in df.iterrows():
        contig_id = row['query_id']
        superkingdom = str(row.get('superkingdom', '')).strip().lower()
        phylum = str(row.get('phylum', '')).strip().replace(' ', '_')
        class_taxon = str(row.get('class', '')).strip().replace(' ', '_')
        order = str(row.get('order', '')).strip().replace(' ', '_')
        family = str(row.get('family', '')).strip().replace(' ', '_')
        genus = str(row.get('genus', '')).strip().replace(' ', '_')
        species = str(row.get('species', '')).strip().replace(' ', '_')
        subject_title = str(row.get('subject_title', '')).strip().replace(' ', '_')
        
        # Handle missing or NaN values
        def safe_val(val, fallback='Unknown'):
            return fallback if val in ['', 'nan', 'None', 'NA', 'N/A'] else val
        
        if superkingdom in ['viruses', 'bacteria']:
            contig_info[contig_id] = {
                'type': superkingdom,
                'superkingdom': safe_val(superkingdom, 'Unknown'),
                'phylum': safe_val(phylum),
                'class': safe_val(class_taxon),
                'order': safe_val(order),
                'family': safe_val(family, 'unclassified'),
                'genus': safe_val(genus),
                'species': safe_val(species),
                'subject_title': safe_val(subject_title)
            }
    
    # Process FASTA file and organize contigs
    unclassified_contigs = []
    taxonomy_summary = {'viruses': {}, 'bacteria': {}}
    
    for record in SeqIO.parse(fasta_file, 'fasta'):
        if record.id in contig_info:
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