// Coverage analysis (read mapping and stats)
process coverage {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/coverage", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs), path(reads1), path(reads2)

    output:
        tuple val(id), path("${id}.bam"), emit: bam
        tuple val(id), path("coverage_${id}.txt"), emit: stats

    script:
    """
    # Index the contigs
    bowtie2-build ${contigs} ${id}_index

    # Map reads to contigs
    bowtie2 -x ${id}_index -1 ${reads1} -2 ${reads2} | samtools view -bS - > ${id}.bam
    samtools sort -o ${id}.sorted.bam ${id}.bam
    mv ${id}.sorted.bam ${id}.bam
    samtools index ${id}.bam

    # Generate contig-level coverage stats
    ${projectDir}/nextflow/bin/calculate_contig_coverage.sh ${id}.bam coverage_${id}.txt
    """
} 