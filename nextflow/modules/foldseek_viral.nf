// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Runs optional Foldseek 3D structural homology searches on candidate viral ORFs and formats parsed alignments with parse_discovery_hits.py.

process foldseek_viral {
    tag "$id"
    label 'medium'
    conda "${projectDir}/envs/foldseek.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}/novel_virus_detection/details", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(candidate_orfs)

    output:
        tuple val(id), path("${id}_foldseek_hits.tsv"), emit: foldseek_hits
        tuple val(id), path("${id}_raw_foldseek.txt"), emit: raw_foldseek

    script:
    def prostArg = params.foldseek_prostt5_weights ? "--prostt5-model '${params.foldseek_prostt5_weights}'" : ''
    """
    set -euo pipefail

    if [ -s "${candidate_orfs}" ] && grep -q '^>' "${candidate_orfs}"; then
        mkdir -p foldseek_tmp
        foldseek easy-search \
            ${candidate_orfs} \
            ${params.foldseek_db} \
            ${id}_raw_foldseek.txt \
            foldseek_tmp \
            --threads ${task.cpus} \
            -e ${params.foldseek_evalue} \
            --format-output "query,target,pident,alnlen,qstart,qend,tstart,tend,evalue,bits,prob,theader" \
            ${prostArg}
        rm -rf foldseek_tmp
    else
        : > ${id}_raw_foldseek.txt
    fi

    python3 ${workflow.projectDir}/bin/parse_discovery_hits.py \
        --mode foldseek \
        -i ${id}_raw_foldseek.txt \
        -o ${id}_foldseek_hits.tsv
    """
}
