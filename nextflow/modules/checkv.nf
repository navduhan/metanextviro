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
    def baseCheckv = params.checkv_db ?: file("${params.db_dir}/checkv").toAbsolutePath().toString()
    """
    mkdir -p checkv_${id}
    if [ -s "${contigs}" ] && grep -q '^>' "${contigs}"; then
        CHECKV_DB="${baseCheckv}"
        if [ ! -f "\$CHECKV_DB/genome_db/checkv_reps.dmnd" ]; then
            SUB_DMND=\$(find "\$CHECKV_DB" -name "checkv_reps.dmnd" 2>/dev/null | head -n 1 || true)
            if [ -n "\$SUB_DMND" ]; then
                CHECKV_DB=\$(dirname "\$(dirname "\$SUB_DMND")")
            fi
        fi
        checkv end_to_end \
            -t ${task.cpus} \
            -d "\$CHECKV_DB" \
            ${contigs} \
            checkv_${id}
    else
        printf "contig_id\tcontig_length\tprovirus\tviral_genes\thost_genes\tcheckv_quality\tmiuvig_quality\tcompleteness\tcompleteness_method\tcontamination\tkmer_freq\twarnings\n" > checkv_${id}/quality_summary.tsv
    fi
    """
}
