// CheckV viral genome completion and host-contamination assessment
process checkv {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/checkv", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("checkv_${id}"), emit: report
        tuple val(id), path("checkv_${id}/quality_summary.tsv"), emit: quality_summary

    script:
    """
    mkdir -p checkv_${id}
    if [ -s "${contigs}" ] && grep -q '^>' "${contigs}"; then
        checkv end_to_end \
            -t ${task.cpus} \
            -d ${params.checkv_db} \
            ${contigs} \
            checkv_${id}
    else
        printf "contig_id\tcontig_length\tprovirus\tviral_genes\thost_genes\tcheckv_quality\tmiuvig_quality\tcompleteness\tcompleteness_method\tcontamination\tkmer_freq\twarnings\n" > checkv_${id}/quality_summary.tsv
    fi
    """
}
