// Author: Naveen Duhan

process metaspades {
    tag "$id"  // Tag the task with the sample ID for traceability

    label 'vhigh'  // Assign a label for resource management

    publishDir "${params.outdir}", mode: 'copy', overwrite: true  // Define output directory

    input:
        tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and reads (paired or single)

    output:
        tuple val(id), path("metaspades_assembly/${id}/${id}_metanextviro_metaspades_contigs.fa"), emit: contigs
        tuple val(id), path("metaspades_assembly/${id}/spades.log"), emit: log
        tuple val(id), path("metaspades_assembly/${id}/params.txt"), emit: params
        tuple val(id), path("metaspades_assembly/${id}/scaffolds.fasta"), emit: raw_scaffolds

    script:
    """
    # Log the start of the process
    echo " Starting MetaSPAdes assembly for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    ${reads2 ? "echo \" - Reads2: ${reads2}\"" : "echo \" - Reads2: None (Single-end)\""}

    # Run MetaSPAdes based on input type
    if [ -n "${reads2}" ]; then
        echo " Running MetaSPAdes in paired-end mode..."
        spades.py \\
            --meta \\
            --pe1-1 ${reads1} --pe1-2 ${reads2} \\
            -t ${task.cpus} \\
            -m ${task.memory.toMega()} \\
            -o metaspades_assembly/${id}
    else
        echo " Running MetaSPAdes in single-end mode..."
        spades.py \\
            --meta \\
            -s ${reads1} \\
            -t ${task.cpus} \\
            -m ${task.memory.toMega()} \\
            -o metaspades_assembly/${id}
    fi

    # Verify MetaSPAdes output
    if [ ! -f "metaspades_assembly/${id}/scaffolds.fasta" ]; then
        echo " Error: MetaSPAdes failed to generate scaffolds for sample: $id" >&2
        exit 1
    fi

    # Create spades.log file
    if [ -f "metaspades_assembly/${id}/spades.log" ]; then
        # File already exists, no need to create
        echo "Using existing spades.log file"
    else
        echo "MetaSPAdes assembly completed for sample: $id" > metaspades_assembly/${id}/spades.log
    fi

    # Create params.txt file
    cat > metaspades_assembly/${id}/params.txt << EOF
    Sample ID: $id
    Assembler: MetaSPAdes
    Threads: ${task.cpus}
    Memory: ${task.memory.toMega()} MB
    Input files:
      Reads1: ${reads1}
      Reads2: ${reads2}
    Parameters:
      --meta: true
      --pe1-1: ${reads1}
      --pe1-2: ${reads2}
    EOF

    # Log the renaming step
    echo " Renaming contig headers for sample: $id"

    # Rename scaffolds to contigs using the Python script
    python3 ${workflow.projectDir}/nextflow/bin/rename_contigs.py \\
        -i metaspades_assembly/${id}/scaffolds.fasta \\
        -o metaspades_assembly/${id}/${id}_metanextviro_metaspades_contigs.fa \\
        -s MetaSPAdes

    # Verify renamed contigs
    if [ ! -f "metaspades_assembly/${id}/${id}_metanextviro_metaspades_contigs.fa" ]; then
        echo " Error: Failed to rename scaffolds to contigs for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " MetaSPAdes assembly completed successfully for sample: $id"
    """
}
