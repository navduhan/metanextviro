// Author: Naveen Duhan

process blastn {
    tag "$id"  // Tag the task with the query ID for traceability
    label 'high'  // Assign a label for resource management

    publishDir "${params.outdir}/blast_results", mode: 'copy', overwrite: true  // Define output directory and handling

    input:
        tuple val(id), path(fasta_file)  // Input: Sample ID and FASTA file

    output:
        tuple val(id), path("${id}_best_hits_nt.xls"), emit: formatted_blast_output  // Emit processed BLAST results in Excel format

    script:
    """
    # Log the start of the BLAST process
    echo " Starting BLAST search for nt database for sample: $id"
    echo " Input FASTA file: ${fasta_file}"
    echo " Using BLAST database: ${params.blastdb_nt}"

    # Run BLAST search
    blastn \
        -query ${fasta_file} \
        -db ${params.blastdb_nt} \
        -out ${id}_nt.txt \
        -num_alignments 5 \
        -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send qcovs evalue bitscore qlen slen stitle staxids sstrand' \
        -num_threads ${task.cpus}

    # Verify BLAST output
    if [ ! -f "${id}_nt.txt" ]; then
        echo " Error: BLAST failed to generate output for sample: $id" >&2
        exit 1
    fi

    # Log the processing step
    echo " Processing BLAST results for sample: $id"

    # Create a directory for processed results
    mkdir -p ${id}_processed_results

    # Run Python script to process the BLAST results
    python3 ${workflow.projectDir}/nextflow/bin/process_blast_results.py \
        -b ${id}_nt.txt \
        -f ${fasta_file} \
        -p ${id} \
        -s nt

    # Verify processed output
    if [ ! -f "${id}_best_hits_nt.xls" ]; then
        echo " Error: Failed to process BLAST results for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " BLAST search and processing completed successfully for sample: $id"
    """
}
