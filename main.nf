#!/usr/bin/env nextflow

// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Entry point for the MetaNextViro Nextflow DSL2 pipeline. Validates runtime parameters, supports standalone samplesheet creation and reference database setup, and launches the main viral metagenomics workflow.

// Enable DSL 2 syntax
nextflow.enable.dsl = 2

include { metanextviro } from './nextflow/workflow/metanextviro.nf'
include { setup_databases } from './nextflow/modules/setup_databases.nf'
include { create_samplesheet } from './nextflow/modules/create_samplesheet.nf'

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
    if (!(params.db_preset in ['full_viral', 'minimal', 'discovery_only', 'genbank_complete'])) {
        error "Invalid --db_preset '${params.db_preset}'. Use full_viral, minimal, discovery_only, or genbank_complete."
    }
    if (!(params.phylo_tool in ['fasttree', 'iqtree'])) {
        error "Invalid --phylo_tool '${params.phylo_tool}'. Use 'fasttree' or 'iqtree'."
    }

    def targetDbDir = params.db_dir ? file(params.db_dir).toAbsolutePath().toString() : null
    def resolvedReadsDir = params.reads_dir ?: params.fastq_dir

    // Standalone samplesheet generation mode (no databases required)
    if (params.create_samplesheet) {
        if (!resolvedReadsDir) {
            error '--create_samplesheet requires --reads_dir <fastq_directory>.'
        }
        def absReadsDir = file(resolvedReadsDir, checkIfExists: true).toAbsolutePath().toString()
        def targetSheet = file(params.samplesheet ?: 'samplesheet.csv').toAbsolutePath()
        create_samplesheet(
            Channel.of(absReadsDir),
            Channel.of(targetSheet.parent.toString()),
            Channel.of(targetSheet.fileName.toString())
        )
    } else if (params.setup_databases && !params.input && !resolvedReadsDir) {
        // Standalone database setup mode (no --input samplesheet required)
        if (!targetDbDir) {
            error '--setup_databases requires --db_dir <directory>.'
        }
        setup_databases(Channel.of(targetDbDir), Channel.of(params.db_preset))
    } else {
        // Analysis mode (accepts --input <samplesheet> OR --reads_dir <fastq_dir>)
        if (!params.input && !resolvedReadsDir) {
            error 'Error: Input not specified! Pass --input <samplesheet>, --reads_dir <fastq_dir>, --create_samplesheet --reads_dir <fastq_dir>, or --setup_databases.'
        }

        def checkPathParamList = [
            params.input,
            resolvedReadsDir,
            params.adapters,
            params.taxonomy_db,
            params.host_fasta,
            params.viral_hmm_db,
            params.viral_hmm_taxonomy,
            params.phylo_reference_faa
        ]
        checkPathParamList.each { param ->
            if (param) {
                file(param, checkIfExists: true)
            }
        }

        def willDownloadDbs = (params.setup_databases || params.auto_download_dbs)
        def presetCoversFull = willDownloadDbs && (params.db_preset in ['full_viral', 'genbank_complete'])
        def presetCoversDiscovery = willDownloadDbs && (params.db_preset in ['minimal', 'discovery_only', 'full_viral', 'genbank_complete'])
        def presetCoversMinimal = willDownloadDbs && (params.db_preset in ['minimal', 'full_viral', 'genbank_complete'])

        if (params.deplete_host && !params.skip_host_depletion && !params.host_fasta && !params.host_bowtie2_index) {
            error '--deplete_host requires --host_fasta or --host_bowtie2_index.'
        }
        if (params.run_genomad && !params.skip_viral_analysis && !(params.genomad_db || hasDbPath(targetDbDir, 'genomad') || presetCoversFull)) {
            error "--run_genomad requires --genomad_db or running '--setup_databases --db_preset full_viral --db_dir ${targetDbDir}'."
        }
        if (params.run_checkv && !params.skip_viral_analysis && !(params.checkv_db || hasDbPath(targetDbDir, 'checkv') || presetCoversFull)) {
            error "--run_checkv requires --checkv_db or running '--setup_databases --db_preset full_viral --db_dir ${targetDbDir}'."
        }
        if (params.run_viral_hmm && !params.skip_novel_detection && !(params.viral_hmm_db || hasDbPath(targetDbDir, 'viral_hmm/vog_hallmarks.hmm') || presetCoversDiscovery)) {
            error "--run_viral_hmm requires --viral_hmm_db or running '--setup_databases --db_dir ${targetDbDir}'."
        }
        if (params.run_viral_protein_blast && !params.skip_novel_detection && !(params.viral_protein_db || hasDbPath(targetDbDir, 'viral_proteins/refseq_viral_proteins.dmnd') || presetCoversDiscovery)) {
            error "--run_viral_protein_blast requires --viral_protein_db or running '--setup_databases --db_dir ${targetDbDir}'."
        }
        if (params.run_foldseek && !params.skip_novel_detection && !params.foldseek_db) {
            error '--run_foldseek requires --foldseek_db <path_to_foldseek_db>.'
        }
        if (params.run_novel_phylogeny && !params.skip_novel_detection && !(params.phylo_reference_faa || hasDbPath(targetDbDir, 'viral_proteins/refseq_hallmark_refs.faa') || presetCoversDiscovery)) {
            error "--run_novel_phylogeny requires --phylo_reference_faa or running '--setup_databases --db_dir ${targetDbDir}'."
        }

        if (!workflow.preview && !willDownloadDbs) {
            def hasKraken = params.kraken2_db || hasDbPath(targetDbDir, 'kraken2_viral/hash.k2d')
            if (!params.skip_taxonomic_profiling && !hasKraken) {
                error "No Kraken2 database found in '${targetDbDir}'. Run 'nextflow run navduhan/metanextviro --setup_databases --db_dir ${targetDbDir} -profile conda', pass '--auto_download_dbs', or supply '--kraken2_db' / '-profile sdsu'."
            }
            def selectedBlast = (params.blast_options instanceof Collection ? params.blast_options : params.blast_options.toString().split(','))
                .collect { opt -> opt.toString().trim().toLowerCase() }
            def needsViralBlast = ('viruses' in selectedBlast || 'nt_viruses' in selectedBlast || 'all' in selectedBlast)
            def hasViralBlast = params.blastdb_viruses || hasDbPath(targetDbDir, 'blast_viruses/.completed') || hasDbPath(targetDbDir, 'nt_viruses/.completed')
            if (!params.skip_blast_annotation && !params.skip_assembly && needsViralBlast && !hasViralBlast && !presetCoversMinimal) {
                error "No viral BLAST database found in '${targetDbDir}'. Run 'nextflow run navduhan/metanextviro --setup_databases --db_dir ${targetDbDir} -profile conda', pass '--auto_download_dbs', or supply '--blastdb_viruses' / '-profile sdsu'."
            }
        }

        // Check actual hard-link support before starting expensive analysis tasks.
        if (params.publish_mode == 'link') {
            validateHardLinks(file(params.outdir), workflow.workDir)
        }

        // Build input samplesheet channel from --input or auto-generate from --reads_dir
        def rawInputCh
        if (params.input) {
            rawInputCh = Channel.value(file(params.input))
        } else {
            def absReadsDir = file(resolvedReadsDir).toAbsolutePath().toString()
            def autoSheetOutDir = file(params.outdir).toAbsolutePath().toString()
            create_samplesheet(
                Channel.of(absReadsDir),
                Channel.of(autoSheetOutDir),
                Channel.of('samplesheet.csv')
            )
            rawInputCh = create_samplesheet.out.csv
        }

        if (willDownloadDbs) {
            setup_databases(Channel.of(targetDbDir), Channel.of(params.db_preset))
            ch_input = setup_databases.out.ready_db_dir.combine(rawInputCh).map { _ready, sheetFile -> sheetFile }
        } else {
            ch_input = rawInputCh
        }

        metanextviro(ch_input)
    }
}

