#!/bin/bash
# Calculate average coverage per contig from BAM file

BAM_FILE=$1
OUTPUT_FILE=$2

# Check if input files are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <bam_file> <output_file>"
    exit 1
fi

# Check if BAM file exists
if [ ! -f "$BAM_FILE" ]; then
    echo "Error: BAM file $BAM_FILE not found"
    exit 1
fi

# Create output file with header
echo -e "Contig\tLength\tAverage_Coverage\tTotal_Reads" > "$OUTPUT_FILE"

# Get contig information and calculate coverage
samtools idxstats "$BAM_FILE" | while read contig length mapped unmapped; do
    # Skip empty lines or lines with no contig name
    if [ -z "$contig" ] || [ "$contig" = "*" ]; then
        continue
    fi
    
    # Calculate average coverage
    # mapped reads * average read length / contig length
    # For paired-end reads, we'll use a simplified approach
    if [ "$length" -gt 0 ]; then
        # Get average coverage using samtools depth and awk
        avg_coverage=$(samtools depth -r "$contig" "$BAM_FILE" 2>/dev/null | awk '{sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
        
        # If no coverage data, set to 0
        if [ -z "$avg_coverage" ]; then
            avg_coverage=0
        fi
        
        echo -e "${contig}\t${length}\t${avg_coverage}\t${mapped}" >> "$OUTPUT_FILE"
    else
        echo -e "${contig}\t${length}\t0\t${mapped}" >> "$OUTPUT_FILE"
    fi
done 