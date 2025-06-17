import argparse
import pandas as pd
import math
from Bio import SeqIO
from ete3 import NCBITaxa
from pathlib import Path

# Define column names for BLAST results
col = [
    'query_id', 'subject_id', 'percent_identity', 'alignment_length', 'mismatches',
    'gap_opens', 'query_start', 'query_end', 'subject_start', 'subject_end',
    'query_coverage', 'evalue', 'bit_score', 'query_length', 'subject_length',
    'subject_title', 'tax_id', 'subject_strand'
]

def seq2dict(fasta_file):
    """Convert a FASTA file to a dictionary with query IDs as keys and sequences as values."""
    seq_dict = {}
    long_seqs = []
    for record in SeqIO.parse(fasta_file, 'fasta'):
        if len(str(record.seq)) > 30000:
            long_seqs.append(record.id)
            seq_dict[record.id] = "Sequence length > 30000 bp. Please check contig file."
        else:
            seq_dict[record.id] = str(record.seq)
    
    if long_seqs:
        print(f"\nWarning: The following sequences are longer than 30000 bp and their sequences have been replaced with a message:")
        for seq_id in long_seqs:
            print(f"- {seq_id}")
    return seq_dict

def get_single_taxonomy_info(tax_id):
    """Retrieve taxonomy information for a single tax_id."""
    ncbi = NCBITaxa()
    try:
        lineage = ncbi.get_lineage(tax_id)
        names = ncbi.get_taxid_translator(lineage)
        ranks = ncbi.get_rank(lineage)
        tax_dict = {rank: None for rank in ['superkingdom', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']}
        for taxid in lineage:
            rank = ranks.get(taxid)
            if rank in tax_dict:
                tax_dict[rank] = names[taxid]
        return tax_dict
    except ValueError:
        print(f"Taxonomic ID {tax_id} not found.")
        return {rank: None for rank in ['superkingdom', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']}

def get_taxonomy_info(tax_id_str):
    """Retrieve taxonomy information for multiple tax_ids."""
    tax_ids = str(tax_id_str).split(';')
    merged_taxonomy = {rank: None for rank in ['superkingdom', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']}
    for tax_id in tax_ids:
        try:
            tax_info = get_single_taxonomy_info(int(tax_id.strip()))
            for rank in merged_taxonomy:
                if merged_taxonomy[rank] is None and tax_info[rank]:
                    merged_taxonomy[rank] = tax_info[rank]
        except ValueError:
            print(f"Invalid tax ID: {tax_id}")
    return merged_taxonomy

def process_blast_results(blast_file, fasta_file, prefix, suffix):
    """Process BLAST results and export them to Excel."""
    seqd = seq2dict(fasta_file)

    df = pd.read_csv(blast_file, sep="\t", names=col, low_memory=False)

    if df.empty:
        output_file = f"{prefix}_best_hits_{suffix}.xls"
        with open(output_file, 'w') as empty_file:
            empty_file.write('')  # Write an empty file
        print(f"BLAST results are empty. Saved empty file: {output_file}")
        return

    # Map sequences and calculate sequence lengths
    df['sequence'] = df['query_id'].map(seqd)
    df['sequence_length'] = df['sequence'].apply(lambda x: len(x) if isinstance(x, str) and not x.startswith("Sequence length > 30000") else 0)

    # Sort and select the best hits
    df_sorted = df.sort_values(by=['query_id', 'alignment_length', 'bit_score'], ascending=[True, False, False])
    df_best_hits = df_sorted.groupby('query_id').first().reset_index()

    # Apply taxonomy mapping
    taxonomy_info = df_best_hits['tax_id'].apply(get_taxonomy_info)
    taxonomy_df = pd.json_normalize(taxonomy_info)
    df_best_hits = df_best_hits.join(taxonomy_df)

    # Exit early if df_best_hits is empty
    if df_best_hits.empty:
        output_file = f"{prefix}_best_hits_{suffix}.xls"
        with open(output_file, 'w') as empty_file:
            empty_file.write('')  # Write an empty file
        print(f"Filtered BLAST results are empty after taxonomy mapping. Saved empty file: {output_file}")
        return

    # Select and reorder columns
    df_best_hits = df_best_hits[[
        'query_id', 'subject_id', 'percent_identity', 'alignment_length', 'mismatches',
        'gap_opens', 'query_start', 'query_end', 'subject_start', 'subject_end',
        'query_coverage', 'evalue', 'bit_score', 'query_length', 'subject_length',
        'subject_title', 'tax_id', 'subject_strand', 'sequence_length',
        'superkingdom', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species', 'sequence'
    ]]

    # Sort by alignment length
    df_best_hits = df_best_hits.sort_values(by=['alignment_length'], ascending=False)

    # Save the processed results to a file
    output_file = f"{prefix}_best_hits_{suffix}.xls"  # Save as .xls extension
    df_best_hits.to_csv(output_file, sep="\t", index=False)

    print(f"Saved {output_file} with {len(df_best_hits)} rows.")


def main():
    parser = argparse.ArgumentParser(description="Process BLAST results and map sequences with taxonomy information.")
    parser.add_argument("-b", "--blast_file", required=True, help="Path to the BLAST results file.")
    parser.add_argument("-f", "--fasta_file", required=True, help="Path to the FASTA file.")
    parser.add_argument("-p", "--prefix", required=True, help="Prefix for output file names.")
    parser.add_argument("-s", "--suffix", required=True, help="Prefix for output file names.")
    args = parser.parse_args()

    process_blast_results(args.blast_file, args.fasta_file,  args.prefix, args.suffix)

if __name__ == "__main__":
    main()
