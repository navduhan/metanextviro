process hybrid {
    tag "$id"  // Tag the task with the sample ID for traceability

    label 'medium'  // Assign a label for resource management

    publishDir "${params.outdir}", mode: 'copy', overwrite: true  // Define output directory

    input:
        tuple val(id), path(megahit_contigs), path(metaspades_contigs)  // Input: Sample ID and contig files from MEGAHIT and metaSPAdes

    output:
        tuple val(id), path("hybrid_assembly/${id}/${id}_metanextviro_hybrid_contigs.fa"), emit: contigs
        tuple val(id), path("hybrid_assembly/${id}/${id}_merged.fasta"), emit: merged
        tuple val(id), path("hybrid_assembly/${id}/${id}_merged_cdhit.fasta"), emit: cdhit
        tuple val(id), path("hybrid_assembly/${id}/${id}_merged_cdhit.fasta.clstr"), emit: cdhit_clstr

    script:
    """
    # Create output directory for hybrid assembly
    mkdir -p hybrid_assembly/${id}

    # Log the start of the process
    echo " Starting hybrid assembly for sample: $id"
    echo " Input files:"
    echo " - MEGAHIT contigs: ${megahit_contigs}"
    echo " - metaSPAdes contigs: ${metaspades_contigs}"

    # Merge MEGAHIT and metaSPAdes contigs into a single file
    echo " Merging MEGAHIT and metaSPAdes contigs..."
    cat ${megahit_contigs} ${metaspades_contigs} > hybrid_assembly/${id}/${id}_merged.fasta

    # Verify merging
    if [ ! -f "hybrid_assembly/${id}/${id}_merged.fasta" ]; then
        echo " Error: Failed to merge contigs for sample: $id" >&2
        exit 1
    fi

    # Run CD-HIT-EST for clustering
    echo " Running CD-HIT-EST for strand-specific clustering..."
    cd-hit-est -i hybrid_assembly/${id}/${id}_merged.fasta -o hybrid_assembly/${id}/${id}_merged_cdhit.fasta -n 10 -c 0.9 -M 0 -T ${task.cpus}

    # Verify CD-HIT-EST output
    if [ ! -f "hybrid_assembly/${id}/${id}_merged_cdhit.fasta" ]; then
        echo " Error: CD-HIT-EST failed for sample: $id" >&2
        exit 1
    fi

    # Rename the contig headers
    echo " Renaming contig headers for sample: $id"
    python3 ${workflow.projectDir}/nextflow/bin/rename_contigs.py -i hybrid_assembly/${id}/${id}_merged_cdhit.fasta -o hybrid_assembly/${id}/${id}_metanextviro_hybrid_contigs.fa -s hybrid

    # Verify renamed contigs
    if [ ! -f "hybrid_assembly/${id}/${id}_metanextviro_hybrid_contigs.fa" ]; then
        echo " Error: Failed to rename contigs for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " Hybrid assembly completed successfully for sample: $id"
    """
}
