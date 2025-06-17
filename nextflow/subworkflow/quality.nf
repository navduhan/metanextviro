// Author: Naveen Duhan

include { fastqc } from '../modules/fastqc.nf'
include { multiqc } from '../modules/multiqc.nf'

workflow QUALITY {
    take:
        reads1_ch
        reads2_ch

    main:
        // Run FastQC on both read files
        fastqc(reads1_ch.join(reads2_ch))
        
        // Run MultiQC on all FastQC results
        multiqc(fastqc.out.html)

    emit:
        reports = fastqc.out.html
        multiqc_report = multiqc.out.html
} 