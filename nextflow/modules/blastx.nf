// Author: Naveen Duhan

process blastx {
    tag "$id"  // Tag the task with the query ID for traceability
    label 'blast'  // Assign a label for resource management

    publishDir "${params.outdir}/blast_results", mode: 'copy', overwrite: true  // Define output directory and handling

    input:
        tuple val(id), path(fasta_file)  // Input: Sample ID and FASTA file

    output:
        path "${id}_best_hits_nr.xls", emit: formatted_blast_output  // Emit processed BLAST results in Excel format

    script:
    """
    # Log the start of the BLASTX process
    echo " Starting BLASTX search for NR database for sample: $id"
    echo " Input FASTA file: ${fasta_file}"
    echo " Using BLAST database: ${params.blastdb_nr}"

    # Run BLASTX search
    blastx \\ 
        -query ${fasta_file} \\ 
        -db ${params.blastdb_nr} \\ 
        -out ${id}_nr.txt \\ 
        -num_alignments 5 \\ 
        -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovs evalue bitscore qlen slen stitle staxids qstrand' \\ 
        -num_threads ${task.cpus}

    # Verify BLASTX output
    if [ ! -f "${id}_nr.txt" ]; then
        echo " Error: BLASTX failed to generate output for sample: $id" >&2
        exit 1
    fi

    # Log the processing step
    echo " Processing BLASTX results for sample: $id"

    # Create a directory for processed results
    mkdir -p ${id}_processed_results

    # Run Python script to process the BLASTX results
    python3 ${workflow.projectDir}/nextflow/bin/process_blast_results.py \\ 
        -b ${id}_nr.txt \\ 
        -f ${fasta_file} \\ 
        -p ${id} \\ 
        -s nr

    # Verify processed output
    if [ ! -f "${id}_best_hits_nr.xls" ]; then
        echo " Error: Failed to process BLASTX results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " BLASTX search and processing completed successfully for sample: $id"
    """
}
