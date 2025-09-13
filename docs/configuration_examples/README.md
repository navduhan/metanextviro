# Configuration Examples

This directory contains configuration examples for different computing environments and use cases.

## Available Examples

### HPC Environments
- [SLURM Clusters](slurm_examples.md) - Configuration for SLURM-based HPC systems
- [PBS/Torque Clusters](pbs_examples.md) - Configuration for PBS/Torque systems
- [SGE Clusters](sge_examples.md) - Configuration for Sun Grid Engine systems

### Cloud Environments
- [AWS Batch](aws_batch_examples.md) - Configuration for AWS Batch execution
- [Google Cloud](gcp_examples.md) - Configuration for Google Cloud Platform
- [Azure Batch](azure_examples.md) - Configuration for Microsoft Azure

### Specialized Configurations
- [High-Memory Systems](high_memory_examples.md) - Optimized for memory-intensive workloads
- [GPU Clusters](gpu_examples.md) - Configuration for GPU-accelerated processing
- [Development Environments](development_examples.md) - Settings for testing and development

### Environment Management
- [Unified Environments](unified_env_examples.md) - Single conda environment configurations
- [Per-Process Environments](per_process_env_examples.md) - Isolated environment configurations
- [Container Configurations](container_examples.md) - Docker and Singularity setups

## Quick Start Templates

### Basic SLURM Configuration
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /path/to/kraken2_db \
  --checkv_db /path/to/checkv_db \
  -profile slurm
```

### Local Development
```bash
nextflow run main.nf \
  --input test_samples.csv \
  --outdir test_results \
  --max_forks 2 \
  --scaling_strategy conservative \
  -profile local
```

### Cloud Execution
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --scaling_strategy aggressive \
  --enable_dynamic_scaling true \
  -profile awsbatch
```

## Configuration Validation

Before running with a new configuration, validate your setup:

```bash
# Test configuration syntax
nextflow config -profile your_profile

# Validate resource settings
nextflow run main.nf \
  --validate_resources true \
  --strict_validation true \
  -profile your_profile \
  --help

# Test with minimal dataset
nextflow run main.nf \
  --input minimal_test.csv \
  --outdir test_output \
  -profile your_profile
```

## Getting Help

1. Check the [Troubleshooting Guide](../troubleshooting_guide.md)
2. Review the [Performance Tuning Guide](../performance_tuning_guide.md)
3. Examine similar configurations in this directory
4. Create an issue on GitHub with your configuration details