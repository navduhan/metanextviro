// Author: Naveen Duhan

process ORGANIZE_CONTIGS {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/organized_contigs", mode: 'copy'

    input:
        tuple val(id), path(blast_results), path(contigs)

    output:
        tuple val(id), path("${id}"), emit: organized_dir
        tuple val(id), path("${id}/classification_summary.txt"), emit: summary

    script:
        """
        python3 ${workflow.projectDir}/nextflow/bin/organize_contigs_by_taxonomy.py \\
            --blast_results ${blast_results} \\
            --fasta_file ${contigs} \\
            --output_dir . \\
            --sample_id ${id}
        """
}

workflow CONTIG_ORGANIZATION {
    take:
        blast_results_ch    // Channel: [ val(id), [path(blast_results), ...] ]
        contigs_ch         // Channel: [ val(id), path(contigs) ]

    main:
        // Join the channels by ID to ensure correct sample pairing
        ch_input = blast_results_ch.join(contigs_ch)

        // Organize contigs by taxonomy
        ORGANIZE_CONTIGS(ch_input)

    emit:
        organized_dirs = ORGANIZE_CONTIGS.out.organized_dir
        summaries = ORGANIZE_CONTIGS.out.summary
} 