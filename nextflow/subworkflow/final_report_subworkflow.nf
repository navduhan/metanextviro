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
        megahit_logs
        megahit_params
        megahit_raw_contigs
        metaspades_logs
        metaspades_params
        metaspades_raw_scaffolds
        hybrid_merged
        hybrid_cdhit
        hybrid_cdhit_clstr
        organized_dirs

    main:
        final_report(
            kraken2_reports,
            fastqc_reports,
            coverage_stats,
            checkv_results,
            virfinder_full,
            virfinder_filtered,
            blast_results,
            assembly_results,
            megahit_logs,
            megahit_params,
            megahit_raw_contigs,
            metaspades_logs,
            metaspades_params,
            metaspades_raw_scaffolds,
            hybrid_merged,
            hybrid_cdhit,
            hybrid_cdhit_clstr,
            organized_dirs
        )

    emit:
        report = final_report.out.report
}
