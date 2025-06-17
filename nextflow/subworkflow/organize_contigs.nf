// Author: Naveen Duhan

process ORGANIZE_CONTIGS {
    tag "$meta.id"
    label 'process_low'

    publishDir "${params.outdir}/organized_contigs", mode: 'copy'

    input:
        tuple val(meta), path(blast_results)
        tuple val(meta2), path(contigs)

    output:
        tuple val(meta), path("${meta.id}"), emit: organized_dir
        tuple val(meta), path("${meta.id}/classification_summary.txt"), emit: summary

    script:
        """
        python3 ${workflow.projectDir}/nextflow/bin/organize_contigs_by_taxonomy.py \\
            --blast_results ${blast_results} \\
            --fasta_file ${contigs} \\
            --output_dir . \\
            --sample_id ${meta.id}
        """
}

workflow CONTIG_ORGANIZATION {
    take:
        blast_results_ch    // Channel: [ val(meta), path(blast_results) ]
        contigs_ch         // Channel: [ val(meta), path(contigs) ]

    main:
        // Combine channels by meta.id
        combined_ch = blast_results_ch.combine(contigs_ch, by: 0)
        
        // Organize contigs by taxonomy
        ORGANIZE_CONTIGS(combined_ch)

    emit:
        organized_dirs = ORGANIZE_CONTIGS.out.organized_dir
        summaries = ORGANIZE_CONTIGS.out.summary
} 