// VirFinder viral classification
process virfinder {
    tag "$id"
    label 'process_medium'

    publishDir "${params.outdir}/virfinder", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("virfinder_${id}.txt"), emit: results

    script:
    """
    Rscript -e 'library(VirFinder); vf.run("${contigs}", out.file="virfinder_${id}.txt", nthread=${task.cpus})'
    """
} 