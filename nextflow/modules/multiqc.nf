// MultiQC aggregation
process multiqc {
    label 'process_medium'
    publishDir "${params.outdir}/multiqc", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        path qc_reports

    output:
        path "multiqc_report.html", emit: report
        path "multiqc_data", emit: data

    script:
    """
    multiqc ${qc_reports} -o .
    """
} 