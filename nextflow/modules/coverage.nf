// Author: Naveen Duhan

// Coverage analysis (read mapping and stats)
process coverage {
    tag "$id"  // Tag the task with the sample ID for traceability
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/coverage_results", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(contigs), path(reads1), path(reads2)  // Input: Sample ID, contigs, and reads

    output:
        tuple val(id), path("${id}.bam"), emit: bam
        tuple val(id), path("coverage_${id}.txt"), emit: stats

    script:
    """
    # Log the start of the process
    echo " Starting coverage analysis for sample: $id"
    echo "Input files:"
    echo " - Contigs: ${contigs}"
    echo " - Reads1: ${reads1}"
    echo " - Reads2: ${reads2}"

    # Index the contigs
    echo " Building Bowtie2 index..."
    bowtie2-build ${contigs} ${id}_index

    # Map reads to contigs
    echo " Mapping reads to contigs..."
    bowtie2 -x ${id}_index -1 ${reads1} -2 ${reads2} --threads ${task.cpus} | samtools view -bS - > ${id}.bam

    # Sort and index BAM file
    echo " Sorting and indexing BAM file..."
    samtools sort -@ ${task.cpus} -o ${id}.sorted.bam ${id}.bam
    mv ${id}.sorted.bam ${id}.bam
    samtools index ${id}.bam

    # Generate contig-level coverage stats
    echo " Calculating coverage statistics..."
    ${projectDir}/nextflow/bin/calculate_contig_coverage.sh ${id}.bam coverage_${id}.txt

    # Verify output files
    if [ ! -f "${id}.bam" ] || [ ! -f "coverage_${id}.txt" ]; then
        echo " Error: Coverage analysis failed for sample: $id" >&2
        exit 1
    fi

    # Log successful completion
    echo " Coverage analysis completed successfully for sample: $id"
    """
} 