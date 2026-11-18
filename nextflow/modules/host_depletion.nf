// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Aligns trimmed paired reads to a host reference genome with Bowtie2 and extracts unmapped read pairs with SAMtools before de novo assembly.

process host_depletion {
    tag "$id"
    label 'medium'
    conda "${projectDir}/envs/core.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}/host_depletion", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(reads1), path(reads2)

    output:
        tuple val(id), path("${id}_host_depleted_R1.fastq.gz"), emit: reads1
        tuple val(id), path("${id}_host_depleted_R2.fastq.gz"), emit: reads2
        tuple val(id), path("${id}_host_depletion_stats.txt"), emit: stats

    script:
    def hostFastaArg = params.host_fasta ? file(params.host_fasta).toAbsolutePath().toString() : ''
    def hostIndexArg = params.host_bowtie2_index ? params.host_bowtie2_index.toString() : ''
    """
    set -euo pipefail

    if [ -n "${hostIndexArg}" ]; then
        HOST_IDX="${hostIndexArg}"
    else
        mkdir -p host_bt2_idx
        bowtie2-build --threads ${task.cpus} "${hostFastaArg}" host_bt2_idx/host
        HOST_IDX="host_bt2_idx/host"
    fi

    bowtie2 \
        -x "\$HOST_IDX" \
        -1 ${reads1} \
        -2 ${reads2} \
        -p ${task.cpus} \
        --very-sensitive \
        2> ${id}_host_depletion_stats.txt \
    | samtools fastq \
        -@ ${task.cpus} \
        -f 12 -F 256 \
        -1 ${id}_host_depleted_R1.fastq.gz \
        -2 ${id}_host_depleted_R2.fastq.gz \
        -0 /dev/null \
        -s /dev/null \
        -n -
    """
}
