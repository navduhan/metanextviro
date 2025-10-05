// Author: Naveen Duhan

process fastqc {
    tag "$id"  // Tagging process with sample ID for better traceability
    label 'low'

    // Use publishDir to save outputs in a specific directory
    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
    tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and read file paths (paired-end or single-end)

    output:
    path "fastqc_reports/*", emit: fastqc_report  // Emit the FastQC report directory

    script:
    """
    # Create output directory for FastQC reports
    mkdir -p fastqc_reports

    # Logging input file details
    echo "Starting FastQC for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    [ -n "${reads2}" ] && echo " - Reads2: ${reads2}" || echo " - Reads2: None (Single-end)"

    # Run FastQC based on input file type
    if [ -z "${reads2}" ]; then
        echo "Running FastQC in single-end mode..."
        fastqc -t ${task.cpus} -o fastqc_reports ${reads1}
    else
        echo "Running FastQC in paired-end mode..."
        fastqc -t ${task.cpus} -o fastqc_reports ${reads1} ${reads2}
    fi

    # Verify output and log success
    echo "FastQC completed for sample: $id"
    """
}
