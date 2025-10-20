// Coverage plot per contig/sample
process coverage_plot {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/coverage_plots", mode: 'copy', overwrite: true

    input:
        tuple val(id), path(coverage_stats)

    output:
        tuple val(id), path("coverage_plot_${id}.png"), emit: plot
        tuple val(id), path("coverage_distribution_${id}.png"), optional: true, emit: distribution_plot

    script:
    """
    python3 -c "
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import math
import sys

# Read coverage data
try:
    df = pd.read_csv('${coverage_stats}', sep='\t')
    print(f'Columns in coverage file: {list(df.columns)}')
    print(f'First few rows:')
    print(df.head())
    
    # Check if required columns exist
    required_columns = ['Contig', 'Average_Coverage']
    missing_columns = [col for col in required_columns if col not in df.columns]
    
    if missing_columns:
        print(f'Error: Missing required columns: {missing_columns}')
        print(f'Available columns: {list(df.columns)}')
        sys.exit(1)
    
    # Check for empty dataframe
    if df.empty:
        print('Error: Coverage file is empty')
        sys.exit(1)
    
    # Check for NaN values in Average_Coverage
    if df['Average_Coverage'].isna().any():
        print('Warning: Found NaN values in Average_Coverage, removing them')
        df = df.dropna(subset=['Average_Coverage'])
    
    if df.empty:
        print('Error: No valid coverage data after removing NaN values')
        sys.exit(1)
    
except Exception as e:
    print(f'Error reading coverage file: {e}')
    sys.exit(1)

# Sort by coverage for better visualization
df = df.sort_values('Average_Coverage', ascending=False)

# Create figure with dynamic size based on number of contigs
n_contigs = len(df)
fig_width = max(12, min(20, n_contigs * 0.3))  # Dynamic width based on contig count
fig_height = 8

plt.figure(figsize=(fig_width, fig_height))

# Create bar plot of coverage per contig
bars = plt.bar(range(len(df)), df['Average_Coverage'], alpha=0.7, color='steelblue')

# Set title and labels
plt.title(f'Contig Coverage for ${id} (n={n_contigs} contigs)', fontsize=14, fontweight='bold')
plt.xlabel('Contigs (sorted by coverage)', fontsize=12)
plt.ylabel('Average Coverage', fontsize=12)

# Handle x-axis labels intelligently
if n_contigs <= 20:
    # For small number of contigs, show all labels
    plt.xticks(range(len(df)), df['Contig'], rotation=45, ha='right', fontsize=10)
elif n_contigs <= 50:
    # For medium number, show every 2nd label
    step = 2
    plt.xticks(range(0, len(df), step), df['Contig'].iloc[::step], rotation=45, ha='right', fontsize=9)
else:
    # For large number, show every 5th label and use shorter names
    step = max(1, n_contigs // 20)  # Show max 20 labels
    short_names = df['Contig'].str[:15] + '...'  # Truncate long names
    plt.xticks(range(0, len(df), step), short_names.iloc[::step], rotation=45, ha='right', fontsize=8)

# Add grid for better readability
plt.grid(axis='y', alpha=0.3, linestyle='--')

# Add horizontal line at mean coverage
mean_coverage = df['Average_Coverage'].mean()
plt.axhline(y=mean_coverage, color='red', linestyle='--', alpha=0.7, label=f'Mean: {mean_coverage:.1f}')
plt.legend()

# Add value labels on bars (only for top 10 or if few contigs)
if n_contigs <= 15:
    for i, bar in enumerate(bars):
        height = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2., height + height*0.01,
                 f'{height:.1f}', ha='center', va='bottom', fontsize=8)
else:
    # Only label top 10 bars
    for i, bar in enumerate(bars[:10]):
        height = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2., height + height*0.01,
                 f'{height:.1f}', ha='center', va='bottom', fontsize=8)

# Add statistics text box
max_coverage = df['Average_Coverage'].max()
min_coverage = df['Average_Coverage'].min()
stats_text = f'Total Contigs: {n_contigs}\\nMean Coverage: {mean_coverage:.1f}\\nMax Coverage: {max_coverage:.1f}\\nMin Coverage: {min_coverage:.1f}'
plt.text(0.02, 0.98, stats_text, transform=plt.gca().transAxes, 
         verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8),
         fontsize=10)

plt.tight_layout()
plt.savefig('coverage_plot_${id}.png', dpi=300, bbox_inches='tight')
plt.close()

# Also create a summary plot for very large datasets
if n_contigs > 100:
    plt.figure(figsize=(12, 6))
    
    # Create histogram of coverage distribution
    plt.hist(df['Average_Coverage'], bins=min(30, n_contigs//5), alpha=0.7, color='lightcoral', edgecolor='black')
    plt.title(f'Coverage Distribution for ${id} (n={n_contigs} contigs)', fontsize=14, fontweight='bold')
    plt.xlabel('Average Coverage', fontsize=12)
    plt.ylabel('Number of Contigs', fontsize=12)
    plt.grid(axis='y', alpha=0.3)
    
    # Add vertical line at mean
    plt.axvline(x=mean_coverage, color='red', linestyle='--', alpha=0.7, label=f'Mean: {mean_coverage:.1f}')
    plt.legend()
    
    plt.tight_layout()
    plt.savefig('coverage_distribution_${id}.png', dpi=300, bbox_inches='tight')
    plt.close()

print(f'Successfully created coverage plot for {n_contigs} contigs')
"
    """
} 