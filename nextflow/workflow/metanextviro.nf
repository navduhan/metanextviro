// Author: Naveen Duhan

include { INPUT_PARSER } from '../subworkflow/input_parser'
include { QUALITY } from '../subworkflow/quality.nf'
include { TRIMMING } from '../subworkflow/trimming.nf'
include { ASSEMBLY } from '../subworkflow/assembly.nf'
include { BLAST_ANNOTATION } from '../subworkflow/blast_annotation.nf'
include { TAXONOMIC_PROFILING } from '../subworkflow/taxonomic_profiling.nf'
include { VIRAL_ANALYSIS } from '../subworkflow/viral_analysis.nf'
include { CONTIG_ORGANIZATION } from '../subworkflow/organize_contigs.nf'
include { VISUALIZATION } from '../subworkflow/visualization.nf'
include { COVERAGE_ANALYSIS } from '../subworkflow/coverage_analysis.nf'
include { FINAL_REPORT_SUBWORKFLOW as FINAL_REPORT } from '../subworkflow/final_report_subworkflow.nf'

workflow metanextviro {
    take:
        ch_input

    main:
        // Parse input samplesheet
        INPUT_PARSER(ch_input)

        // Capture output channels
        ch_reads1 = INPUT_PARSER.out.reads1
        ch_reads2 = INPUT_PARSER.out.reads2

        // Initialize output channels
        ch_quality_reports = Channel.empty()
        ch_trimmed_reads1 = ch_reads1
        ch_trimmed_reads2 = ch_reads2
        ch_contigs = Channel.empty()
        ch_blastn_results_viruses = Channel.empty()
        ch_blastn_results_nt = Channel.empty()
        ch_blastx_results_nr = Channel.empty()
        ch_kraken2_reports = Channel.empty()
        ch_kraken2_outputs = Channel.empty()
        ch_krona_html = Channel.empty()
        ch_checkv_report = Channel.empty()
        ch_virfinder_full = Channel.empty()
        ch_virfinder_filtered = Channel.empty()
        ch_coverage_bam = Channel.empty()
        ch_coverage_stats = Channel.empty()
        ch_coverage_plot = Channel.empty()
        ch_coverage_distribution_plot = Channel.empty()
        ch_organized_dirs = Channel.empty()
        ch_organization_summaries = Channel.empty()
        ch_final_report = Channel.empty()

        // Run pipeline steps
        if (!params.skip_quality) {
            QUALITY(ch_reads1, ch_reads2)
            ch_quality_reports = QUALITY.out.reports
        }

        if (!params.skip_trimming) {
            TRIMMING(ch_reads1, ch_reads2)
            ch_trimmed_reads1 = TRIMMING.out.clean_reads1
            ch_trimmed_reads2 = TRIMMING.out.clean_reads2
        }
        
        if (!params.skip_assembly) {
            ASSEMBLY(ch_trimmed_reads1, ch_trimmed_reads2)
            ch_contigs = ASSEMBLY.out.contigs
        }
        
        if (!params.skip_blast_annotation) {
            BLAST_ANNOTATION(ch_contigs)
            ch_blastn_results_viruses = BLAST_ANNOTATION.out.blastn_results_viruses
            ch_blastn_results_nt = BLAST_ANNOTATION.out.blastn_results_nt
            ch_blastx_results_nr = BLAST_ANNOTATION.out.blastx_results_nr
        }

        if (!params.skip_taxonomic_profiling) {
            TAXONOMIC_PROFILING(ch_trimmed_reads1.join(ch_trimmed_reads2))
            ch_kraken2_reports = TAXONOMIC_PROFILING.out.kraken2_reports
            ch_kraken2_outputs = TAXONOMIC_PROFILING.out.kraken2_outputs
            ch_krona_html = TAXONOMIC_PROFILING.out.krona_html
        }

        if (!params.skip_viral_analysis) {
            VIRAL_ANALYSIS(ch_contigs)
            ch_checkv_report = VIRAL_ANALYSIS.out.checkv_report
            ch_virfinder_full = VIRAL_ANALYSIS.out.virfinder_full
            ch_virfinder_filtered = VIRAL_ANALYSIS.out.virfinder_filtered
        }
        
        if (!params.skip_coverage_analysis) {
            COVERAGE_ANALYSIS(
                ch_contigs,
                ch_trimmed_reads1,
                ch_trimmed_reads2
            )
            ch_coverage_bam = COVERAGE_ANALYSIS.out.bam
            ch_coverage_stats = COVERAGE_ANALYSIS.out.stats
            ch_coverage_plot = COVERAGE_ANALYSIS.out.plot
            ch_coverage_distribution_plot = COVERAGE_ANALYSIS.out.distribution_plot
        }
        
        if (!params.skip_contig_organization) {
            CONTIG_ORGANIZATION(
                ch_blastn_results_nt,
                ch_contigs
            )
            ch_organized_dirs = CONTIG_ORGANIZATION.out.organized_dirs
            ch_organization_summaries = CONTIG_ORGANIZATION.out.summaries
        }
        
        if (!params.skip_final_report) {
            FINAL_REPORT(
                ch_kraken2_reports.map { id, path -> path }.collect(),      // tuple [id, path] -> extract path
                ch_quality_reports.collect(),                                // already just paths (no tuple)
                ch_coverage_stats.map { id, path -> path }.collect(),        // tuple [id, path] -> extract path
                ch_checkv_report.map { id, path -> path }.collect(),         // tuple [id, path] -> extract path
                ch_virfinder_full.collect(),                                 // already just paths (mapped in subworkflow)
                ch_virfinder_filtered.collect(),                             // already just paths (mapped in subworkflow)
                ch_blastn_results_nt.map { id, path -> path }.collect(),     // tuple [id, path] -> extract path
                ch_contigs.map { id, path -> path }.collect()                // tuple [id, path] -> extract path
            )
            ch_final_report = FINAL_REPORT.out.report
        }

    emit:
        // Quality control outputs
        quality_reports = ch_quality_reports
        
        // Trimming outputs
        trimmed_reads1 = ch_trimmed_reads1
        trimmed_reads2 = ch_trimmed_reads2
        
        // Assembly outputs
        assembly_results = ch_contigs
        
        // BLAST annotation outputs
        blastn_viruses = ch_blastn_results_viruses
        blastn_nt = ch_blastn_results_nt
        blastx_nr = ch_blastx_results_nr
        
        // Taxonomic profiling outputs
        kraken2_reports = ch_kraken2_reports
        kraken2_outputs = ch_kraken2_outputs
        krona_html = ch_krona_html
        
        // Viral analysis outputs
        checkv_report = ch_checkv_report
        virfinder_full = ch_virfinder_full
        virfinder_filtered = ch_virfinder_filtered
        
        // Coverage outputs
        coverage_bam = ch_coverage_bam
        coverage_stats = ch_coverage_stats
        
        // Contig organization outputs
        organized_dirs = ch_organized_dirs
        organization_summaries = ch_organization_summaries
        
        // Final comprehensive report (generated after all processes complete)
        final_html_report = ch_final_report
        coverage_plots = ch_coverage_plot
        coverage_distributions = ch_coverage_distribution_plot
}