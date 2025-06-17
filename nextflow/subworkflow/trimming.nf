// Author: Naveen Duhan

include { fastp } from '../modules/fastp.nf'
include { flexbar } from '../modules/flexbar.nf'
include { trim_galore } from '../modules/trim_galore.nf'

process TRIMMING {
    input:
        val reads1
        val reads2

    output:
        path "*_1.fastq.gz", emit: clean_reads1
        path "*_2.fastq.gz", emit: clean_reads2

    script:
        if (params.trimmer == 'fastp') {
            """
            fastp -i ${reads1} -I ${reads2} -o trimmed_1.fastq.gz -O trimmed_2.fastq.gz
            """
        } else if (params.trimmer == 'flexbar') {
            """
            flexbar -r ${reads1} -p ${reads2} -t trimmed
            """
        } else if (params.trimmer == 'trim_galore') {
            """
            trim_galore --paired ${reads1} ${reads2}
            """
        } else {
            error "Invalid trimmer specified: ${params.trimmer}. Choose from: fastp, flexbar, trim_galore"
        }
} 