#!/bin/bash
# Whole-contig mean depth and breadth, including uncovered positions.
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <indexed_bam> <output_file> [idxstats_file]" >&2
    exit 1
fi

BAM_FILE=$1
OUTPUT_FILE=$2
IDXSTATS_FILE=${3:-"${OUTPUT_FILE}.idxstats.txt"}

if [ ! -f "$BAM_FILE" ]; then
    echo "Error: BAM file $BAM_FILE not found" >&2
    exit 1
fi

samtools idxstats "$BAM_FILE" > "$IDXSTATS_FILE"
# One depth pass rather than reopening the BAM separately for every contig.
# idxstats counts mapped read segments, not deduplicated read pairs.
samtools depth "$BAM_FILE" | awk '
    BEGIN { OFS="\t" }
    NR==FNR {
        if ($1 != "*" && $2 > 0) {
            ids[++n]=$1; lengths[$1]=$2; reads[$1]=$3
        }
        next
    }
    { depth[$1]+=$3; if ($3 > 0) covered[$1]++ }
    END {
        print "Contig", "Length", "Average_Coverage", "Total_Reads", "Covered_Bases", "Coverage_Breadth"
        for (i=1; i<=n; i++) {
            id=ids[i]
            print id, lengths[id], (depth[id]+0)/lengths[id], reads[id], covered[id]+0, 100*(covered[id]+0)/lengths[id]
        }
    }
' "$IDXSTATS_FILE" - > "$OUTPUT_FILE"
