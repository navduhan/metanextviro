// Author: Naveen Duhan

// VirFinder viral classification
process virfinder {
    tag "$id"  // Tag the task with the sample ID for traceability
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/virfinder_results", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs)  // Input: Sample ID and contig file

    output:
        tuple val(id), path("virfinder_${id}_full.txt"), emit: full_results
        tuple val(id), path("virfinder_${id}_filtered.txt"), emit: filtered_results

    script:
    """
    # Log the start of the process
    echo " Starting VirFinder analysis for sample: $id"
    echo "Input contig file: ${contigs}"

    # Run VirFinder R script
    Rscript ${projectDir}/nextflow/bin/run_virfinder.R \\
        ${contigs} \\
        virfinder_${id}_full.txt \\
        virfinder_${id}_filtered.txt

    # Verify output files
    if [ ! -f "virfinder_${id}_full.txt" ] || [ ! -f "virfinder_${id}_filtered.txt" ]; then
        echo " Error: VirFinder failed to generate results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " VirFinder analysis completed successfully for sample: $id"
    """
} 