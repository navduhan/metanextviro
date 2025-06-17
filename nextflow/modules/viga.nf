// VIGA viral genome annotation
process viga {
    tag "$id"
    label 'process_medium'

    publishDir "${params.outdir}/viga", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("viga_${id}"), emit: annotation

    script:
    """
    mkdir -p viga_${id}
    viga --contigs ${contigs} --outdir viga_${id} --prefix ${id} --threads ${task.cpus}
    """
} 