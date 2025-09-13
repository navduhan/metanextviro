# HPC Configuration Examples

This document provides configuration examples for running MetaNextViro on different HPC environments and cluster systems.

## Table of Contents

- [SLURM Clusters](#slurm-clusters)
- [PBS/Torque Clusters](#pbstorque-clusters)
- [SGE Clusters](#sge-clusters)
- [Cloud Environments](#cloud-environments)
- [Partition Configuration](#partition-configuration)
- [Resource Optimization](#resource-optimization)

## SLURM Clusters

### Standard SLURM Configuration

#### Basic Setup
```bash
# Standard SLURM execution with default settings
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /path/to/kraken2_db \
  --checkv_db /path/to/checkv_db \
  -profile slurm
```

#### Custom Partition Names
Different SLURM clusters use different partition naming conventions. Configure your cluster's partition names:

```bash
# Example for clusters with different partition names
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'cpu' \
  --partitions.bigmem 'highmem' \
  --partitions.gpu 'gpu_v100' \
  --partitions.quick 'express' \
  -profile slurm
```

#### Common SLURM Partition Configurations

**Academic HPC Centers:**
```bash
# Example: Many university clusters
--partitions.compute 'general' \
--partitions.bigmem 'bigmem' \
--partitions.gpu 'gpu' \
--partitions.quick 'debug'
```

**National Computing Centers:**
```bash
# Example: XSEDE/ACCESS resources
--partitions.compute 'compute' \
--partitions.bigmem 'large-mem' \
--partitions.gpu 'gpu-shared' \
--partitions.quick 'shared'
```

**Commercial Cloud HPC:**
```bash
# Example: AWS ParallelCluster
--partitions.compute 'compute' \
--partitions.bigmem 'memory-optimized' \
--partitions.gpu 'gpu-compute' \
--partitions.quick 'spot'
```

### Advanced SLURM Configuration

#### Custom Resource Limits
```bash
# Override default resource limits for your cluster
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --max_cpus 128 \
  --max_memory '1000.GB' \
  --max_time '72.h' \
  -profile slurm
```

#### Partition Thresholds
```bash
# Customize when to use different partitions
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partition_thresholds.bigmem_memory_gb 256 \
  --partition_thresholds.quick_time_hours 0.5 \
  --partition_thresholds.quick_memory_gb 32 \
  -profile slurm
```

#### Account and QOS Settings
```bash
# Add account and QOS for SLURM accounting
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --custom_cluster_options '--account=myproject --qos=normal' \
  -profile slurm
```

## PBS/Torque Clusters

### Basic PBS Configuration

Create a custom profile for PBS systems:

```groovy
// Add to nextflow.config
profiles {
    pbs {
        process.executor = 'pbs'
        executor {
            name = 'pbs'
            queueSize = 50
        }
        process {
            queue = 'batch'
            cpus = 8
            memory = '32.GB'
            time = '12.h'
            
            withLabel: 'process_memory_intensive' {
                queue = 'bigmem'
                memory = '128.GB'
            }
            
            withLabel: 'process_quick' {
                queue = 'express'
                time = '1.h'
            }
        }
    }
}
```

Usage:
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  -profile pbs
```

## SGE Clusters

### Basic SGE Configuration

```groovy
// Add to nextflow.config
profiles {
    sge {
        process.executor = 'sge'
        executor {
            name = 'sge'
            queueSize = 100
        }
        process {
            queue = 'all.q'
            penv = 'smp'
            cpus = 8
            memory = '32.GB'
            time = '12.h'
            
            withLabel: 'process_memory_intensive' {
                queue = 'bigmem.q'
                memory = '128.GB'
            }
        }
    }
}
```

## Cloud Environments

### AWS Batch Configuration

```groovy
// Add to nextflow.config
profiles {
    awsbatch {
        process.executor = 'awsbatch'
        process.queue = 'nextflow-queue'
        aws.region = 'us-east-1'
        aws.batch.cliPath = '/home/ec2-user/miniconda/bin/aws'
        
        process {
            withLabel: 'process_low' {
                cpus = 2
                memory = '4.GB'
            }
            withLabel: 'process_medium' {
                cpus = 4
                memory = '8.GB'
            }
            withLabel: 'process_high' {
                cpus = 8
                memory = '16.GB'
            }
            withLabel: 'process_memory_intensive' {
                cpus = 4
                memory = '32.GB'
            }
        }
    }
}
```

### Google Cloud Platform

```groovy
// Add to nextflow.config
profiles {
    gcp {
        process.executor = 'google-batch'
        google.project = 'my-project-id'
        google.location = 'us-central1'
        
        process {
            machineType = 'n1-standard-4'
            disk = '100.GB'
            
            withLabel: 'process_memory_intensive' {
                machineType = 'n1-highmem-8'
                disk = '200.GB'
            }
        }
    }
}
```

## Partition Configuration

### Intelligent Partition Selection

The pipeline automatically selects partitions based on process requirements:

| Process Type | Memory Threshold | Time Threshold | Selected Partition |
|--------------|------------------|----------------|-------------------|
| `process_memory_intensive` | > 128 GB | Any | `bigmem` |
| `process_gpu` | Any | Any | `gpu` |
| `process_quick` | ≤ 16 GB | ≤ 1 hour | `quick` |
| Others | ≤ 128 GB | > 1 hour | `compute` |

### Custom Partition Mapping

Define specific partitions for each process type:

```bash
# Method 1: Command line parameters
nextflow run main.nf \
  --partition_selection_strategy user_defined \
  --custom_partition_mapping.process_low 'debug' \
  --custom_partition_mapping.process_medium 'compute' \
  --custom_partition_mapping.process_high 'compute' \
  --custom_partition_mapping.process_memory_intensive 'bigmem' \
  --custom_partition_mapping.process_gpu 'gpu_v100' \
  --custom_partition_mapping.process_quick 'express'
```

```groovy
// Method 2: Configuration file
params {
    partition_selection_strategy = 'user_defined'
    custom_partition_mapping = [
        'process_low': 'debug',
        'process_medium': 'compute',
        'process_high': 'compute', 
        'process_memory_intensive': 'bigmem',
        'process_gpu': 'gpu_v100',
        'process_quick': 'express'
    ]
}
```

### Partition Fallback Configuration

Configure fallback partitions when primary partitions are unavailable:

```groovy
params {
    partition_fallbacks = [
        'bigmem': ['compute', 'general'],
        'gpu': ['compute'],
        'express': ['debug', 'compute'],
        'compute': []
    ]
}
```

## Resource Optimization

### Memory-Optimized Configuration

For memory-intensive datasets:

```bash
nextflow run main.nf \
  --input large_dataset.csv \
  --outdir results \
  --partition_thresholds.bigmem_memory_gb 64 \
  --max_retry_scaling 3 \
  --enable_retry_scaling true \
  -profile slurm
```

### CPU-Optimized Configuration

For CPU-intensive workloads:

```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --max_cpus 64 \
  --max_forks 10 \
  --assembler megahit \
  -profile slurm
```

### Time-Optimized Configuration

For quick turnaround:

```bash
nextflow run main.nf \
  --input small_dataset.csv \
  --outdir results \
  --partition_thresholds.quick_time_hours 2 \
  --partition_thresholds.quick_memory_gb 32 \
  --max_forks 20 \
  -profile slurm
```

## Environment-Specific Examples

### Shared HPC Systems

Conservative resource usage for shared systems:

```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --max_forks 5 \
  --max_retry_scaling 2 \
  --enable_retry_scaling true \
  --custom_cluster_options '--nice=100' \
  -profile slurm
```

### Dedicated Compute Nodes

Aggressive resource usage for dedicated systems:

```bash
nextflow run main.nf \
  --input large_dataset.csv \
  --outdir results \
  --max_forks 50 \
  --max_retry_scaling 5 \
  --enable_retry_scaling true \
  --partition_selection_strategy intelligent \
  -profile slurm
```

### Development and Testing

Quick testing configuration:

```bash
nextflow run main.nf \
  --input test_samples.csv \
  --outdir test_results \
  --partition_selection_strategy static \
  --partitions.compute 'debug' \
  --max_time '1.h' \
  --max_memory '16.GB' \
  -profile slurm
```

## Troubleshooting HPC Configurations

### Common Issues and Solutions

1. **Partition not found**: Check partition names with `sinfo -s`
2. **Resource limits exceeded**: Verify cluster limits with `scontrol show partition`
3. **Account/QOS issues**: Add account information to `custom_cluster_options`
4. **Environment conflicts**: Use `--env_mode per_process` for isolation

### Debugging Commands

```bash
# Check SLURM partition information
sinfo -s

# Check resource limits
scontrol show partition <partition_name>

# Monitor job status
squeue -u $USER

# Check job details
scontrol show job <job_id>
```