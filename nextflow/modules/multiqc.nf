// Author: Naveen Duhan

// MultiQC aggregation
process multiqc {
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/multiqc_results", mode: 'copy', overwrite: true

    input:
        path qc_reports  // Input: QC report files from various tools

    output:
        path "multiqc_report.html", emit: report
        path "multiqc_data", emit: data

    script:
    """
    # Log the start of the process
    echo " Starting MultiQC aggregation"
    echo "Input QC reports: ${qc_reports}"

    # Run MultiQC to aggregate all QC reports
    multiqc ${qc_reports} -o . --force

    # Verify output
    if [ ! -f "multiqc_report.html" ]; then
        echo " Error: MultiQC failed to generate report" >&2
        exit 1
    fi

    # Log successful completion
    echo " MultiQC aggregation completed successfully"
    """
} 