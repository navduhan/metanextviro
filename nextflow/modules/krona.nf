// Author: Naveen Duhan

// Krona taxonomic visualization
process krona {
    tag "$id"  // Tag each task with the sample ID for traceability

    label 'low'  // Assign a label for resource management

    publishDir "${params.outdir}/krona_results", mode: 'copy', overwrite: true  // Define output directory

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
