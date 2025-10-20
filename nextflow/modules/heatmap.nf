// Comparative heatmap visualization
process heatmap {
    label 'process_medium'
    publishDir "${params.outdir}/heatmaps", mode: 'copy', overwrite: true

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