// Author: Naveen Duhan

include { fastp } from '../modules/fastp.nf'
include { flexbar } from '../modules/flexbar.nf'
include { trim_galore } from '../modules/trim_galore.nf'

workflow TRIMMING {
    take:
        reads1
        reads2

    main:
        // Select trimming tool based on params.trimmer
        trimmed_reads = if (params.trimmer == 'fastp') {
            fastp(reads1, reads2)
            fastp.out.clean_reads
        } else if (params.trimmer == 'flexbar') {
            flexbar(reads1, reads2)
            flexbar.out.clean_reads
        } else if (params.trimmer == 'trim_galore') {
            trim_galore(reads1, reads2)
            trim_galore.out.clean_reads
        } else {
            error "Invalid trimmer specified: ${params.trimmer}. Choose from: fastp, flexbar, trim_galore"
        }

    emit:
        clean_reads1 = trimmed_reads.map { meta, reads -> reads[0] }
        clean_reads2 = trimmed_reads.map { meta, reads -> reads[1] }
} 