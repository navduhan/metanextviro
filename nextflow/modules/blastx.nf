// Author: Naveen Duhan

process blastx {
    tag "$id"  // Tag the task with the query ID for traceability
    label 'high'  // Assign a label for resource management

    publishDir "${params.outdir}/blast_results",
        mode: params.publish_mode,
        overwrite: true,
        failOnError: true,
        saveAs: { filename -> filename.startsWith("${id}_best_hits_") ? filename : "details/${filename}" }

    input:
        tuple val(id), path(fasta_file)  // Input: Sample ID and FASTA file

    output:
        tuple val(id), path("${id}_all_hsps_nr.tsv"), emit: formatted_blast_output
        tuple val(id), path("${id}_subject_summary_nr.tsv"), emit: hit_summary
        tuple val(id), path("${id}_best_hits_nr.tsv"), emit: best_hit_tsv
        tuple val(id), path("${id}_best_hits_nr.xlsx"), emit: best_hit_summary
        tuple val(id), path("${id}_raw_nr.txt"), emit: raw_blast_output

    script:
    def taxonomyArg = params.taxonomy_db ? "--taxonomy_db '" + file(params.taxonomy_db).toAbsolutePath().toString().replace("'", "'\"'\"'") + "'" : ''
    """
    # Log the start of the BLASTX process
    echo " Starting \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') search for NR database for sample: $id"
    echo " Input FASTA file: ${fasta_file}"
    
    if [ "${params.blastx_tool}" = "diamond" ]; then
        echo " Using DIAMOND database: ${params.diamonddb}"
    else
        echo " Using BLAST database: ${params.blastdb_nr}"
    fi

    # Run BLASTX search based on user choice
    if [ "${params.blastx_tool}" = "diamond" ]; then
        # Use DIAMOND BLASTX (much faster)
        diamond blastx \
            --query ${fasta_file} \
            --db ${params.diamonddb} \
            --out ${id}_raw_nr.txt \
            --max-target-seqs ${params.blast_max_target_seqs} \
            --max-hsps 0 \
            --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovhsp evalue bitscore qlen slen stitle staxids qframe \
            --threads ${task.cpus} \
            --sensitive
    else
        # Use traditional BLASTX
        blastx \
            -query ${fasta_file} \
            -db ${params.blastdb_nr} \
            -out ${id}_raw_nr.txt \
            -max_target_seqs ${params.blast_max_target_seqs} \
            -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovhsp evalue bitscore qlen slen stitle staxids qframe' \
            -num_threads ${task.cpus}
    fi

    # Verify BLASTX output
    if [ ! -f "${id}_raw_nr.txt" ]; then
        echo " Error: \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') failed to generate output for sample: $id" >&2
        exit 1
    fi

    # Log the processing step
    echo " Processing \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') results for sample: $id"

    # Run Python script to process the BLASTX results
    python3 ${workflow.projectDir}/nextflow/bin/process_blast_results.py \
        -b ${id}_raw_nr.txt \
        -f ${fasta_file} \
        -p ${id} \
        -s nr \
        --query_coverage_type qcovhsp --strand_field qframe ${taxonomyArg}

    # Verify processed output
    if [ ! -f "${id}_best_hits_nr.tsv" ] || [ ! -f "${id}_best_hits_nr.xlsx" ]; then
        echo " Error: Failed to process \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') search and processing completed successfully for sample: $id"
    """
}
