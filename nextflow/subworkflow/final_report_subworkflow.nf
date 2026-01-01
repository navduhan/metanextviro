// nextflow/subworkflow/final_report_subworkflow.nf

include { final_report } from '../modules/final_report.nf'

workflow FINAL_REPORT_SUBWORKFLOW {
    take:
        kraken2_reports
        fastqc_reports
        coverage_stats
        checkv_results
        virfinder_full
        virfinder_filtered
        blast_results
        assembly_results

    main:
        final_report(
            kraken2_reports,
            fastqc_reports,
            coverage_stats,
            checkv_results,
            virfinder_full,
            virfinder_filtered,
            blast_results,
            assembly_results
        )

    emit:
        report = final_report.out.report
}
