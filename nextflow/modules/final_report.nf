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

    output:
        path "final_report.html", emit: report

    script:
    def kraken2_args = (kraken2_reports && kraken2_reports.size() > 0) ? "--kraken2-reports ${kraken2_reports}" : ""
    def fastqc_args = (fastqc_reports && fastqc_reports.size() > 0) ? "--fastqc-reports ${fastqc_reports}" : ""
    def coverage_args = (coverage_stats && coverage_stats.size() > 0) ? "--coverage-stats ${coverage_stats}" : ""
    def checkv_args = (checkv_results && checkv_results.size() > 0) ? "--checkv-results ${checkv_results}" : ""
    def virfinder_full_args = (virfinder_full && virfinder_full.size() > 0) ? "--virfinder-full ${virfinder_full}" : ""
    def virfinder_filtered_args = (virfinder_filtered && virfinder_filtered.size() > 0) ? "--virfinder-filtered ${virfinder_filtered}" : ""
    def blast_args = (blast_results && blast_results.size() > 0) ? "--blast-results ${blast_results}" : ""
    def assembly_args = (assembly_results && assembly_results.size() > 0) ? "--assembly-results ${assembly_results}" : ""
    
    """
    python3 ${projectDir}/nextflow/bin/generate_report.py \\
        ${kraken2_args} \\
        ${fastqc_args} \\
        ${coverage_args} \\
        ${checkv_args} \\
        ${virfinder_full_args} \\
        ${virfinder_filtered_args} \\
        ${blast_args} \\
        ${assembly_args} \\
        --output final_report.html
    """
}