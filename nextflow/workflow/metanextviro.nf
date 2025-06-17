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
        ASSEMBLY(TRIMMING.out.clean_reads1, TRIMMING.out.clean_reads2)
        BLAST_ANNOTATION(ASSEMBLY.out.contigs)
        TAXONOMIC_PROFILING(ASSEMBLY.out.contigs)
        VIRAL_ANALYSIS(ASSEMBLY.out.contigs)
        
        // Run coverage analysis
        coverage_input = ASSEMBLY.out.contigs
            .combine(TRIMMING.out.clean_reads1)
            .combine(TRIMMING.out.clean_reads2)
        coverage(coverage_input)
        
        // Pass BLAST results and contigs separately to CONTIG_ORGANIZATION
        CONTIG_ORGANIZATION(
            BLAST_ANNOTATION.out.blastn_results_viruses,
            ASSEMBLY.out.contigs
        )
        
        // Pass available inputs to VISUALIZATION
        VISUALIZATION(
            TAXONOMIC_PROFILING.out.kraken2_reports,
            QUALITY.out.reports,
            coverage.out.stats,
            VIRAL_ANALYSIS.out.checkv_report,
            VIRAL_ANALYSIS.out.virfinder_results
        )

    emit:
        // Quality control outputs
        quality_reports = QUALITY.out.reports
        
        // Trimming outputs
        trimmed_reads1 = TRIMMING.out.clean_reads1
        trimmed_reads2 = TRIMMING.out.clean_reads2
        
        // Assembly outputs
        assembly_results = ASSEMBLY.out.contigs
        assembly_stats = ASSEMBLY.out.assembly_stats
        
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
        virfinder_results = VIRAL_ANALYSIS.out.virfinder_results
        
        // Coverage outputs
        coverage_bam = coverage.out.bam
        coverage_stats = coverage.out.stats
        
        // Contig organization outputs
        organized_dirs = CONTIG_ORGANIZATION.out.organized_dirs
        organization_summaries = CONTIG_ORGANIZATION.out.summaries
        
        // Visualization outputs
        html_report = VISUALIZATION.out.html
}