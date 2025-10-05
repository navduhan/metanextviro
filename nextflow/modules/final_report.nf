// Final comprehensive HTML report - runs after all processes complete
process final_report {
    label 'low'
    publishDir "${params.outdir}/final_report", mode: 'copy', overwrite: true

    input:
        path kraken2_reports
        path fastqc_reports
        path coverage_stats
        path checkv_results
        path virfinder_full
        path virfinder_filtered
        path blast_results
        path assembly_results
        // The other inputs from the old process are not used in the new template for simplicity,
        // but can be added back if needed. This covers the main results.

    output:
        path "final_report.html", emit: report

    script:
    template 'report_template.html'
}