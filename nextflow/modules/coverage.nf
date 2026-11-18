// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Builds a Bowtie2 index for assembled contigs, maps trimmed paired reads with SAMtools sorting, and runs calculate_contig_coverage.sh to compute whole-contig depth and breadth.

process coverage {
    tag "$id"
    label 'medium'
    conda "${projectDir}/envs/core.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}/coverage", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(contigs), path(reads1), path(reads2)

    output:
        tuple val(id), path("${id}.bam"), emit: bam
        tuple val(id), path("${id}.bam.bai"), emit: bai
        tuple val(id), path("${id}_index*.bt2*"), emit: mapping_index
        tuple val(id), path("${id}.mapping.log"), emit: mapping_log
        tuple val(id), path("${id}.idxstats.txt"), emit: idxstats
        tuple val(id), path("coverage_${id}.txt"), emit: stats

    script:
    """
    set -euo pipefail

    # Index the contigs
    bowtie2-build ${contigs} ${id}_index

    # Map reads to contigs
    bowtie2 -x ${id}_index -1 ${reads1} -2 ${reads2} 2> ${id}.mapping.log | \
        samtools sort -o ${id}.bam -
    samtools index ${id}.bam

    # Generate contig-level coverage stats
    ${projectDir}/bin/calculate_contig_coverage.sh ${id}.bam coverage_${id}.txt ${id}.idxstats.txt
    """
} 