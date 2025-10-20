// Visualization subworkflow

include { html_report } from '../modules/html_report.nf'
include { coverage_plot } from '../modules/coverage_plot.nf'

workflow VISUALIZATION {
    take:
        kraken2_reports_ch
        fastqc_reports_ch
        coverage_stats_ch
        checkv_results_ch
        virfinder_full_ch
        virfinder_filtered_ch

    main:
        // Extract file paths from tuple channels for html_report
        kraken2_files = kraken2_reports_ch.map { id, path -> path }
        fastqc_files = fastqc_reports_ch.map { id, path -> path }
        coverage_files = coverage_stats_ch.map { id, path -> path }
        checkv_files = checkv_results_ch.map { id, path -> path }
        virfinder_full_files = virfinder_full_ch.map { id, full, filtered -> full }
        virfinder_filtered_files = virfinder_filtered_ch.map { id, full, filtered -> filtered }
        
        // Generate coverage plots
        coverage_plot(coverage_stats_ch)
        
        // Generate HTML report
        html_report(
            kraken2_files,
            fastqc_files,
            coverage_files,
            checkv_files,
            virfinder_full_files,
            virfinder_filtered_files
        )

    emit:
        html = html_report.out.report
        coverage_plots = coverage_plot.out.plot
} 