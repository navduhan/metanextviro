// Author: Naveen Duhan

process trim_galore {
    tag "$id"  // Tagging process with sample ID for traceability
    label 'low'

    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and reads (paired-end or single-end)

    output:
        tuple val(id), path("trimmed_reads/${id}_val_1.fq.gz"), emit: clean_reads1
        tuple val(id), path("trimmed_reads/${id}_val_2.fq.gz"), emit: clean_reads2
        tuple val(id), path("trimmed_reads/${reads1}_trimming_report.txt"), emit: clean_log

    script:
    """
    # Create output directory for trimmed reads
    mkdir -p trimmed_reads

    # Log the start of the process
    echo " Starting Trim Galore for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    ${reads2 ? "echo \" - Reads2: ${reads2}\"" : "echo \" - Reads2: None (Single-end)\""}

    # Run Trim Galore based on input type
    if [ -n "${reads2}" ]; then
        echo " Running Trim Galore in paired-end mode..."
        trim_galore --paired \
                    --gzip \
                    --quality ${params.quality} \
                    --cores ${task.cpus} \
                    --basename ${id} \
                    --output_dir trimmed_reads \
                    ${reads1} ${reads2}
    else
        echo " Running Trim Galore in single-end mode..."
        trim_galore --quality ${params.quality} \
                    --gzip \
                    --cores ${task.cpus} \
                    --basename ${id} \
                    --output_dir trimmed_reads \
                    ${reads1}
    fi

    # Verify output files
    if [ ! -f "trimmed_reads/${id}_val_1.fq.gz" ] || ([ -n "${reads2}" ] && [ ! -f "trimmed_reads/${id}_val_2.fq.gz" ]); then
        echo " Error: Trim Galore failed to generate trimmed reads for sample: $id" >&2
        exit 1
    fi

    # Log completion of the process
    echo " Trim Galore completed successfully for sample: $id"
    """
}
