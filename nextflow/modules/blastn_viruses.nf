// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Aligns assembled contigs against the viral nucleotide reference database using blastn and runs process_blast_results.py to produce sorted best-hit and multi-HSP tables.

process blastn_viruses {
    tag "$id"  // Tag the task with the query ID for traceability
    label 'medium'  // Assign a label for resource management

    publishDir "${params.outdir}/blast_results",
        mode: params.publish_mode,
        overwrite: true,
        failOnError: true,
        saveAs: { filename -> filename.startsWith("${id}_best_hits_") ? filename : "details/${filename}" }

    input:
        tuple val(id), path(fasta_file)  // Input: Sample ID and FASTA file

    output:
        tuple val(id), path("${id}_all_hsps_viruses.tsv"), emit: formatted_blast_output
        tuple val(id), path("${id}_subject_summary_viruses.tsv"), emit: hit_summary
        tuple val(id), path("${id}_best_hits_viruses.tsv"), emit: best_hit_tsv
        tuple val(id), path("${id}_best_hits_viruses.xlsx"), emit: best_hit_summary
        tuple val(id), path("${id}_raw_viruses.txt"), emit: raw_blast_output

    script:
    def resolvedDb = params.blastdb_viruses ?: (
        (params.db_dir && file("${params.db_dir}/nt_viruses/.completed").exists())
            ? file("${params.db_dir}/nt_viruses/nt_viruses").toAbsolutePath().toString()
            : file("${params.db_dir}/blast_viruses/refseq_viral_genomic").toAbsolutePath().toString()
    )
    def resolvedTax = params.taxonomy_db ?: (
        (params.db_dir && (params.auto_download_dbs || params.setup_databases || file("${params.db_dir}/taxonomy/taxa.sqlite").exists()))
            ? file("${params.db_dir}/taxonomy/taxa.sqlite").toAbsolutePath().toString()
            : null
    )
    def taxonomyArg = resolvedTax ? "--taxonomy_db '" + file(resolvedTax).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    """
    # Log the start of the BLAST process
    echo " Starting BLAST search for viruses for sample: $id"
    echo " Input FASTA file: ${fasta_file}"
    echo " Using BLAST database: ${resolvedDb}"

    # Run BLAST search
    blastn \
        -query ${fasta_file} \
        -db "${resolvedDb}" \
        -out ${id}_raw_viruses.txt \
        -max_target_seqs ${params.blast_max_target_seqs} \
        -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovhsp evalue bitscore qlen slen stitle staxids sstrand' \
        -num_threads ${task.cpus}

    # Verify BLAST output
    if [ ! -f "${id}_raw_viruses.txt" ]; then
        echo " Error: BLAST failed to generate output for sample: $id" >&2
        exit 1
    fi

    # Log the processing step
    echo " Processing BLAST results for sample: $id"
    
    # Run Python script to process the BLAST results
    python3 ${workflow.projectDir}/bin/process_blast_results.py \
        -b ${id}_raw_viruses.txt \
        -f ${fasta_file} \
        -p ${id} \
        -s viruses \
        --query_coverage_type qcovhsp ${taxonomyArg}

    # Verify processed output
    if [ ! -f "${id}_best_hits_viruses.tsv" ] || [ ! -f "${id}_best_hits_viruses.xlsx" ]; then
        echo " Error: Failed to process BLAST results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " BLAST search and processing completed successfully for sample: $id"
    """
}
