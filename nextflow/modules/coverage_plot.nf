// Coverage plot per contig/sample
process coverage_plot {
    tag "$id"
    label 'process_medium'

    publishDir "${params.outdir}/coverage_plots", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(coverage_stats)

    output:
        tuple val(id), path("coverage_plot_${id}.png"), emit: plot

    script:
    """
    python3 -c "
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Read coverage data
df = pd.read_csv('${coverage_stats}', sep='\t')

# Create bar plot of coverage per contig
plt.figure(figsize=(12, 6))
bars = plt.bar(range(len(df)), df['Average_Coverage'])
plt.title('Contig Coverage for ${id}')
plt.xlabel('Contigs')
plt.ylabel('Average Coverage')
plt.xticks(range(len(df)), df['Contig'], rotation=45, ha='right')

# Add value labels on bars
for i, bar in enumerate(bars):
    height = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2., height + 0.1,
             f'{height:.1f}', ha='center', va='bottom', fontsize=8)

plt.tight_layout()
plt.savefig('coverage_plot_${id}.png', dpi=300, bbox_inches='tight')
plt.close()
"
    """
} 