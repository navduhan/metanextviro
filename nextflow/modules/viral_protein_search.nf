// Optional ultra-sensitive DIAMOND protein search against curated viral protein DB (e.g. RVDB)
process viral_protein_search {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/novel_virus_detection/details", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(candidate_orfs)

    output:
        tuple val(id), path("${id}_viral_protein_hits.tsv"), emit: vp_hits
        tuple val(id), path("${id}_raw_viral_protein.txt"), emit: raw_vp

    script:
    """
    set -euo pipefail

    if [ -s "${candidate_orfs}" ] && grep -q '^>' "${candidate_orfs}"; then
        diamond blastp \
            --ultra-sensitive \
            --query ${candidate_orfs} \
            --db ${params.viral_protein_db} \
            --evalue ${params.viral_protein_evalue} \
            --max-target-seqs 10 \
            --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovhsp evalue bitscore qlen slen stitle \
            --threads ${task.cpus} \
            --out ${id}_raw_viral_protein.txt
    else
        : > ${id}_raw_viral_protein.txt
    fi

    python3 ${workflow.projectDir}/nextflow/bin/parse_discovery_hits.py \
        --mode viral_protein \
        -i ${id}_raw_viral_protein.txt \
        -o ${id}_viral_protein_hits.tsv
    """
}
