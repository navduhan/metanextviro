// Author: Naveen Duhan

include { parse_input } from '../modules/parse_input.nf'

workflow INPUT_PARSER {
    take:
        samplesheet

    main:
        parse_input(samplesheet)

    emit:
        reads1 = parse_input.out.reads1
        reads2 = parse_input.out.reads2
}
