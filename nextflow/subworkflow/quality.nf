// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Pairs sample read channels and runs FastQC to generate initial read quality reports.

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