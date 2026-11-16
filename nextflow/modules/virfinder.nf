// Enhanced VirFinder viral classification (FDR q-value + complexity QC + descending sort)
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
    Rscript ${workflow.projectDir}/nextflow/bin/run_virfinder.R \
        ${contigs} \
        virfinder_${id}_full.txt \
        virfinder_${id}_filtered.txt \
        ${params.virfinder_min_score} \
        ${params.virfinder_max_qvalue} \
        ${params.virfinder_moderate_score}
    """
}
