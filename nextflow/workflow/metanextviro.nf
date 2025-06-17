// Author: Naveen Duhan

include { INPUT_PARSER } from '../subworkflow/input_parser'
include { QUALITY } from '../subworkflow/quality.nf'
include { TRIMMING } from '../subworkflow/trimming.nf'
include { ASSEMBLY } from '../subworkflow/assembly.nf'
include { BLAST_ANNOTATION } from '../subworkflow/blast_annotation.nf'

workflow metanextviro {
    take:
        ch_input

    main:
        // Parse input samplesheet
        INPUT_PARSER(ch_input)

        // Capture output channels
        ch_reads1 = INPUT_PARSER.out.reads1
        ch_reads2 = INPUT_PARSER.out.reads2

        // Run pipeline steps
        QUALITY(ch_reads1, ch_reads2)
        TRIMMING(ch_reads1, ch_reads2)
        ASSEMBLY(TRIMMING.out.clean_reads1, TRIMMING.out.clean_reads2)
        BLAST_ANNOTATION(ASSEMBLY.out.contigs)

    emit:
        quality_reports = QUALITY.out.reports
        trimmed_reads1 = TRIMMING.out.clean_reads1
        trimmed_reads2 = TRIMMING.out.clean_reads2
        assembly_results = ASSEMBLY.out.contigs
        blast_results = BLAST_ANNOTATION.out.results
}