def hasDbPath(targetDbDir, relPath) {
    return targetDbDir != null && file("${targetDbDir}/${relPath}").exists()
}

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

    Quick Start (Nextflow or CLI execution):

    # 0. One-time pull so you can run short 'nextflow run metanextviro' anywhere:
    nextflow pull navduhan/metanextviro

    # 1. Generate a validated samplesheet from a directory of paired FASTQ files:
    nextflow run metanextviro --create_samplesheet --reads_dir ./raw_fastqs --samplesheet samplesheet.csv

    # 2. One-time full viral database download & setup (~4.0 GB default):
    nextflow run metanextviro --setup_databases --db_dir ~/.metanextviro/dbs -profile conda

    # 3. Routine targeted virus run (from --input samplesheet OR directly from --reads_dir):
    nextflow run metanextviro --input samplesheet.csv --outdir results -profile conda
    nextflow run metanextviro --reads_dir ./raw_fastqs --outdir results -profile conda

    # 4. Novel virus discovery + VirFinder (with automatic Order/Family assignment):
    nextflow run metanextviro --input samplesheet.csv --discover_novel_viruses --run_virfinder -profile conda

    Samplesheet & Input Options:
    --input              Path to an existing samplesheet (CSV, TSV, XLS, XLSX)
    --reads_dir          Directory of paired FASTQ files (runs directly or pairs with --create_samplesheet)
    --create_samplesheet Generate a samplesheet CSV from --reads_dir and exit
    --samplesheet        Output CSV path for --create_samplesheet (default: 'samplesheet.csv')
    --recursive_reads    Recursively search subdirectories under --reads_dir (default: false)

    Database Management Options:
    --db_dir            Directory for managed databases (default: ~/.metanextviro/dbs)
    --setup_databases   Download and build reference databases in --db_dir (can run standalone without --input)
    --auto_download_dbs Automatically build missing databases in --db_dir before running analysis
    --db_preset         Database bundle: 'full_viral' (~4 GB, default), 'minimal' (~1.1 GB), 'discovery_only' (~375 MB), 'genbank_complete' (~18-20 GB)
    --db_components     Optional comma-separated component list overriding --db_preset
    --db_force          Force rebuilding databases even if already present

    Core Options:
    --input             Path to the input samplesheet (mandatory for analysis runs)
    --outdir            Directory for output files (default: './results')
    --publish_mode      Output publishing: copy (default), link (same filesystem), symlink, rellink
    --trimming_tool     Trimming tool: 'fastp', 'flexbar', or 'trim_galore' (default: 'trim_galore')
    --assembler         Assembler: 'megahit' (default), 'metaspades', or 'hybrid'
    --blast_options     Databases: viruses (alias: nt_viruses), nt, nr, all, or comma-separated (default: viruses)
    --blast_max_target_seqs Maximum subject sequences reported per query (default: 50)
    --blastx_tool       Protein search tool: diamond (default) or blastx
    --organize_contigs  Enable contig organization using selected BLAST results (default: false)
    --account           SLURM account to charge (optional; uses scheduler default when omitted)

    Opt-in Novel Virus Discovery & VirFinder Options (disabled by default):
    --discover_novel_viruses  Enable automated post-BLAST novel virus triage, ORF/DTR/EVE scan & XLSX/TSV report
    --run_virfinder           Enable enhanced VirFinder (FDR q-value + entropy QC + Order/Family follow-up)
    --run_checkv              Enable CheckV assessment on unassigned/divergent contigs
    --run_genomad             Enable geNomad marker + neural virus/plasmid classifier
    --discovery_all_contigs   Score all contigs instead of automatically skipping confident BLAST hits
    --deplete_host            Subtract host reads prior to assembly (requires --host_fasta or --host_bowtie2_index)
    --run_viral_hmm           Scan candidate ORFs against viral hallmark HMMs
    --run_viral_protein_blast Run ultra-sensitive DIAMOND blastp on candidate ORFs
    --run_foldseek            Run Foldseek 3D structural homology search on candidate ORFs
    --run_novel_phylogeny     Align promoted novel ORFs with reference hallmarks via MAFFT + FastTree/IQ-TREE

    Profiles (-profile):
    local, slurm, sdsu, conda, mamba, docker, singularity, apptainer

    """.stripIndent()
}
