// Author: Naveen Duhan
// SPDX-License-Identifier: MIT
// Description: Aggregates FastQC and other module quality metrics into a single MultiQC HTML report and data directory.

process multiqc {
    label 'process_medium'
    conda "${projectDir}/envs/multiqc.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2' : 'quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2' }"
    publishDir "${params.outdir}/multiqc", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        path qc_reports

    output:
        path "multiqc_report.html", emit: report
        path "multiqc_data", emit: data

    script:
    """
    multiqc ${qc_reports} -o .
    """
} 