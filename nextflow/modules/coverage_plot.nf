// Coverage plot per contig/sample
process coverage_plot {
    tag "$id"
    label 'process_medium'

    publishDir "${params.outdir}/coverage_plots", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(bam)

    output:
        tuple val(id), path("coverage_${id}.png"), emit: plot

    script:
    """
    samtools depth ${bam} | awk '{print $3}' > ${id}_depth.txt
    python3 -c "
import matplotlib.pyplot as plt
depth = [int(x.strip()) for x in open('${id}_depth.txt')]
plt.figure(figsize=(10,3))
plt.plot(depth)
plt.title('Coverage for ${id}')
plt.xlabel('Position')
plt.ylabel('Depth')
plt.tight_layout()
plt.savefig('coverage_${id}.png')
"
    """
} 