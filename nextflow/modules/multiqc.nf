// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Aggregates FastQC and other module quality metrics into a single MultiQC HTML report and data directory.

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