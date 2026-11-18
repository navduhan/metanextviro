// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Aligns translated candidate ORFs against a RefSeq viral protein DIAMOND database and attaches NCBI lineages using parse_discovery_hits.py.

process viral_protein_search {
    tag "$id"
    label 'medium'
    conda "${projectDir}/envs/core.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}/novel_virus_detection/details", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(candidate_orfs)

    output:
        tuple val(id), path("${id}_viral_protein_hits.tsv"), emit: vp_hits
        tuple val(id), path("${id}_raw_viral_protein.txt"), emit: raw_vp

    script:
    def resolvedVpDb = params.viral_protein_db ?: file("${params.db_dir}/viral_proteins/refseq_viral_proteins.dmnd").toAbsolutePath().toString()
    def resolvedTax = params.taxonomy_db ?: (
        (params.db_dir && (params.auto_download_dbs || params.setup_databases || file("${params.db_dir}/taxonomy/taxa.sqlite").exists()))
            ? file("${params.db_dir}/taxonomy/taxa.sqlite").toAbsolutePath().toString()
            : null
    )
    def taxArg = resolvedTax ? "--taxonomy_db '" + file(resolvedTax).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    """
    set -euo pipefail

    if [ -s "${candidate_orfs}" ] && grep -q '^>' "${candidate_orfs}"; then
        diamond blastp \
            --ultra-sensitive \
            --query ${candidate_orfs} \
            --db "${resolvedVpDb}" \
            --evalue ${params.viral_protein_evalue} \
            --max-target-seqs 10 \
            --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovhsp evalue bitscore qlen slen stitle staxids \
            --threads ${task.cpus} \
            --out ${id}_raw_viral_protein.txt
    else
        : > ${id}_raw_viral_protein.txt
    fi

    python3 ${workflow.projectDir}/bin/parse_discovery_hits.py \
        --mode viral_protein \
        -i ${id}_raw_viral_protein.txt \
        -o ${id}_viral_protein_hits.tsv \
        ${taxArg}
    """
}
