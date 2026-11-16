#!/usr/bin/env nextflow

// Enable DSL 2 syntax
nextflow.enable.dsl = 2

// Author: Naveen Duhan

include { metanextviro } from './nextflow/workflow/metanextviro.nf'

// Validate parameters before running workflows
workflow {
 // Display help message if requested
    if (params.help) {
        helpMSG()
        exit 0
    }

    if (!(params.publish_mode in ['link', 'copy', 'symlink', 'rellink'])) {
        error 'Invalid --publish_mode. Use link, copy, symlink, or rellink.'
    }
    if (!(params.blast_max_target_seqs.toString() ==~ /[1-9][0-9]*/)) {
        error '--blast_max_target_seqs must be a positive integer.'
    }

    // Validate mandatory input parameters
    if (!params.input) {
        error 'Error: Input samplesheet not specified! Use --input <samplesheet> to provide input.'
    }

        // Check if input files exist
    def checkPathParamList = [
        params.input,
        params.adapters,
        params.taxonomy_db,
        params.host_fasta,
        params.viral_hmm_db,
        params.phylo_reference_faa
    ]
    checkPathParamList.each { param -> 
        if (param) { 
            file(param, checkIfExists: true) 
        } 
    }

    if (params.deplete_host && !params.skip_host_depletion && !params.host_fasta && !params.host_bowtie2_index) {
        error '--deplete_host requires --host_fasta or --host_bowtie2_index.'
    }
    if (params.run_genomad && !params.skip_viral_analysis && !params.genomad_db) {
        error '--run_genomad requires --genomad_db <path_to_genomad_db>.'
    }
    if (params.run_checkv && !params.skip_viral_analysis && !params.checkv_db) {
        error '--run_checkv requires --checkv_db <path_to_checkv_db>.'
    }
    if (params.run_viral_hmm && !params.skip_novel_detection && !params.viral_hmm_db) {
        error '--run_viral_hmm requires --viral_hmm_db <path_to_hmm_file>.'
    }
    if (params.run_viral_protein_blast && !params.skip_novel_detection && !params.viral_protein_db) {
        error '--run_viral_protein_blast requires --viral_protein_db <path_to_diamond_db>.'
    }
    if (params.run_foldseek && !params.skip_novel_detection && !params.foldseek_db) {
        error '--run_foldseek requires --foldseek_db <path_to_foldseek_db>.'
    }
    if (params.run_novel_phylogeny && !params.skip_novel_detection && !params.phylo_reference_faa) {
        error '--run_novel_phylogeny requires --phylo_reference_faa <path_to_reference_proteins.faa>.'
    }
    if (!(params.phylo_tool in ['fasttree', 'iqtree'])) {
        error "Invalid --phylo_tool '${params.phylo_tool}'. Use 'fasttree' or 'iqtree'."
    }

    // Check mandatory parameters
    if (params.input) { 
        ch_input = file(params.input) 
    } else { 
        exit 1, 'Input samplesheet not specified!' 
    }

    // Check actual hard-link support before starting expensive analysis tasks.
    if (params.publish_mode == 'link') {
        validateHardLinks(file(params.outdir), workflow.workDir)
    }

    // Run the MetaNextViro sub-workflow
    metanextviro(ch_input)
}

// Helper functions
def validateHardLinks(outputDir, workDir) {
    def source = null
    def destination = null
    try {
        java.nio.file.Files.createDirectories(outputDir)
        java.nio.file.Files.createDirectories(workDir)
        source = java.nio.file.Files.createTempFile(workDir, '.metanextviro-link-check-', '.tmp')
        destination = outputDir.resolve(source.fileName)
        java.nio.file.Files.createLink(destination, source)
    } catch (Exception exception) {
        if (source != null) {
            java.nio.file.Files.deleteIfExists(source)
        }
        error "Cannot hard-link work files into results: ${exception.message}. " +
            'Use work and results on the same filesystem, or select --publish_mode copy/symlink.'
    }
    java.nio.file.Files.deleteIfExists(destination)
    java.nio.file.Files.deleteIfExists(source)
}

