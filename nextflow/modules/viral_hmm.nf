// Optional viral hallmark profile-HMM scan with VOGDB/ICTV taxonomic lineage resolution
process viral_hmm {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/novel_virus_detection/details", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(candidate_orfs)

    output:
        tuple val(id), path("${id}_hallmark_hmm_hits.tsv"), emit: hmm_hits
        tuple val(id), path("${id}_raw_hmm_domtbl.txt"), emit: raw_domtbl

    script:
    def taxArg = params.taxonomy_db ? "--taxonomy_db '" + file(params.taxonomy_db).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    def hmmTaxArg = params.viral_hmm_taxonomy ? "--hmm_taxonomy '" + file(params.viral_hmm_taxonomy).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    """
    set -euo pipefail

    if [ -s "${candidate_orfs}" ] && grep -q '^>' "${candidate_orfs}"; then
        hmmsearch \
            --noali \
            -E ${params.hmm_evalue} \
            --domE ${params.hmm_evalue} \
            --cpu ${task.cpus} \
            --domtblout ${id}_raw_hmm_domtbl.txt \
            ${params.viral_hmm_db} \
            ${candidate_orfs} > /dev/null
    else
        : > ${id}_raw_hmm_domtbl.txt
    fi

    python3 ${workflow.projectDir}/nextflow/bin/parse_discovery_hits.py \
        --mode hmm \
        -i ${id}_raw_hmm_domtbl.txt \
        -o ${id}_hallmark_hmm_hits.tsv \
        ${taxArg} ${hmmTaxArg}
    """
}
