// Author: Naveen Duhan
// SPDX-License-Identifier: MIT
// Description: Assembles paired-end reads de novo with MEGAHIT and standardizes output contig headers using rename_contigs.py.

process megahit {
    tag "$id"  // Tag the task with the sample ID for traceability

    label 'high'  // Assign a label for resource management
    conda "${projectDir}/envs/core.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"

    publishDir "${params.outdir}", mode: params.publish_mode, overwrite: true, failOnError: true, pattern: 'megahit_assembly/*'  // Define output directory

    input:
        tuple val(id), path(reads1), path(reads2)  // Input: Sample ID and reads (paired or single)

    output:
        tuple val(id), path("megahit_assembly/${id}"), emit: all_assembly_files
        tuple val(id), path("megahit_assembly/${id}/${id}_metanextviro_megahit_contigs.fa"), emit: contigs
        tuple val(id), path("megahit_assembly/${id}/log"), emit: log
        tuple val(id), path("megahit_assembly/${id}/params.json"), emit: params
        tuple val(id), path("megahit_assembly/${id}/${id}.contigs.fa"), emit: raw_contigs

    script:
    def memArg = task.memory ? "--memory ${task.memory.toBytes()}" : ''
    """

   # Create output directory for assembly
    mkdir -p megahit_assembly
    # Bioconda megahit v1.2.9 on macOS (Darwin) overflows the 512 KB std::thread stack when threads > 1; Linux uses full task.cpus
    if [ "\$(uname -s)" = "Darwin" ]; then
        MH_THREADS=1
    else
        MH_THREADS=${task.cpus}
    fi
    # Log the start of the process
    echo " Starting MEGAHIT assembly for sample: $id"
    echo "Input files:"
    echo " - Reads1: ${reads1}"
    ${reads2 ? "echo \" - Reads2: ${reads2}\"" : "echo \" - Reads2: None (Single-end)\""}

    # Run MEGAHIT based on input type
    if [ -n "${reads2}" ]; then
        echo " Running MEGAHIT in paired-end mode..."
        megahit \\
            -1 ${reads1} \\
            -2 ${reads2} \\
            --out-dir megahit_assembly/${id} \\
            --out-prefix ${id} \\
            --no-mercy \\
            ${memArg} \\
            --num-cpu-threads "\$MH_THREADS" \\
            --min-contig-len ${params.min_contig_length}
    else
        echo " Running MEGAHIT in single-end mode..."
        megahit \\
            -r ${reads1} \\
            --out-dir megahit_assembly/${id} \\
            --out-prefix ${id} \\
            --no-mercy \\
            ${memArg} \\
            --num-cpu-threads "\$MH_THREADS" \\
            --min-contig-len ${params.min_contig_length}
    fi

    # Verify MEGAHIT output
    if [ ! -f "megahit_assembly/${id}/${id}.contigs.fa" ]; then
        echo " Error: MEGAHIT failed to generate contigs for sample: $id" >&2
        exit 1
    fi

    # Create log file by copying MEGAHIT log if it exists
    if [ -f "megahit_assembly/${id}/${id}.log" ]; then
        cp megahit_assembly/${id}/${id}.log megahit_assembly/${id}/log
    else
        echo "MEGAHIT assembly completed for sample: $id" > megahit_assembly/${id}/log
    fi

    # Create params.json file
    cat > megahit_assembly/${id}/params.json <<EOF
{
    "sample_id": "$id",
    "assembler": "megahit",
    "min_contig_length": "${params.min_contig_length}",
    "threads": "${task.cpus}",
    "input_files": {
        "reads1": "${reads1}",
        "reads2": "${reads2}"
    },
    "parameters": {
        "no_mercy": true,
        "out_prefix": "$id"
    }
}
EOF

    # Log the renaming step
    echo " Renaming contig headers for sample: $id"

    # Rename the contig headers
    python3 ${workflow.projectDir}/bin/rename_contigs.py \\
        -i megahit_assembly/${id}/${id}.contigs.fa \\
        -o megahit_assembly/${id}/${id}_metanextviro_megahit_contigs.fa \\
        -s megahit

    # Verify renamed contigs
    if [ ! -f "megahit_assembly/${id}/${id}_metanextviro_megahit_contigs.fa" ]; then
        echo " Error: Failed to rename contigs for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " MEGAHIT assembly completed successfully for sample: $id"
    """
}
