// Author: Naveen Duhan

include { blastn } from "../modules/blastn"
include { blastn_viruses } from "../modules/blastn_viruses"
include { blastx } from "../modules/blastx"

workflow BLAST_ANNOTATION {
    take:
        fasta_file // Input FASTA file(s)

    main:
        // Initialize empty channels for BLAST results
        def blastn_viruses_channel = Channel.empty()
        def blastn_channel = Channel.empty()
        def blastx_channel = Channel.empty()

        // Log the selected BLAST options
        println "Selected BLAST options: ${params.blast_options}"

        // Execute relevant BLAST processes based on selected options
        if ('viruses' in params.blast_options || 'all' in params.blast_options) {
            println "Running BLASTN against the viruses database..."
            blastn_viruses_channel = blastn_viruses(fasta_file)
        }

        if ('nt' in params.blast_options || 'all' in params.blast_options) {
            println "Running BLASTN against the NT database..."
            blastn_channel = blastn(fasta_file)
        }

        if ('nr' in params.blast_options || 'all' in params.blast_options) {
            println "Running BLASTX against the NR database..."
            blastx_channel = blastx(fasta_file)
        }

    emit:
        // Emit results for each BLAST option
        blastn_results_viruses = blastn_viruses_channel.formatted_blast_output
        blastn_results_nt = blastn_channel.formatted_blast_output
        blastx_results_nr = blastx_channel.formatted_blast_output
}

