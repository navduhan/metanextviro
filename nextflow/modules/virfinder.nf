// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Runs run_virfinder.R on assembled or triaged contigs to compute 8-mer viral scores, FDR q-values, and sequence complexity flags.

process virfinder {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/virfinder", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("virfinder_${id}_full.txt"), path("virfinder_${id}_filtered.txt"), emit: results
        tuple val(id), path("virfinder_${id}_full.txt"), emit: full_table

    script:
    """
    Rscript ${workflow.projectDir}/bin/run_virfinder.R \
        ${contigs} \
        virfinder_${id}_full.txt \
        virfinder_${id}_filtered.txt \
        ${params.virfinder_min_score} \
        ${params.virfinder_max_qvalue} \
        ${params.virfinder_moderate_score}
    """
}
