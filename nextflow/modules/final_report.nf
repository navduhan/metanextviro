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
        path(megahit_logs, stageAs: { "megahit_logs/${it.parent.name}_${it.name}" })
        path(megahit_params, stageAs: { "megahit_params/${it.parent.name}_${it.name}" })
        path(megahit_raw_contigs, stageAs: { "megahit_raw_contigs/${it.parent.name}_${it.name}" })
        path(metaspades_logs, stageAs: { "metaspades_logs/${it.parent.name}_${it.name}" })
        path(metaspades_params, stageAs: { "metaspades_params/${it.parent.name}_${it.name}" })
        path(metaspades_raw_scaffolds, stageAs: { "metaspades_raw_scaffolds/${it.parent.name}_${it.name}" })
        path(hybrid_merged, stageAs: { "hybrid_merged/${it.parent.name}_${it.name}" })
        path(hybrid_cdhit, stageAs: { "hybrid_cdhit/${it.parent.name}_${it.name}" })
        path(hybrid_cdhit_clstr, stageAs: { "hybrid_cdhit_clstr/${it.parent.name}_${it.name}" })
        path(organized_dirs, stageAs: { "organized/${it.name}" })

    output:
        path "final_report.html", emit: report

    script:
    template 'report_template.html'
}