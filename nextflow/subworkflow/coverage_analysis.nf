// Author: Naveen Duhan
// SPDX-License-Identifier: MIT
// Description: Connects assembled contigs and trimmed paired reads to the coverage module and emits whole-contig depth tables and BAM alignments.

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
        mapping_log = coverage.out.mapping_log
        plot = coverage_plot.out.plot
        distribution_plot = coverage_plot.out.distribution_plot
}
