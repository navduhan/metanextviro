// Author: Naveen Duhan

// CheckV viral genome completion assessment
process checkv {
    tag "$id"  // Tag the task with the sample ID for traceability
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/checkv_results", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs)  // Input: Sample ID and contig file

    output:
        tuple val(id), path("checkv_${id}"), emit: report

    script:
    """
    # Log the start of the process
    echo " Starting CheckV analysis for sample: $id"
    echo "Input contig file: ${contigs}"
    echo "Using CheckV database: ${params.checkv_db}"

    # Create output directory
    mkdir -p checkv_${id}

    # Run CheckV end-to-end analysis
    checkv end_to_end \\
        -t ${task.cpus} \\
        -d ${params.checkv_db} \\
        ${contigs} \\
        checkv_${id}

    # Verify output directory and key files
    if [ ! -d "checkv_${id}" ] || [ ! -f "checkv_${id}/quality_summary.tsv" ]; then
        echo " Error: CheckV failed to generate results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " CheckV analysis completed successfully for sample: $id"
    """
} 