// Preprocessing subworkflow: QC + Trimming + MultiQC

include { fastqc } from '../modules/fastqc.nf'
include { fastp } from '../modules/fastp.nf'
include { flexbar } from '../modules/flexbar.nf'
include { trim_galore } from '../modules/trim-galore.nf'
include { multiqc } from '../modules/multiqc.nf'

workflow PREPROCESSING {
    take:
        reads1_ch
        reads2_ch

    main:
        // FastQC on raw reads
        fastqc_raw1 = fastqc(reads1_ch)
        fastqc_raw2 = fastqc(reads2_ch)

        // Trimming tool selection
        trimmed =
            params.trimming_tool == 'fastp' ? fastp(reads1_ch.combine(reads2_ch)) :
            params.trimming_tool == 'flexbar' ? flexbar(reads1_ch.combine(reads2_ch)) :
            params.trimming_tool == 'trim_galore' ? trim_galore(reads1_ch.combine(reads2_ch)) :
            error("Invalid trimming tool specified in params.trimming_tool: '${params.trimming_tool}'. Please use 'fastp', 'flexbar', or 'trim_galore'.")

        // FastQC on trimmed reads
        fastqc_trim1 = fastqc(trimmed.out.trimmed_reads1)
        fastqc_trim2 = fastqc(trimmed.out.trimmed_reads2)

        // Collect all QC reports for MultiQC
        all_qc_reports = fastqc_raw1.out.reports.mix(fastqc_raw2.out.reports)
            .mix(fastqc_trim1.out.reports)
            .mix(fastqc_trim2.out.reports)

        multiqc(all_qc_reports)

    emit:
        trimmed_reads1 = trimmed.out.trimmed_reads1
        trimmed_reads2 = trimmed.out.trimmed_reads2
        multiqc_report = multiqc.out.report
} 