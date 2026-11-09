// Coverage analysis (read mapping and stats)
process coverage {
    tag "$id"
    label 'medium'

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
    ${projectDir}/nextflow/bin/calculate_contig_coverage.sh ${id}.bam coverage_${id}.txt ${id}.idxstats.txt
    """
} 