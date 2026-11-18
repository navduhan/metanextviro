// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Searches translated candidate ORFs against viral hallmark profile HMMs with hmmsearch and resolves HMM taxonomic lineages using parse_discovery_hits.py.

process viral_hmm {
    tag "$id"
    label 'medium'
    conda "${projectDir}/envs/discovery.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}/novel_virus_detection/details", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(candidate_orfs)

    output:
        tuple val(id), path("${id}_hallmark_hmm_hits.tsv"), emit: hmm_hits
        tuple val(id), path("${id}_raw_hmm_domtbl.txt"), emit: raw_domtbl

    script:
    def resolvedHmmDb = params.viral_hmm_db ?: file("${params.db_dir}/viral_hmm/vog_hallmarks.hmm").toAbsolutePath().toString()
    def resolvedTax = params.taxonomy_db ?: (
        (params.db_dir && (params.auto_download_dbs || params.setup_databases || file("${params.db_dir}/taxonomy/taxa.sqlite").exists()))
            ? file("${params.db_dir}/taxonomy/taxa.sqlite").toAbsolutePath().toString()
            : null
    )
    def resolvedHmmTax = params.viral_hmm_taxonomy ?: (
        (params.db_dir && (params.auto_download_dbs || params.setup_databases || file("${params.db_dir}/viral_hmm/vog_hmm_taxonomy.tsv").exists()))
            ? file("${params.db_dir}/viral_hmm/vog_hmm_taxonomy.tsv").toAbsolutePath().toString()
            : null
    )
    def taxArg = resolvedTax ? "--taxonomy_db '" + file(resolvedTax).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    def hmmTaxArg = resolvedHmmTax ? "--hmm_taxonomy '" + file(resolvedHmmTax).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    """
    set -euo pipefail

    if [ -s "${candidate_orfs}" ] && grep -q '^>' "${candidate_orfs}"; then
        hmmsearch \
            --noali \
            -E ${params.hmm_evalue} \
            --domE ${params.hmm_evalue} \
            --cpu ${task.cpus} \
            --domtblout ${id}_raw_hmm_domtbl.txt \
            "${resolvedHmmDb}" \
            ${candidate_orfs} > /dev/null
    else
        : > ${id}_raw_hmm_domtbl.txt
    fi

    python3 ${workflow.projectDir}/bin/parse_discovery_hits.py \
        --mode hmm \
        -i ${id}_raw_hmm_domtbl.txt \
        -o ${id}_hallmark_hmm_hits.tsv \
        ${taxArg} ${hmmTaxArg}
    """
}
