// Author: Naveen Duhan

process flexbar {
    tag "$id"  // Tagging process with sample ID for traceability
    label 'low'

    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and reads (paired-end or single-end)

    output:
        tuple val(id), path("trimmed_reads/${id}_trimmed_1.fastq.gz"), emit: clean_reads1
        tuple val(id), path("trimmed_reads/${id}_trimmed_2.fastq.gz"), emit: clean_reads2
        tuple val(id), path("trimmed_reads/${id}_trimmed.log"), emit: clean_log
        

    script:
    """
    # Create output directory for trimmed reads
    mkdir -p trimmed_reads

    # Logging input file details
    echo " Starting Flexbar for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    ${reads2 ? "echo \" - Reads2: ${reads2}\"" : "echo \" - Reads2: None (Single-end)\""}

    # Run Flexbar based on input type
    if [ -n "$reads2" ]; then
        echo " Running Flexbar in paired-end mode..."
        flexbar -r $reads1 -p $reads2 \
                -t trimmed_reads/${id}_trimmed \
                -qt ${params.quality} \
                -n ${task.cpus} \
                -z GZ \
                -a ${params.adapters}
    else
        echo " Running Flexbar in single-end mode..."
        flexbar -r $reads1 \
                -t trimmed_reads/${id}_trimmed \
                -qt ${params.quality} \
                -n ${task.cpus} \
                -z GZ \
                -a ${params.adapters}
    fi

    # Verify output files
    if [ ! -f "trimmed_reads/${id}_trimmed_1.fastq.gz" ] || [ "$reads2" -a ! -f "trimmed_reads/${id}_trimmed_2.fastq.gz" ]; then
        echo " Error: Flexbar failed to generate trimmed reads for sample: $id" >&2
        exit 1
    fi

    echo " Flexbar completed successfully for sample: $id"
    """
}
