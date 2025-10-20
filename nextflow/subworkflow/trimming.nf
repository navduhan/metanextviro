// Author: Naveen Duhan

include { fastp } from '../modules/fastp.nf'
include { flexbar } from "../modules/flexbar"
include { trim_galore } from "../modules/trim-galore"

workflow TRIMMING {

    take:
        raw_reads1
        raw_reads2

    main:
        if (params.trimming_tool == "fastp") {
            fastp(raw_reads1.join(raw_reads2))
        } else if (params.trimming_tool == "flexbar") {
            flexbar(raw_reads1.join(raw_reads2))
        } else if (params.trimming_tool == "trim_galore") {
            trim_galore(raw_reads1.join(raw_reads2))
        } else {
            error "Invalid trimming tool specified in params.trimming_tool: '${params.trimming_tool}'. Please use 'fastp', 'flexbar' or 'trim_galore'."
        }

    emit:
        clean_reads1 = params.trimming_tool == "fastp" ? fastp.out.trimmed_reads1 :
                       params.trimming_tool == "flexbar" ? flexbar.out.clean_reads1 :
                       params.trimming_tool == "trim_galore" ? trim_galore.out.clean_reads1 :
                       null

        clean_reads2 = params.trimming_tool == "fastp" ? fastp.out.trimmed_reads2 :
                       params.trimming_tool == "flexbar" ? flexbar.out.clean_reads2 :
                       params.trimming_tool == "trim_galore" ? trim_galore.out.clean_reads2 :
                       null
}