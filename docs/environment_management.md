# Environment Management System

The MetaNextViro pipeline includes a flexible environment management system that supports both unified and per-process conda environments.

## Overview

The environment management system provides two modes:

1. **Unified Mode**: All tools run in a single conda environment
2. **Per-Process Mode**: Each tool category has its own isolated environment

## Configuration

### Environment Mode Selection

Set the environment mode using the `env_mode` parameter:

```bash
# Use unified environment (default)
nextflow run main.nf --env_mode unified

# Use per-process environments
nextflow run main.nf --env_mode per_process
```

### Environment Files

The system uses environment files located in the `environments/` directory:

#### Unified Mode
- `environments/unified.yml` - Contains all tools in a single environment

#### Per-Process Mode
- `environments/qc.yml` - Quality control tools (FastQC, MultiQC)
- `environments/trimming.yml` - Trimming tools (fastp, flexbar, trim-galore)
- `environments/assembly.yml` - Assembly tools (MEGAHIT, SPAdes, QUAST)
- `environments/annotation.yml` - Annotation tools (BLAST, DIAMOND, CD-HIT)
- `environments/taxonomy.yml` - Taxonomic classification (Kraken2, Krona)
- `environments/viral.yml` - Viral analysis tools (CheckV, VirFinder)
- `environments/alignment.yml` - Alignment tools (Bowtie2, SAMtools, BEDtools)

## Process to Environment Mapping

In per-process mode, each process is automatically mapped to the appropriate environment:

| Process | Environment File |
|---------|------------------|
| FASTQC, MULTIQC | qc.yml |
| FASTP, FLEXBAR, TRIM_GALORE | trimming.yml |
| MEGAHIT, METASPADES, QUAST | assembly.yml |
| BLASTN, BLASTX, DIAMOND_BLASTX | annotation.yml |
| KRAKEN2, KRONA | taxonomy.yml |
| CHECKV, VIRFINDER | viral.yml |
| BOWTIE2, SAMTOOLS, BEDTOOLS | alignment.yml |

## Advantages and Trade-offs

### Unified Mode
**Advantages:**
- Simpler setup and management
- Faster environment creation (single environment)
- No dependency conflicts between tools
- Lower disk space usage

**Trade-offs:**
- Potential for dependency conflicts
- Larger environment size
- All tools must be compatible

### Per-Process Mode
**Advantages:**
- Complete isolation between tool categories
- Easier to update individual tools
- Reduced risk of dependency conflicts
- More granular control

**Trade-offs:**
- Multiple environments to manage
- Longer setup time
- Higher disk space usage
- More complex troubleshooting

## Environment Validation

The system includes built-in validation to ensure environments are properly configured:

```bash
# Validate environment setup
python3 validate_environments.py
```

### Validation Checks
- Environment file existence and readability
- Required YAML fields (name, channels, dependencies)
- Package specification format
- Process to environment mapping

## Configuration Parameters

Additional environment management parameters:

```bash
# Environment validation settings
--validate_environments true          # Enable environment validation
--auto_resolve_conflicts true         # Automatically resolve conflicts
--strict_env_validation false         # Strict validation mode

# Conda-specific settings
--conda_cache_dir /path/to/cache      # Custom conda cache directory
--conda_create_timeout 30m           # Environment creation timeout
--conda_create_options ""             # Additional conda options
```

## Troubleshooting

### Common Issues

1. **Environment file not found**
   - Ensure all required environment files exist in `environments/` directory
   - Check file permissions

2. **Dependency conflicts**
   - Use unified mode to avoid inter-environment conflicts
   - Pin package versions consistently

3. **Conda not available**
   - Install conda or miniconda
   - Ensure conda is in your PATH

4. **Environment creation fails**
   - Check conda channels are configured correctly
   - Verify package availability in specified channels

### Validation Commands

```bash
# Check environment files exist
ls -la environments/

# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('environments/unified.yml'))"

# Test conda environment creation (dry-run)
conda env create -n test_env -f environments/unified.yml --dry-run
```

## Best Practices

1. **Choose the right mode**
   - Use unified mode for simplicity and compatibility
   - Use per-process mode for complex setups with potential conflicts

2. **Version pinning**
   - Pin critical package versions for reproducibility
   - Use version ranges for flexibility

3. **Channel management**
   - Use bioconda for bioinformatics tools
   - Use conda-forge for general packages
   - Maintain consistent channel order

4. **Testing**
   - Validate environments before running the pipeline
   - Test environment creation in isolation
   - Monitor for dependency conflicts

## Examples

### Basic Usage

```bash
# Run with unified environment (default)
nextflow run main.nf --input samplesheet.csv

# Run with per-process environments
nextflow run main.nf --input samplesheet.csv --env_mode per_process
```

### Advanced Configuration

```bash
# Run with custom environment settings
nextflow run main.nf \
  --input samplesheet.csv \
  --env_mode per_process \
  --validate_environments true \
  --auto_resolve_conflicts true \
  --conda_create_timeout 45m
```

### Profile Integration

The environment management system integrates with Nextflow profiles:

```bash
# Use with conda profile
nextflow run main.nf -profile conda --env_mode unified

# Use with SLURM and per-process environments
nextflow run main.nf -profile slurm --env_mode per_process
```