def helpMSG() {
    println """
    ______________________________________________________________________________________________________________________________________________
    
                                MetaNextViro: High-Throughput Virus Identification and Metagenomic Analysis Pipeline
                                                Author : Naveen Duhan (naveen.duhan@outlook.com)
    ______________________________________________________________________________________________________________________________________________

    Usage example:

    nextflow run metanextviro/main.nf [options] --input <sample file /samplesheet> --outdir <output_directory>

    Options:
    --input           Path to the input samplesheet (mandatory)
    --publish_mode    Output publishing: copy (default), link (same filesystem), symlink, rellink
    --blast_max_target_seqs Maximum subject sequences reported per query (default: 50)
    --outdir          Directory for output files (default: './results')
    --adapters        Path to the adapters file (optional, for trimming)
    --trimming_tool   Trimming tool to use: 'fastp', 'flexbar', or 'trim_galore' (default: 'trim_galore')
    --assembler       Assembler to use: 'megahit', 'metaspades', or 'hybrid' (default: 'megahit')
    --kraken2_db      Path to Kraken2 database (required for taxonomic profiling)
    --blast_options   Databases: viruses (alias: nt_viruses), nt, nr, all, or comma-separated values (default: viruses)
    --blastdb_viruses Path to BLAST nt_viruses database (used by default)
    --blastdb_nt      Path to BLAST nt database (used when nt or all is selected)
    --blastdb_nr      Path to BLAST nr database (used with blastx when nr or all is selected)
    --diamonddb       Path to DIAMOND protein database
    --taxonomy_db     Existing local ETE taxonomy SQLite database (default: ~/.etetoolkit/taxa.sqlite)
    --blastx_tool     Protein search tool: diamond or blastx (default: diamond)
    --checkv_db       Path to CheckV database (required only with --run_checkv)
    --run_checkv      Enable CheckV assessment on unassigned/divergent contigs (default: false)
    --run_virfinder   Enable enhanced VirFinder (FDR q-value + entropy QC) on unassigned contigs (default: false)
    --run_genomad     Enable geNomad marker + neural virus/plasmid classifier (default: false; requires --genomad_db)
    --genomad_db      Path to geNomad database
    --organize_contigs Enable contig organization using selected BLAST results (default: false)

    Opt-in Novel Virus Discovery options (disabled by default for targeted runs):
    --discover_novel_viruses  Enable automated post-BLAST novel virus triage, ORF/DTR/EVE scan & XLSX/TSV report
    --discovery_all_contigs   Run discovery/viral classifiers on all contigs instead of skipping confident BLAST hits
    --novel_min_contig_length Minimum contig length (bp) for novel virus discovery (default: 500)
    --known_virus_identity    BLAST % identity threshold to skip already-known viruses (default: 80.0)
    --known_virus_coverage    BLAST % union coverage threshold to skip already-known viruses (default: 50.0)
    --deplete_host            Subtract host reads prior to assembly (requires --host_fasta or --host_bowtie2_index)
    --host_fasta              Host reference FASTA for pre-assembly depletion
    --host_bowtie2_index      Pre-built Bowtie2 index prefix for host depletion
    --run_viral_hmm           Scan candidate ORFs against viral hallmark HMMs (requires --viral_hmm_db)
    --viral_hmm_db            Path to HMMER profile database (e.g. NeoRdRp, RdRp-scan, RVDB-hmm, VOGDB)
    --run_viral_protein_blast Run ultra-sensitive DIAMOND blastp on candidate ORFs (requires --viral_protein_db)
    --viral_protein_db        Path to curated viral protein DIAMOND database (e.g. RVDB or RefSeq Viral Protein)
    --run_foldseek            Run Foldseek 3D structural homology search on candidate ORFs (requires --foldseek_db)
    --foldseek_db             Path to Foldseek target database (and optional --foldseek_prostt5_weights)
    --run_novel_phylogeny     Align promoted novel ORFs with --phylo_reference_faa via MAFFT + FastTree/IQ-TREE
    --phylo_reference_faa     Reference protein FASTA for phylogenetic placement
    --phylo_tool              Phylogenetic inference tool: 'fasttree' (default) or 'iqtree'
    --min_contig_length Minimum contig length for assembly (default: 200)
    --quality         Quality threshold for trimming (default: 30)
    --profile         Nextflow profile to use (default: 'slurm')
    --account         SLURM account to charge (optional; uses the scheduler default when omitted)
    --help            Show this help message and exit

    Skip options:
    --skip_quality              Skip the quality control step (FastQC)
    --skip_trimming             Skip the trimming step
    --skip_assembly             Skip the assembly step
    --skip_blast_annotation     Skip the BLAST annotation step
    --skip_taxonomic_profiling  Skip the taxonomic profiling step (Kraken2)
    --skip_viral_analysis       Skip any requested CheckV and VirFinder analysis
    --skip_coverage_analysis    Skip the coverage analysis step
    --skip_contig_organization  Skip contig organization even when --organize_contigs is set
    --skip_visualization        Skip the visualization step
    --skip_final_report         Skip the final report generation
    --skip_report               Alias for --skip_final_report


    Example samplesheet:
    sample,fastq_1,fastq_2
    sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
    sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz

    """.stripIndent()
}
