// Author: Naveen Duhan

include { INPUT_PARSER } from '../subworkflow/input_parser'
include { QUALITY } from '../subworkflow/quality.nf'
include { TRIMMING } from '../subworkflow/trimming.nf'
include { host_depletion } from '../modules/host_depletion.nf'
include { ASSEMBLY } from '../subworkflow/assembly.nf'
include { BLAST_ANNOTATION } from '../subworkflow/blast_annotation.nf'
include { TAXONOMIC_PROFILING } from '../subworkflow/taxonomic_profiling.nf'
include { VIRAL_ANALYSIS } from '../subworkflow/viral_analysis.nf'
include { CONTIG_TRIAGE; NOVEL_VIRUS_DETECTION } from '../subworkflow/novel_virus_detection.nf'
include { CONTIG_ORGANIZATION } from '../subworkflow/organize_contigs.nf'
include { VISUALIZATION } from '../subworkflow/visualization.nf'
include { COVERAGE_ANALYSIS } from '../subworkflow/coverage_analysis.nf'

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
        ch_host_depletion_stats = Channel.empty()
        ch_contigs = Channel.empty()
        ch_blastn_results_viruses = Channel.empty()
        ch_blastn_results_nt = Channel.empty()
        ch_blastx_results_nr = Channel.empty()
        ch_all_blast = Channel.empty()
        ch_kraken2_reports = Channel.empty()
        ch_kraken2_outputs = Channel.empty()
        ch_krona_html = Channel.empty()
        ch_checkv_report = Channel.empty()
        ch_checkv_summary = Channel.empty()
        ch_virfinder_full = Channel.empty()
        ch_virfinder_filtered = Channel.empty()
        ch_virfinder_table = Channel.empty()
        ch_genomad_report = Channel.empty()
        ch_genomad_virus = Channel.empty()
        ch_genomad_plasmid = Channel.empty()
        ch_coverage_bam = Channel.empty()
        ch_coverage_stats = Channel.empty()
        ch_coverage_plot = Channel.empty()
        ch_coverage_distribution_plot = Channel.empty()
        ch_organized_dirs = Channel.empty()
        ch_organization_summaries = Channel.empty()
        ch_novel_candidates_xlsx = Channel.empty()
        ch_novel_candidates_tsv = Channel.empty()
        ch_novel_candidates_fasta = Channel.empty()
        ch_novel_phylogeny = Channel.empty()

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

        ch_analysis_reads1 = ch_trimmed_reads1
        ch_analysis_reads2 = ch_trimmed_reads2
        if (params.deplete_host && !params.skip_host_depletion) {
            host_depletion(ch_trimmed_reads1.join(ch_trimmed_reads2))
            ch_analysis_reads1 = host_depletion.out.reads1
            ch_analysis_reads2 = host_depletion.out.reads2
            ch_host_depletion_stats = host_depletion.out.stats
        }
        
        if (!params.skip_assembly) {
            ASSEMBLY(ch_analysis_reads1, ch_analysis_reads2)
            ch_contigs = ASSEMBLY.out.contigs
        }
        
        if (!params.skip_blast_annotation && !params.skip_assembly) {
            BLAST_ANNOTATION(ch_contigs)
            ch_blastn_results_viruses = BLAST_ANNOTATION.out.blastn_results_viruses
            ch_blastn_results_nt = BLAST_ANNOTATION.out.blastn_results_nt
            ch_blastx_results_nr = BLAST_ANNOTATION.out.blastx_results_nr

            ch_all_blast = ch_blastn_results_nt
                .mix(ch_blastn_results_viruses, ch_blastx_results_nr)
                .groupTuple()
                .map { id, results -> [id, results.flatten()] }
        }

        if (!params.skip_taxonomic_profiling) {
            TAXONOMIC_PROFILING(ch_analysis_reads1.join(ch_analysis_reads2))
            ch_kraken2_reports = TAXONOMIC_PROFILING.out.kraken2_reports
            ch_kraken2_outputs = TAXONOMIC_PROFILING.out.kraken2_outputs
            ch_krona_html = TAXONOMIC_PROFILING.out.krona_html
        }
        
        if (!params.skip_coverage_analysis && !params.skip_assembly) {
            COVERAGE_ANALYSIS(
                ch_contigs,
                ch_analysis_reads1,
                ch_analysis_reads2
            )
            ch_coverage_bam = COVERAGE_ANALYSIS.out.bam
            ch_coverage_stats = COVERAGE_ANALYSIS.out.stats
            ch_coverage_plot = COVERAGE_ANALYSIS.out.plot
            ch_coverage_distribution_plot = COVERAGE_ANALYSIS.out.distribution_plot
        }

        // Automated post-BLAST triage: skip contigs already confidently identified by BLAST
        def run_novel_workflow = !params.skip_novel_detection && (
            params.discover_novel_viruses ||
            (params.run_virfinder && params.annotate_virfinder_taxonomy) ||
            params.run_viral_hmm ||
            params.run_viral_protein_blast ||
            params.run_foldseek ||
            params.run_novel_phylogeny
        )
        def run_viral_tools = !params.skip_viral_analysis && (
            params.run_checkv ||
            params.run_virfinder ||
            params.run_genomad
        )

        if (!params.skip_assembly && (run_novel_workflow || run_viral_tools)) {
            CONTIG_TRIAGE(ch_contigs, ch_all_blast)
            ch_candidate_contigs = CONTIG_TRIAGE.out.candidate_contigs
            ch_triage_manifest = CONTIG_TRIAGE.out.manifest

            if (run_viral_tools) {
                VIRAL_ANALYSIS(ch_candidate_contigs)
                ch_checkv_report = VIRAL_ANALYSIS.out.checkv_report
                ch_checkv_summary = VIRAL_ANALYSIS.out.checkv_summary
                ch_virfinder_full = VIRAL_ANALYSIS.out.virfinder_full
                ch_virfinder_filtered = VIRAL_ANALYSIS.out.virfinder_filtered
                ch_virfinder_table = VIRAL_ANALYSIS.out.virfinder_table
                ch_genomad_report = VIRAL_ANALYSIS.out.genomad_report
                ch_genomad_virus = VIRAL_ANALYSIS.out.genomad_virus
                ch_genomad_plasmid = VIRAL_ANALYSIS.out.genomad_plasmid
            }

            if (run_novel_workflow) {
                NOVEL_VIRUS_DETECTION(
                    ch_contigs,
                    ch_candidate_contigs,
                    ch_triage_manifest,
                    ch_coverage_stats,
                    ch_virfinder_table,
                    ch_checkv_summary,
                    ch_genomad_virus,
                    ch_genomad_plasmid
                )
                ch_novel_candidates_xlsx = NOVEL_VIRUS_DETECTION.out.candidates_xlsx
                ch_novel_candidates_tsv = NOVEL_VIRUS_DETECTION.out.candidates_tsv
                ch_novel_candidates_fasta = NOVEL_VIRUS_DETECTION.out.candidates_fasta
                ch_novel_phylogeny = NOVEL_VIRUS_DETECTION.out.phylogeny
            }
        }
        
        if (params.organize_contigs && !params.skip_contig_organization && !params.skip_blast_annotation && !params.skip_assembly) {
            CONTIG_ORGANIZATION(
                ch_all_blast,
                ch_contigs
            )
            ch_organized_dirs = CONTIG_ORGANIZATION.out.organized_dirs
            ch_organization_summaries = CONTIG_ORGANIZATION.out.summaries
        }

    emit:
        // Quality control outputs
        quality_reports = ch_quality_reports
        
        // Trimming & host-depletion outputs
        trimmed_reads1 = ch_analysis_reads1
        trimmed_reads2 = ch_analysis_reads2
        host_depletion_stats = ch_host_depletion_stats
        
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
        genomad_report = ch_genomad_report
        
        // Novel virus discovery outputs
        novel_candidates_xlsx = ch_novel_candidates_xlsx
        novel_candidates_tsv = ch_novel_candidates_tsv
        novel_candidates_fasta = ch_novel_candidates_fasta
        novel_phylogeny = ch_novel_phylogeny
        
        // Coverage outputs
        coverage_bam = ch_coverage_bam
        coverage_stats = ch_coverage_stats
        
        // Contig organization outputs
        organized_dirs = ch_organized_dirs
        organization_summaries = ch_organization_summaries

        coverage_plots = ch_coverage_plot
        coverage_distributions = ch_coverage_distribution_plot
}
