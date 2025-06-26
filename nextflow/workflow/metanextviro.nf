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
include { coverage } from '../modules/coverage.nf'
include { coverage_plot } from '../modules/coverage_plot.nf'
include { final_report } from '../modules/final_report.nf'

workflow metanextviro {
    take:
        ch_input

    main:
        // Parse input samplesheet
        INPUT_PARSER(ch_input)

        // Capture output channels
        ch_reads1 = INPUT_PARSER.out.reads1
        ch_reads2 = INPUT_PARSER.out.reads2

        // Run pipeline steps
        QUALITY(ch_reads1, ch_reads2)
        TRIMMING(ch_reads1, ch_reads2)
        
        // Run assembly with selected assembler
        ASSEMBLY(TRIMMING.out.clean_reads1, TRIMMING.out.clean_reads2)
        
        BLAST_ANNOTATION(ASSEMBLY.out.contigs)
        TAXONOMIC_PROFILING(TRIMMING.out.clean_reads1.join(TRIMMING.out.clean_reads2))
        VIRAL_ANALYSIS(ASSEMBLY.out.contigs)
        
        // Run coverage analysis - combine channels properly for tuple format
        coverage_input = ASSEMBLY.out.contigs
            .join(TRIMMING.out.clean_reads1)
            .join(TRIMMING.out.clean_reads2)
        coverage(coverage_input)
        
        // Pass BLAST results and contigs separately to CONTIG_ORGANIZATION
        CONTIG_ORGANIZATION(
            BLAST_ANNOTATION.out.blastn_results_viruses,
            ASSEMBLY.out.contigs
        )
        
        // Generate coverage plots (intermediate visualization)
        coverage_plot_input = coverage.out.stats
        coverage_plot(coverage_plot_input)
        
        // TODO: Fix channel structure issues for final_report
        // Extract file paths from tuple channels for final_report
        // kraken2_files_final = TAXONOMIC_PROFILING.out.kraken2_reports.map { id, path -> path }
        // fastqc_files_final = QUALITY.out.reports.map { id, path -> path }
        // coverage_files_final = coverage.out.stats.map { id, path -> path }
        // checkv_files_final = VIRAL_ANALYSIS.out.checkv_report.map { id, path -> path }
        // virfinder_full_files_final = VIRAL_ANALYSIS.out.virfinder_full.map { id, full, filtered -> full }
        // virfinder_filtered_files_final = VIRAL_ANALYSIS.out.virfinder_filtered.map { id, full, filtered -> filtered }
        // blast_files_final = BLAST_ANNOTATION.out.blastn_results_viruses.map { id, path -> path }
        // assembly_files_final = ASSEMBLY.out.contigs.map { id, path -> path }
        // organized_files_final = CONTIG_ORGANIZATION.out.organized_dirs.map { id, path -> path }
        
        // TODO: FINAL STEP: Generate comprehensive HTML report after all processes complete
        // This ensures the report is generated only after everything is finished
        // final_report(
        //     kraken2_files_final,
        //     fastqc_files_final,
        //     coverage_files_final,
        //     checkv_files_final,
        //     virfinder_full_files_final,
        //     virfinder_filtered_files_final,
        //     blast_files_final,
        //     assembly_files_final,
        //     organized_files_final
        // )

    emit:
        // Quality control outputs
        quality_reports = QUALITY.out.reports
        
        // Trimming outputs
        trimmed_reads1 = TRIMMING.out.clean_reads1
        trimmed_reads2 = TRIMMING.out.clean_reads2
        
        // Assembly outputs
        assembly_results = ASSEMBLY.out.contigs
        
        // BLAST annotation outputs
        blastn_viruses = BLAST_ANNOTATION.out.blastn_results_viruses
        blastn_nt = BLAST_ANNOTATION.out.blastn_results_nt
        blastx_nr = BLAST_ANNOTATION.out.blastx_results_nr
        
        // Taxonomic profiling outputs
        kraken2_reports = TAXONOMIC_PROFILING.out.kraken2_reports
        kraken2_outputs = TAXONOMIC_PROFILING.out.kraken2_outputs
        krona_html = TAXONOMIC_PROFILING.out.krona_html
        
        // Viral analysis outputs
        checkv_report = VIRAL_ANALYSIS.out.checkv_report
        virfinder_full = VIRAL_ANALYSIS.out.virfinder_full
        virfinder_filtered = VIRAL_ANALYSIS.out.virfinder_filtered
        
        // Coverage outputs
        coverage_bam = coverage.out.bam
        coverage_stats = coverage.out.stats
        
        // Contig organization outputs
        organized_dirs = CONTIG_ORGANIZATION.out.organized_dirs
        organization_summaries = CONTIG_ORGANIZATION.out.summaries
        
        // TODO: Final comprehensive report (generated after all processes complete)
        // final_html_report = final_report.out.report
        coverage_plots = coverage_plot.out.plot
}