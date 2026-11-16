// Optional geNomad marker + neural virus/plasmid/provirus classification
process genomad {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/genomad", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("genomad_${id}"), emit: report_dir
        tuple val(id), path("genomad_${id}/${id}_virus_summary.tsv"), emit: virus_summary
        tuple val(id), path("genomad_${id}/${id}_plasmid_summary.tsv"), emit: plasmid_summary

    script:
    """
    set -euo pipefail
    mkdir -p genomad_${id}

    if [ -s "${contigs}" ] && grep -q '^>' "${contigs}"; then
        genomad end-to-end \
            --cleanup \
            --threads ${task.cpus} \
            ${contigs} \
            genomad_${id} \
            ${params.genomad_db}

        VIR_SUM=\$(find genomad_${id} -name "*_virus_summary.tsv" | head -n 1 || true)
        PLAS_SUM=\$(find genomad_${id} -name "*_plasmid_summary.tsv" | head -n 1 || true)

        if [ -n "\$VIR_SUM" ] && [ -f "\$VIR_SUM" ]; then
            cp "\$VIR_SUM" "genomad_${id}/${id}_virus_summary.tsv"
        else
            printf "seq_name\tlength\ttopology\tcoordinates\tn_genes\tgenetic_code\tvirus_score\tfdr\tn_hallmarks\tmarker_enrichment\ttaxonomy\n" > "genomad_${id}/${id}_virus_summary.tsv"
        fi

        if [ -n "\$PLAS_SUM" ] && [ -f "\$PLAS_SUM" ]; then
            cp "\$PLAS_SUM" "genomad_${id}/${id}_plasmid_summary.tsv"
        else
            printf "seq_name\tlength\ttopology\tn_genes\tgenetic_code\tplasmid_score\tfdr\tn_hallmarks\tmarker_enrichment\tconjugation_genes\tamr_genes\n" > "genomad_${id}/${id}_plasmid_summary.tsv"
        fi
    else
        printf "seq_name\tlength\ttopology\tcoordinates\tn_genes\tgenetic_code\tvirus_score\tfdr\tn_hallmarks\tmarker_enrichment\ttaxonomy\n" > "genomad_${id}/${id}_virus_summary.tsv"
        printf "seq_name\tlength\ttopology\tn_genes\tgenetic_code\tplasmid_score\tfdr\tn_hallmarks\tmarker_enrichment\tconjugation_genes\tamr_genes\n" > "genomad_${id}/${id}_plasmid_summary.tsv"
    fi
    """
}
