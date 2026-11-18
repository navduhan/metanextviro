// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Runs create_samplesheet.py locally to build a validated CSV samplesheet from a directory of paired FASTQ files.

process create_samplesheet {
    tag "$reads_dir"
    executor 'local'
    cpus 1
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${out_dir}", mode: 'copy', overwrite: true, failOnError: true

    input:
        val reads_dir
        val out_dir
        val out_name

    output:
        path "${out_name}", emit: csv

    script:
    def recArg = params.recursive_reads ? '--recursive' : ''
    """
    set -euo pipefail
    python3 ${workflow.projectDir}/bin/create_samplesheet.py \
        --reads-dir "${reads_dir}" \
        --output "${out_name}" \
        ${recArg}
    """
}
