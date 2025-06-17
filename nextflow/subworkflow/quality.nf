// Author: Naveen Duhan

include { fastqc } from '../modules/fastqc.nf'
include { multiqc } from '../modules/multiqc.nf'

workflow QUALITY {
    take:
        reads1
        reads2

    main:
        // Run FastQC on raw reads
        fastqc(reads1)
        fastqc(reads2)

        // Run MultiQC to aggregate FastQC reports
        multiqc(fastqc.out.reports)

    emit:
        reports = fastqc.out.reports
        multiqc_report = multiqc.out.report
} 