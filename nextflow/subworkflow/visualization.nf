// Visualization subworkflow

include { html_report } from '../modules/html_report.nf'

workflow VISUALIZATION {
    take:
        checkv_results_ch
        virfinder_results_ch

    main:
        // Generate HTML report
        html_report(
            checkv_results_ch,
            virfinder_results_ch
        )

    emit:
        html = html_report.out.report
} 