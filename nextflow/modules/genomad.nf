// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Runs optional geNomad end-to-end classification on candidate contigs to separate viral genomes, plasmids, and integrated proviruses.

process genomad {
    tag "$id"
    label 'medium'
    conda "${projectDir}/envs/genomad.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://quay.io/biocontainers/genomad:1.13.0--pyhdfd78af_0' : 'quay.io/biocontainers/genomad:1.13.0--pyhdfd78af_0' }"

    publishDir "${params.outdir}/genomad", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(contigs)

    output:
        tuple val(id), path("genomad_${id}"), emit: report_dir
        tuple val(id), path("genomad_${id}/${id}_virus_summary.tsv"), emit: virus_summary
        tuple val(id), path("genomad_${id}/${id}_plasmid_summary.tsv"), emit: plasmid_summary

    script:
    def baseGenomad = params.genomad_db ?: file("${params.db_dir}/genomad").toAbsolutePath().toString()
    """
    set -euo pipefail
    mkdir -p genomad_${id}

    if [ -s "${contigs}" ] && grep -q '^>' "${contigs}"; then
        GENOMAD_DB="${baseGenomad}"
        if [ ! -f "\$GENOMAD_DB/genomad_db" ] && [ -d "\$GENOMAD_DB/genomad_db" ]; then
            GENOMAD_DB="\$GENOMAD_DB/genomad_db"
        fi
        genomad end-to-end \
            --cleanup \
            --threads ${task.cpus} \
            ${contigs} \
            genomad_${id} \
            "\$GENOMAD_DB"

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
