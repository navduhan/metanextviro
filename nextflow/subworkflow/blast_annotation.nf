// Author: Naveen Duhan

include { blastn } from '../modules/blastn.nf'
include { parse_blast } from '../modules/parse_blast.nf'

workflow BLAST_ANNOTATION {
    take:
        contigs_ch

    main:
        // Run BLASTN search
        blastn(contigs_ch)
        
        // Parse BLAST results
        parse_blast(blastn.out.results)

    emit:
        results = parse_blast.out.parsed_results
        raw_blast = blastn.out.results
}

