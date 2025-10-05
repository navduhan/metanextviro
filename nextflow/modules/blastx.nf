// Author: Naveen Duhan

process blastx {
    tag "$id"  // Tag the task with the query ID for traceability
    label 'high'  // Assign a label for resource management

    publishDir "${params.outdir}/blast_results", mode: 'copy', overwrite: true  // Define output directory and handling

    input:
        tuple val(id), path(fasta_file)  // Input: Sample ID and FASTA file

    output:
        path "${id}_best_hits_nr.xls", emit: formatted_blast_output  // Emit processed BLAST results in Excel format

    script:
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
            --out ${id}_nr.txt \
            --max-target-seqs 5 \
            --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovhsp evalue bitscore qlen slen stitle staxids qstrand \
            --threads ${task.cpus} \
            --sensitive
    else
        # Use traditional BLASTX
        blastx \
            -query ${fasta_file} \
            -db ${params.blastdb_nr} \
            -out ${id}_nr.txt \
            -num_alignments 5 \
            -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovs evalue bitscore qlen slen stitle staxids qstrand' \
            -num_threads ${task.cpus}
    fi

    # Verify BLASTX output
    if [ ! -f "${id}_nr.txt" ]; then
        echo " Error: \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') failed to generate output for sample: $id" >&2
        exit 1
    fi

    # Log the processing step
    echo " Processing \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') results for sample: $id"

    # Create a directory for processed results
    mkdir -p ${id}_processed_results

    # Run Python script to process the BLASTX results
    python3 ${workflow.projectDir}/nextflow/bin/process_blast_results.py \
        -b ${id}_nr.txt \
        -f ${fasta_file} \
        -p ${id} \
        -s nr

    # Verify processed output
    if [ ! -f "${id}_best_hits_nr.xls" ]; then
        echo " Error: Failed to process \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " \$(echo ${params.blastx_tool} | tr '[:lower:]' '[:upper:]') search and processing completed successfully for sample: $id"
    """
}
