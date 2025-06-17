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

def write_fasta(sequence_record, output_file):
    """Write a sequence record to a FASTA file."""
    with open(output_file, 'w') as f:
        SeqIO.write(sequence_record, f, 'fasta')

def organize_contigs(blast_results, fasta_file, output_dir, sample_id):
    """Organize contigs based on BLAST results and taxonomy."""
    
    # Create directory structure
    base_dir, virus_dir, bacteria_dir = create_directory_structure(output_dir, sample_id)
    
    # Read BLAST results
    df = pd.read_csv(blast_results, sep='\t')
    
    # Create a dictionary to store contig classifications
    contig_info = {}
    for _, row in df.iterrows():
        contig_id = row['query_id']
        superkingdom = str(row.get('superkingdom', '')).lower()
        family = str(row.get('family', '')).replace(' ', '_')
        
        if superkingdom in ['viruses', 'bacteria']:
            contig_info[contig_id] = {
                'type': superkingdom,
                'family': family if family != 'nan' else 'unclassified'
            }
    
    # Process FASTA file and organize contigs
    unclassified_contigs = []
    classified_families = {'viruses': set(), 'bacteria': set()}
    
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
                classified_families[org_type].add(family)
            
            # Determine output directory and filename
            if family == 'unclassified':
                output_dir = virus_dir / 'unclassified' if org_type == 'viruses' else bacteria_dir / 'unclassified'
            else:
                output_dir = virus_dir / family if org_type == 'viruses' else bacteria_dir / family
            
            # Write contig to appropriate file
            output_file = output_dir / f"{record.id}.fasta"
            write_fasta(record, output_file)
        else:
            unclassified_contigs.append(record)
    
    # Write unclassified contigs
    if unclassified_contigs:
        unclass_dir = base_dir / "unclassified"
        unclass_dir.mkdir(exist_ok=True)
        for record in unclassified_contigs:
            write_fasta(record, unclass_dir / f"{record.id}.fasta")
    
    # Create summary file
    with open(base_dir / "classification_summary.txt", 'w') as f:
        f.write(f"Classification Summary for {sample_id}\n")
        f.write("=" * 50 + "\n\n")
        
        f.write("Viral Families:\n")
        for family in sorted(classified_families['viruses']):
            f.write(f"- {family}\n")
        
        f.write("\nBacterial Families:\n")
        for family in sorted(classified_families['bacteria']):
            f.write(f"- {family}\n")
        
        f.write(f"\nUnclassified Contigs: {len(unclassified_contigs)}\n")

def main():
    parser = argparse.ArgumentParser(description="Organize contigs based on BLAST results and taxonomy")
    parser.add_argument("-b", "--blast_results", required=True, help="Path to BLAST results file")
    parser.add_argument("-f", "--fasta_file", required=True, help="Path to input FASTA file")
    parser.add_argument("-o", "--output_dir", required=True, help="Output directory")
    parser.add_argument("-s", "--sample_id", required=True, help="Sample ID")
    
    args = parser.parse_args()
    
    organize_contigs(args.blast_results, args.fasta_file, args.output_dir, args.sample_id)

if __name__ == "__main__":
    main() 