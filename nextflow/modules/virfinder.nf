// VirFinder viral classification
process virfinder {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/virfinder", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("virfinder_${id}_full.txt"), path("virfinder_${id}_filtered.txt"), emit: results

    script:
    """
    Rscript ${projectDir}/nextflow/bin/run_virfinder.R \\
        ${contigs} \\
        virfinder_${id}_full.txt \\
        virfinder_${id}_filtered.txt
    """
} 