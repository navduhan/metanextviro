// Author: Naveen Duhan

process blastn_viruses {
    tag "$id"  // Tag the task with the query ID for traceability
    label 'medium'  // Assign a label for resource management

    publishDir "${params.outdir}/blast_results", mode: 'copy', overwrite: true  // Define output directory and handling

    input:
        tuple val(id), path(fasta_file)  // Input: Sample ID and FASTA file

    output:
        tuple val(id), path("${id}_best_hits_viruses.xls"), emit: formatted_blast_output  // Emit processed BLAST results in Excel format

    script:
    """
    # Log the start of the BLAST process
    echo " Starting BLAST search for viruses for sample: $id"
    echo " Input FASTA file: ${fasta_file}"
    echo " Using BLAST database: ${params.blastdb_viruses}"

    # Run BLAST search
    blastn \
        -query ${fasta_file} \
        -db ${params.blastdb_viruses} \
        -out ${id}_viruses.txt \
        -num_alignments 5 \
        -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovs evalue bitscore qlen slen stitle staxids sstrand' \
        -num_threads ${task.cpus}

    # Verify BLAST output
    if [ ! -f "${id}_viruses.txt" ]; then
        echo " Error: BLAST failed to generate output for sample: $id" >&2
        exit 1
    fi

    # Log the processing step
    echo " Processing BLAST results for sample: $id"
    
    # Run Python script to process the BLAST results
    python3 ${workflow.projectDir}/nextflow/bin/process_blast_results.py \
        -b ${id}_viruses.txt \
        -f ${fasta_file} \
        -p ${id} \
        -s viruses

    # Verify processed output
    if [ ! -f "${id}_best_hits_viruses.xls" ]; then
        echo " Error: Failed to process BLAST results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " BLAST search and processing completed successfully for sample: $id"
    """
}
