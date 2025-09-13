// Author: Naveen Duhan

// Comparative heatmap visualization
process heatmap {
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/heatmap_results", mode: 'copy', overwrite: true

    input:
        path matrix  // Input: Data matrix file for heatmap generation

    output:
        path "heatmap.png", emit: heatmap

    script:
    """
    # Log the start of the process
    echo " Starting heatmap generation"
    echo "Input matrix file: ${matrix}"

    # Generate heatmap using Python
    python3 -c "
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import sys

try:
    # Read the matrix file
    df = pd.read_csv('${matrix}', sep='\t', index_col=0)
    
    # Check if dataframe is empty
    if df.empty:
        print('Error: Matrix file is empty')
        sys.exit(1)
    
    # Create heatmap
    plt.figure(figsize=(10,8))
    sns.heatmap(df, cmap='viridis', annot=True if df.shape[0] <= 20 and df.shape[1] <= 20 else False)
    plt.title('Comparative Heatmap')
    plt.tight_layout()
    plt.savefig('heatmap.png', dpi=300, bbox_inches='tight')
    
    print('Heatmap generated successfully')
    
except Exception as e:
    print(f'Error generating heatmap: {e}')
    sys.exit(1)
"

    # Verify output
    if [ ! -f "heatmap.png" ]; then
        echo " Error: Failed to generate heatmap" >&2
        exit 1
    fi

    # Log successful completion
    echo " Heatmap generation completed successfully"
    """
} 