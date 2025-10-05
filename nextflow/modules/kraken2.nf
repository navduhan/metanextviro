// Author: Naveen Duhan

process kraken2 {
    tag "$id"  // Tag each task with the sample ID for better traceability

    label 'high'  // Assign a label for resource management

    publishDir "${params.outdir}/kraken2_results", mode: 'copy', overwrite: true  // Define and manage the output directory

    input:
        tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and reads (paired-end or single-end)

    output:
        tuple val(id), path("${id}_kraken2_report.txt"), emit: report
        tuple val(id), path("${id}_kraken2_output.txt"), emit: classified_reads

    script:
    """
    # Log the start of the process
    echo " Starting Kraken2 analysis for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    ${reads2 ? "echo \" - Reads2: ${reads2}\"" : "echo \" - Reads2: None (Single-end)\""}

    # Run Kraken2 based on input type
    if [ -n "${reads2}" ]; then
        echo " Running Kraken2 in paired-end mode..."
        kraken2 \\
            --db ${params.kraken2_db} \\
            --paired \\
            --threads ${task.cpus} \\
            --output ${id}_kraken2_output.txt \\
            --report ${id}_kraken2_report.txt \\
            --memory-mapping \\
            ${reads1} ${reads2}
    else
        echo " Running Kraken2 in single-end mode..."
        kraken2 \\
            --db ${params.kraken2_db} \\
            --threads ${task.cpus} \\
            --output ${id}_kraken2_output.txt \\
            --report ${id}_kraken2_report.txt \\
            ${reads1}
    fi

    # Verify output files
    if [ ! -f "${id}_kraken2_report.txt" ] || [ ! -f "${id}_kraken2_output.txt" ]; then
        echo " Error: Kraken2 failed to generate results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " Kraken2 analysis completed successfully for sample: $id"
    """
}
