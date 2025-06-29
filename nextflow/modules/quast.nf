// Author: Naveen Duhan

process quast {
    tag "$meta.id"
    label 'process_medium'

    publishDir "${params.outdir}/assembly_stats", mode: 'copy'

    input:
        tuple val(meta), path(contigs)

    output:
        tuple val(meta), path("${meta.id}_quast"), emit: report
        path "versions.yml", emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
        def args = task.ext.args ?: ''
        def prefix = task.ext.prefix ?: "${meta.id}"
        """
        # Create output directory
        mkdir -p ${meta.id}_quast

        # Run QUAST
        quast.py \\
            --output-dir ${meta.id}_quast \\
            --threads ${task.cpus} \\
            $args \\
            $contigs

        # Create versions file
        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            quast: \$(quast.py --version | sed 's/QUAST v//;s/ .*\$//')
        END_VERSIONS
        """

    stub:
        def prefix = task.ext.prefix ?: "${meta.id}"
        """
        mkdir -p ${meta.id}_quast
        touch ${meta.id}_quast/report.txt
        touch ${meta.id}_quast/report.tsv
        touch ${meta.id}_quast/report.html
        touch versions.yml
        """
} 