// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Converts Kraken2 taxonomic reports into interactive Krona HTML charts using ktImportTaxonomy.

process krona {
    tag "$id"  // Tag each task with the sample ID for traceability

    label 'low'  // Assign a label for resource management
    conda "${projectDir}/envs/core.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}/krona_results", mode: params.publish_mode, overwrite: true, failOnError: true  // Define output directory

    input:
        tuple val(id), path(kraken_report)  // Input: Kraken2 report file

    output:
        tuple val(id), path("${id}_krona.html"), emit: krona_html

    script:
    """
    # Log the start of the process
    echo " Starting Krona visualization for sample: $id"
    echo "Input Kraken2 report: ${kraken_report}"

    # Generate Krona HTML visualization
    ktImportTaxonomy \
        -t 5 \
        -m 3 \
        -o ${id}_krona.html \
        ${kraken_report}

    # Verify the output file
    if [ ! -f "${id}_krona.html" ]; then
        echo " Error: Krona failed to generate HTML for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " Krona visualization completed successfully for sample: $id"
    """
}
