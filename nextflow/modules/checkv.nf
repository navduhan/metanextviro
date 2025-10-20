// CheckV viral genome completion assessment
process checkv {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/checkv", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("checkv_${id}"), emit: report

    script:
    """
    mkdir -p checkv_${id}
    checkv end_to_end \
        -t ${task.cpus} \
        -d ${params.checkv_db} \
        ${contigs} \
        checkv_${id}
    """
} 