// Author: Naveen Duhan

process quast {
    tag "$meta.id"  // Tag the task with the sample ID for traceability
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/assembly_stats", mode: 'copy', overwrite: true

    input:
        tuple val(meta), path(contigs)  // Input: Sample metadata and contig file

    output:
        tuple val(meta), path("assembly_stats/${meta.id}_quast"), emit: report
        path "versions.yml", emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
        def args = task.ext.args ?: ''
        def prefix = task.ext.prefix ?: "${meta.id}"
        """
        # Log the start of the process
        echo " Starting QUAST analysis for sample: ${meta.id}"
        echo "Input contig file: ${contigs}"

        # Create output directory
        mkdir -p assembly_stats/${meta.id}_quast

        # Run QUAST
        quast.py \\
            --output-dir assembly_stats/${meta.id}_quast \\
            --threads ${task.cpus} \\
            $args \\
            $contigs

        # Verify output
        if [ ! -f "assembly_stats/${meta.id}_quast/report.txt" ]; then
            echo " Error: QUAST failed to generate report for sample: ${meta.id}" >&2
            exit 1
        fi

        # Create versions file
        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            quast: \$(quast.py --version | sed 's/QUAST v//;s/ .*\$//')
        END_VERSIONS

        # Log successful completion
        echo " QUAST analysis completed successfully for sample: ${meta.id}"
        """

    stub:
        def prefix = task.ext.prefix ?: "${meta.id}"
        """
        mkdir -p assembly_stats/${meta.id}_quast
        touch assembly_stats/${meta.id}_quast/report.txt
        touch assembly_stats/${meta.id}_quast/report.tsv
        touch assembly_stats/${meta.id}_quast/report.html
        touch versions.yml
        """
} 