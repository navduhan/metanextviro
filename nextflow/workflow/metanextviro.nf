// Author: Naveen Duhan

include { input_parser } from '../subworkflow/input_parser'
include { quality } from '../subworkflow/quality.nf'
include { trimming } from '../subworkflow/trimming.nf'
include {assembly} from '../subworkflow/assembly.nf'
include { blast_annotation } from '../subworkflow/blast_annotation.nf'

workflow metanextviro {

    take:

        ch_input

    main:

        // Parse input samplesheet
        input_parser(ch_input)

        // Capture output channels
        ch_reads1 = input_parser.out.reads1
        ch_reads2 = input_parser.out.reads2

        // Run pipeline steps
        quality(ch_reads1, ch_reads2)
        trimming(ch_reads1, ch_reads2)
        assembly(trimming.out.clean_reads1, trimming.out.clean_reads2)
        blast_annotation(assembly.out.contigs)


}