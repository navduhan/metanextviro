// Author: Naveen Duhan

// fastp paired-end trimming
process fastp {
    tag "$id"  // Tag the task with the sample ID for traceability
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/fastp_results", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and reads (paired-end or single-end)

    output:
        tuple val(id), path("${id}_fastp_trimmed_1.fq.gz"), emit: trimmed_reads1
        tuple val(id), path("${id}_fastp_trimmed_2.fq.gz"), emit: trimmed_reads2
        path "fastp_report_${id}.html", emit: report

    script:
    """
    # Log the start of the process
    echo " Starting fastp trimming for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    echo " - Reads2: ${reads2}"

    # Run fastp for paired-end trimming
    fastp \\
        -i ${reads1} \\
        -I ${reads2} \\
        -o ${id}_fastp_trimmed_1.fq.gz \\
        -O ${id}_fastp_trimmed_2.fq.gz \\
        --html fastp_report_${id}.html \\
        --thread ${task.cpus}

    # Verify output files
    if [ ! -f "${id}_fastp_trimmed_1.fq.gz" ] || [ ! -f "${id}_fastp_trimmed_2.fq.gz" ]; then
        echo " Error: fastp failed to generate trimmed reads for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " fastp trimming completed successfully for sample: $id"
    """
} 