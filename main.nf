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

    // Validate mandatory input parameters
    if (!params.input) {
        error 'Error: Input samplesheet not specified! Use --input <samplesheet> to provide input.'
    }

        // Check if input files exist
    def checkPathParamList = [ params.input, params.adapters ]
    checkPathParamList.each { param -> 
        if (param) { 
            file(param, checkIfExists: true) 
        } 
    }

    // Check mandatory parameters
    if (params.input) { 
        ch_input = file(params.input) 
    } else { 
        exit 1, 'Input samplesheet not specified!' 
    }

    // Run the Nextreo sub-workflow
    metanextviro(ch_input)
}

// Helper functions
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
    --outdir          Directory for output files (default: './results')
    --adapters        Path to the adapters file (optional, for trimming)
    --trimming_tool   Trimming tool to use: 'fastp', 'flexbar', or 'trim_galore' (default: 'fastp')
    --assembler       Assembler to use: 'megahit', 'metaspades', or 'hybrid' (default: 'hybrid')
    --kraken2_db      Path to Kraken2 database (required for taxonomic profiling)
    --blastdb_viruses Path to BLAST viruses database
    --blastdb_nt      Path to BLAST nt database
    --blastdb_nr      Path to BLAST nr database
    --diamonddb       Path to DIAMOND protein database
    --checkv_db       Path to CheckV database (required for viral genome completion)
    --min_contig_length Minimum contig length for assembly (default: 200)
    --quality         Quality threshold for trimming (default: 30)
    --profile         Nextflow profile to use (default: 'slurm')
    --help            Show this help message and exit

    Skip options:
    --skip_quality              Skip the quality control step (FastQC)
    --skip_trimming             Skip the trimming step
    --skip_assembly             Skip the assembly step
    --skip_blast_annotation     Skip the BLAST annotation step
    --skip_taxonomic_profiling  Skip the taxonomic profiling step (Kraken2)
    --skip_viral_analysis       Skip the viral analysis step (CheckV & VirFinder)
    --skip_coverage_analysis    Skip the coverage analysis step
    --skip_contig_organization  Skip the contig organization step
    --skip_visualization        Skip the visualization step
    --skip_final_report         Skip the final report generation


    Example samplesheet:
    sample,fastq_1,fastq_2
    sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
    sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz

    """.stripIndent()
}
