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

        // Accept config/params-file lists and comma-separated command-line values.
        def selected_options = (params.blast_options instanceof Collection
            ? params.blast_options
            : params.blast_options.toString().split(','))
            .collect { option -> option.toString().trim().toLowerCase() }
            .collect { option -> option == 'nt_viruses' ? 'viruses' : option }
            .unique()

        def invalid_options = selected_options.findAll { option -> !(option in ['all', 'viruses', 'nt', 'nr']) }
        if (!selected_options || invalid_options) {
            error "Invalid --blast_options: ${params.blast_options}. Use viruses (or nt_viruses), nt, nr, all, or a comma-separated combination."
        }
        println "Selected BLAST options: ${selected_options}"

        // Execute relevant BLAST processes based on selected options
        if ('viruses' in selected_options || 'all' in selected_options) {
            println "Running BLASTN against the viruses database..."
            blastn_viruses(fasta_file)
            blastn_viruses_channel = blastn_viruses.out.formatted_blast_output
        }

        if ('nt' in selected_options || 'all' in selected_options) {
            println "Running BLASTN against the NT database..."
            blastn(fasta_file)
            blastn_channel = blastn.out.formatted_blast_output
        }

        if ('nr' in selected_options || 'all' in selected_options) {
            println "Running BLASTX against the NR database..."
            blastx(fasta_file)
            blastx_channel = blastx.out.formatted_blast_output
        }

    emit:
        // Emit results for each BLAST option
        blastn_results_viruses = blastn_viruses_channel
        blastn_results_nt = blastn_channel
        blastx_results_nr = blastx_channel
}

