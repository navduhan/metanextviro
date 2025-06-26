// Visualization subworkflow

include { html_report } from '../modules/html_report.nf'

workflow VISUALIZATION {
    take:
        kraken2_reports_ch
        fastqc_reports_ch
        coverage_stats_ch
        checkv_results_ch
        virfinder_full_ch
        virfinder_filtered_ch

    main:
        // Generate HTML report
        html_report(
            kraken2_reports_ch,
            fastqc_reports_ch,
            coverage_stats_ch,
            checkv_results_ch,
            virfinder_full_ch,
            virfinder_filtered_ch
        )

    emit:
        html = html_report.out.report
} 