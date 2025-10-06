// nextflow/subworkflow/coverage_analysis.nf

include { coverage } from '../modules/coverage.nf'
include { coverage_plot } from '../modules/coverage_plot.nf'

workflow COVERAGE_ANALYSIS {
    take:
        contigs
        reads1
        reads2

    main:
        coverage_input = contigs
            .join(reads1)
            .join(reads2)
        coverage(coverage_input)

        coverage_plot_input = coverage.out.stats
        coverage_plot(coverage_plot_input)

    emit:
        bam = coverage.out.bam
        stats = coverage.out.stats
        plot = coverage_plot.out.plot
        distribution_plot = coverage_plot.out.distribution_plot
}
