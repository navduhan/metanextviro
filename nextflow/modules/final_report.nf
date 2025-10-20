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
        path megahit_logs
        path megahit_params
        path megahit_raw_contigs
        path metaspades_logs
        path metaspades_params
        path metaspades_raw_scaffolds
        path hybrid_merged
        path hybrid_cdhit
        path hybrid_cdhit_clstr
        path organized_dirs

    output:
        path "final_report.html", emit: report

    script:
    template 'report_template.html'
}