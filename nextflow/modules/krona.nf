// Author: Naveen Duhan
// SPDX-License-Identifier: MIT
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
    def resolvedTaxDir = (params.db_dir && file("${params.db_dir}/taxonomy").exists())
        ? file("${params.db_dir}/taxonomy").toAbsolutePath().toString()
        : ''
    """
    # Log the start of the process
    echo " Starting Krona visualization for sample: $id"
    echo "Input Kraken2 report: ${kraken_report}"

    # Resolve or build Krona taxonomy.tab via ktUpdateTaxonomy.sh
    TAX_ARG=""
    KRONA_DEFAULT_TAX="\$(dirname "\$(command -v ktImportTaxonomy)")/../opt/krona/taxonomy/taxonomy.tab"
    if [ -n "${resolvedTaxDir}" ] && [ -s "${resolvedTaxDir}/taxonomy.tab" ]; then
        TAX_ARG="-tax ${resolvedTaxDir}"
    elif [ -s "\$KRONA_DEFAULT_TAX" ]; then
        TAX_ARG=""
    elif [ -n "${resolvedTaxDir}" ] && [ -s "${resolvedTaxDir}/names.dmp" ] && [ -s "${resolvedTaxDir}/nodes.dmp" ]; then
        mkdir -p krona_tax
        ln -sf "${resolvedTaxDir}/names.dmp" krona_tax/names.dmp
        ln -sf "${resolvedTaxDir}/nodes.dmp" krona_tax/nodes.dmp
        ktUpdateTaxonomy.sh --only-build --preserve krona_tax
        TAX_ARG="-tax krona_tax"
    else
        mkdir -p krona_tax
        ktUpdateTaxonomy.sh krona_tax
        TAX_ARG="-tax krona_tax"
    fi

    # Generate Krona HTML visualization
    ktImportTaxonomy \
        \$TAX_ARG \
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
