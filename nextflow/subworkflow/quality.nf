// Author: Naveen Duhan

include { fastqc } from '../modules/fastqc.nf'
include { multiqc } from '../modules/multiqc.nf'

process QUALITY {
    input:
        val reads1
        val reads2

    output:
        path "*.html", emit: reports
        path "multiqc_report.html", emit: multiqc_report

    script:
        """
        fastqc ${reads1} ${reads2}
        multiqc .
        """
} 