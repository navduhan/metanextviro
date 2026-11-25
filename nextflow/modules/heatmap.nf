// Author: Naveen Duhan
// SPDX-License-Identifier: MIT
// Description: Reads a tab-delimited abundance matrix and plots a comparative heatmap PNG using pandas and seaborn.

process heatmap {
    label 'process_medium'
    conda "${projectDir}/envs/core.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.container_image : params.container_image }"
    publishDir "${params.outdir}/heatmaps", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        path matrix

    output:
        path "heatmap.png", emit: heatmap

    script:
    """
    python3 -c "
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
df = pd.read_csv('${matrix}', sep='\t', index_col=0)
plt.figure(figsize=(10,8))
sns.heatmap(df, cmap='viridis')
plt.title('Comparative Heatmap')
plt.tight_layout()
plt.savefig('heatmap.png')
"
    """
} 