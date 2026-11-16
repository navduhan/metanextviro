// Author: Naveen Duhan

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
    def taxonomyArg = params.taxonomy_db ? "--taxonomy_db '" + file(params.taxonomy_db).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    """
    # Log the start of the BLAST process
    echo " Starting BLAST search for viruses for sample: $id"
    echo " Input FASTA file: ${fasta_file}"
    echo " Using BLAST database: ${params.blastdb_viruses}"

    # Run BLAST search
    blastn \
        -query ${fasta_file} \
        -db ${params.blastdb_viruses} \
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
    python3 ${workflow.projectDir}/nextflow/bin/process_blast_results.py \
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
