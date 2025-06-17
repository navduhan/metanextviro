// MultiQC aggregation
process multiqc {
    label 'process_medium'
    publishDir "${params.outdir}/multiqc", mode: 'copy', overwrite: true

    input:
        path qc_reports

    output:
        path "multiqc_report.html", emit: report

    script:
    """
    multiqc ${qc_reports} -o .
    """
} 