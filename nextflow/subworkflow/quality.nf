// Author: Naveen Duhan

include { fastqc } from '../modules/fastqc.nf'

workflow QUALITY {
    take:
        reads1_ch
        reads2_ch

    main:
        // Run FastQC on both read files
        fastqc(reads1_ch.join(reads2_ch))

    emit:
        reports = fastqc.out.fastqc_report
} 