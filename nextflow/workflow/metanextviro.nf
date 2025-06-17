// Author: Naveen Duhan

include { INPUT_PARSER } from '../subworkflow/input_parser'
include { PREPROCESSING } from '../subworkflow/preprocessing.nf'
include { ASSEMBLY } from '../subworkflow/assembly.nf'
include { BLAST_ANNOTATION } from '../subworkflow/blast_annotation.nf'
include { TAXONOMIC_PROFILING } from '../subworkflow/taxonomic_profiling.nf'
include { VIRAL_ANALYSIS } from '../subworkflow/viral_analysis.nf'
include { CONTIG_ORGANIZATION } from '../subworkflow/organize_contigs.nf'
include { VISUALIZATION } from '../subworkflow/visualization.nf'
include { coverage } from '../modules/coverage.nf'

workflow METANEXTVIRO {
    take:
        ch_input

    main:
        // Parse input samplesheet
        INPUT_PARSER(ch_input)

        // Capture output channels
        ch_reads1 = INPUT_PARSER.out.reads1
        ch_reads2 = INPUT_PARSER.out.reads2

        // Preprocessing: QC, trimming (fastp/flexbar/trim_galore), MultiQC
        PREPROCESSING(ch_reads1, ch_reads2)

        // Prepare trimmed reads for taxonomic profiling
        trimmed_reads_ch = PREPROCESSING.out.trimmed_reads1.combine(PREPROCESSING.out.trimmed_reads2)
            .map { id1, r1, id2, r2 ->
                assert id1 == id2
                tuple(id1, r1, r2)
            }

        // Taxonomic profiling (Kraken2 + Krona)
        TAXONOMIC_PROFILING(trimmed_reads_ch)

        // Assembly and annotation
        ASSEMBLY(PREPROCESSING.out.trimmed_reads1, PREPROCESSING.out.trimmed_reads2)
        BLAST_ANNOTATION(ASSEMBLY.out.contigs)

        // Viral analysis on assembled contigs
        VIRAL_ANALYSIS(ASSEMBLY.out.contigs)

        // Organize contigs by taxonomy
        CONTIG_ORGANIZATION(
            BLAST_ANNOTATION.out.results,
            ASSEMBLY.out.contigs
        )

        // Coverage analysis for visualization
        coverage_input_ch = ASSEMBLY.out.contigs.combine(PREPROCESSING.out.trimmed_reads1, PREPROCESSING.out.trimmed_reads2)
            .map { tuple1, r1, r2 ->
                def (id, contigs) = tuple1
                tuple(id, contigs, r1, r2)
            }
        coverage(coverage_input_ch)

        // Visualization
        VISUALIZATION(
            VIRAL_ANALYSIS.out.checkv_results,
            VIRAL_ANALYSIS.out.virfinder_results
        )

    emit:
        multiqc_report = PREPROCESSING.out.multiqc_report
        trimmed_reads = PREPROCESSING.out.trimmed_reads1.mix(PREPROCESSING.out.trimmed_reads2)
        assembly_results = ASSEMBLY.out.contigs
        blast_results = BLAST_ANNOTATION.out.results
        kraken2_reports = TAXONOMIC_PROFILING.out.kraken2_reports
        kraken2_outputs = TAXONOMIC_PROFILING.out.kraken2_outputs
        krona_html = TAXONOMIC_PROFILING.out.krona_html
        checkv_results = VIRAL_ANALYSIS.out.checkv_results
        virfinder_results = VIRAL_ANALYSIS.out.virfinder_results
        organized_contigs = CONTIG_ORGANIZATION.out.organized_dirs
        taxonomy_summaries = CONTIG_ORGANIZATION.out.summaries
        visualization_html = VISUALIZATION.out.html
}