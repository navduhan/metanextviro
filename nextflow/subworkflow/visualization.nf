// Visualization subworkflow

include { krona } from '../modules/krona.nf'
include { coverage_plot } from '../modules/coverage_plot.nf'
include { heatmap } from '../modules/heatmap.nf'
include { html_report } from '../modules/html_report.nf'

workflow VISUALIZATION {
    take:
        kraken_reports_ch
        multiqc_report_ch
        bam_ch
        matrix_ch
        checkv_report_ch optional true
        viga_annotation_ch optional true
        virfinder_results_ch optional true

    main:
        krona(kraken_reports_ch)
        coverage_plot(bam_ch)
        heatmap(matrix_ch)
        html_report(
            krona.out.krona_html,
            multiqc_report_ch,
            coverage_plot.out.plot,
            heatmap.out.heatmap,
            checkv_report_ch,
            viga_annotation_ch,
            virfinder_results_ch
        )

    emit:
        krona_html = krona.out.krona_html
        coverage_plots = coverage_plot.out.plot
        heatmap_img = heatmap.out.heatmap
        html = html_report.out.html
} 