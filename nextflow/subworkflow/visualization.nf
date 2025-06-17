// Visualization subworkflow

include { html_report } from '../modules/html_report.nf'

workflow VISUALIZATION {
    take:
        kraken2_reports_ch
        multiqc_report_ch
        coverage_plots_ch
        heatmap_ch
        checkv_results_ch
        virfinder_results_ch

    main:
        // Generate HTML report
        html_report(
            kraken2_reports_ch,
            multiqc_report_ch,
            coverage_plots_ch,
            heatmap_ch,
            checkv_results_ch,
            virfinder_results_ch
        )

    emit:
        html = html_report.out.report
} 