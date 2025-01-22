#!/usr/bin/env python3
"""
Script to rename headers in a FASTA file for consistent naming.
Author: Naveen Duhan
"""

import argparse
from Bio import SeqIO


def rename_fasta_headers(input_fasta, output_fasta, software):
    """
    Rename headers in a FASTA file and save the result to a new file.

    Parameters:
        input_fasta (str): Path to the input FASTA file.
        output_fasta (str): Path to the output FASTA file with renamed headers.
    """
    try:
        # Open the input and output FASTA files
        with open(input_fasta, 'r') as infile, open(output_fasta, 'w') as outfile:
            for num, record in enumerate(SeqIO.parse(infile, "fasta"), start=1):
                # Rename the header to "nextreo_contigs_<num>_<length>"
                record.id = f"MetaNextViro_{software}_contigs_{num}_{len(record.seq)}"
                record.description = ""  # Clear the description (optional)
                # Write the modified record to the output file
                SeqIO.write(record, outfile, "fasta")

        print(f"Successfully renamed headers and saved to: {output_fasta}")
    except FileNotFoundError as e:
        print(f"Error: {e}. Please ensure the input file exists.")
    except Exception as e:
        print(f"Unexpected error occurred: {e}")


def main():
    """
    Main function to parse command-line arguments and execute the renaming process.
    """
    parser = argparse.ArgumentParser(description="Rename headers in a FASTA file.")
    parser.add_argument("-i", "--input", required=True, help="Path to the input FASTA file")
    parser.add_argument("-o", "--output", required=True, help="Path to save the output FASTA file with renamed headers")
    parser.add_argument("-s", "--software", required=True, help="Name of the software used to generate the contigs")

    # Parse the command-line arguments
    args = parser.parse_args()

    # Call the function to rename headers
    rename_fasta_headers(args.input, args.output, args.software)


if __name__ == "__main__":
    main()
