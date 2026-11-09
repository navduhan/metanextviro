// fastp paired-end trimming
process fastp {
    tag "$id"
    label 'low'
    publishDir "${params.outdir}/fastp", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(reads1), path(reads2)

    output:
        tuple val(id), path("${id}_fastp_trimmed_1.fq.gz"), emit: trimmed_reads1
        tuple val(id), path("${id}_fastp_trimmed_2.fq.gz"), emit: trimmed_reads2
        path "fastp_report_${id}.html", emit: report
        path "fastp_report_${id}.json", emit: json_report

    script:
    """
    fastp \
      -i ${reads1} \
      -I ${reads2} \
      -o ${id}_fastp_trimmed_1.fq.gz \
      -O ${id}_fastp_trimmed_2.fq.gz \
      --json fastp_report_${id}.json \
      --html fastp_report_${id}.html \
      --thread ${task.cpus}
    """
} 