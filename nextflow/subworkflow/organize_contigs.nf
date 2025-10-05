// Author: Naveen Duhan

process ORGANIZE_CONTIGS {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/organized_contigs", mode: 'copy'

    input:
        tuple val(id), path(blast_results)
        tuple val(id2), path(contigs)

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
        blast_results_ch    // Channel: [ val(id), path(blast_results) ]
        contigs_ch         // Channel: [ val(id), path(contigs) ]

    main:
        // Organize contigs by taxonomy
        ORGANIZE_CONTIGS(blast_results_ch, contigs_ch)

    emit:
        organized_dirs = ORGANIZE_CONTIGS.out.organized_dir
        summaries = ORGANIZE_CONTIGS.out.summary
} 