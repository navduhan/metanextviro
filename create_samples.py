import os
import csv
import argparse

def extract_sample_name(filename):
    """Extract the sample name by splitting the filename at '_L001'."""
    return filename.split('_L001')[0]

def generate_samples_csv(input_dir, output_file):
    """Generate samples.csv from paired FASTQ files with full paths."""
    fastq_files = [f for f in os.listdir(input_dir) if f.endswith('.fastq') or f.endswith('.fastq.gz')]

    # Group files by sample name
    samples = {}
    for file in fastq_files:
        sample_name = extract_sample_name(file)
        full_path = os.path.abspath(os.path.join(input_dir, file))
        if '_R1' in file:
            samples.setdefault(sample_name, {})['read1'] = full_path
        elif '_R2' in file:
            samples.setdefault(sample_name, {})['read2'] = full_path

    # Write to CSV
    with open(output_file, 'w', newline='') as csvfile:
        csv_writer = csv.writer(csvfile)
        csv_writer.writerow(['id', 'reads1', 'reads2'])

        for sample_name, files in samples.items():
            csv_writer.writerow([
                sample_name,
                files.get('read1', 'NA'),
                files.get('read2', 'NA')
            ])

    print(f"Samples CSV file generated: {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate samples.csv from paired FASTQ files with full paths.")
    parser.add_argument('-i', '--input_dir', required=True, help="Directory containing FASTQ files.")
    parser.add_argument('-o', '--output_file', default="samples.csv", help="Output CSV file (default: samples.csv).")

    args = parser.parse_args()
    generate_samples_csv(args.input_dir, args.output_file)
