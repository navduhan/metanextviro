# SLURM Configuration Examples

This document provides detailed SLURM configuration examples for different cluster setups and use cases.

## Table of Contents

- [Basic SLURM Setup](#basic-slurm-setup)
- [University HPC Centers](#university-hpc-centers)
- [National Computing Centers](#national-computing-centers)
- [Commercial Cloud HPC](#commercial-cloud-hpc)
- [Custom Partition Configurations](#custom-partition-configurations)
- [Resource Optimization](#resource-optimization)

## Basic SLURM Setup

### Standard Configuration
```bash
# Basic SLURM execution with intelligent partition selection
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /path/to/kraken2_db \
  --checkv_db /path/to/checkv_db \
  -profile slurm
```

### With Custom Database Paths
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /shared/databases/kraken2_standard \
  --checkv_db /shared/databases/checkv-db-v1.5 \
  --blastdb_nt /shared/databases/nt/nt \
  --blastdb_nr /shared/databases/nr/nr \
  --diamonddb /shared/databases/diamond/nr.dmnd \
  -profile slurm
```

## University HPC Centers

### Example: Generic University Cluster
```bash
# Common partition names in academic environments
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'general' \
  --partitions.bigmem 'bigmem' \
  --partitions.gpu 'gpu' \
  --partitions.quick 'debug' \
  --custom_cluster_options '--account=research_group' \
  -profile slurm
```

### Example: Multi-PI Cluster
```bash
# Configuration for clusters with PI-based accounting
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'shared' \
  --partitions.bigmem 'highmem' \
  --partitions.gpu 'gpu-shared' \
  --partitions.quick 'express' \
  --custom_cluster_options '--account=pi_lastname --qos=normal' \
  -profile slurm
```

### Example: Condo Cluster Model
```bash
# Configuration for condo-style clusters
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'condo' \
  --partitions.bigmem 'condo-bigmem' \
  --partitions.gpu 'condo-gpu' \
  --partitions.quick 'preempt' \
  --custom_cluster_options '--account=condo_group --qos=condo' \
  -profile slurm
```

## National Computing Centers

### Example: XSEDE/ACCESS Resources
```bash
# Configuration for XSEDE/ACCESS allocations
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'compute' \
  --partitions.bigmem 'large-mem' \
  --partitions.gpu 'gpu-shared' \
  --partitions.quick 'shared' \
  --custom_cluster_options '--account=allocation_id --qos=normal' \
  --max_time '48.h' \
  --max_memory '1500.GB' \
  -profile slurm
```

### Example: NERSC Configuration
```bash
# Configuration for NERSC systems
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'regular' \
  --partitions.bigmem 'bigmem' \
  --partitions.gpu 'gpu' \
  --partitions.quick 'debug' \
  --custom_cluster_options '--account=project_id --qos=regular --constraint=haswell' \
  -profile slurm
```

### Example: TACC Configuration
```bash
# Configuration for TACC systems (Stampede2, Frontera)
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'normal' \
  --partitions.bigmem 'large' \
  --partitions.gpu 'gpu' \
  --partitions.quick 'development' \
  --custom_cluster_options '--account=allocation --partition=normal' \
  --max_cpus 272 \
  --max_memory '1000.GB' \
  -profile slurm
```

## Commercial Cloud HPC

### Example: AWS ParallelCluster
```bash
# Configuration for AWS ParallelCluster
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'compute' \
  --partitions.bigmem 'memory-optimized' \
  --partitions.gpu 'gpu-compute' \
  --partitions.quick 'spot' \
  --scaling_strategy aggressive \
  --enable_dynamic_scaling true \
  -profile slurm
```

### Example: Google Cloud HPC
```bash
# Configuration for Google Cloud HPC
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'compute' \
  --partitions.bigmem 'highmem' \
  --partitions.gpu 'gpu' \
  --partitions.quick 'preemptible' \
  --max_forks 100 \
  --enable_performance_optimization true \
  -profile slurm
```

### Example: Azure CycleCloud
```bash
# Configuration for Azure CycleCloud
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'hpc' \
  --partitions.bigmem 'memory' \
  --partitions.gpu 'gpu' \
  --partitions.quick 'lowpri' \
  --scaling_strategy adaptive \
  -profile slurm
```

## Custom Partition Configurations

### High-Memory Workloads
```bash
# Optimized for memory-intensive analysis
nextflow run main.nf \
  --input large_samples.csv \
  --outdir results \
  --partition_thresholds.bigmem_memory_gb 64 \
  --partitions.bigmem 'himem' \
  --partitions.compute 'standard' \
  --assembler metaspades \
  --max_memory '2000.GB' \
  -profile slurm
```

### GPU-Accelerated Processing
```bash
# Configuration for GPU-enabled tools
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.gpu 'gpu_v100' \
  --partitions.compute 'cpu' \
  --custom_cluster_options '--gres=gpu:v100:1' \
  --enable_gpu_acceleration true \
  -profile slurm
```

### Quick Turnaround Analysis
```bash
# Optimized for fast processing
nextflow run main.nf \
  --input urgent_samples.csv \
  --outdir results \
  --partition_thresholds.quick_time_hours 2 \
  --partition_thresholds.quick_memory_gb 64 \
  --partitions.quick 'express' \
  --assembler megahit \
  --blastx_tool diamond \
  --max_forks 50 \
  -profile slurm
```

### Development and Testing
```bash
# Configuration for development work
nextflow run main.nf \
  --input test_samples.csv \
  --outdir dev_results \
  --partition_selection_strategy static \
  --partitions.compute 'debug' \
  --max_time '2.h' \
  --max_memory '32.GB' \
  --max_forks 5 \
  -profile slurm
```

## Resource Optimization

### Conservative Resource Usage
```bash
# For shared systems with strict policies
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --scaling_strategy conservative \
  --max_forks 10 \
  --max_retry_scaling 2 \
  --custom_cluster_options '--nice=100' \
  -profile slurm
```

### Aggressive Resource Usage
```bash
# For dedicated systems or urgent analysis
nextflow run main.nf \
  --input large_dataset.csv \
  --outdir results \
  --scaling_strategy aggressive \
  --max_forks 100 \
  --max_retry_scaling 5 \
  --max_parallel_samples 50 \
  --enable_performance_optimization true \
  -profile slurm
```

### Balanced Resource Usage
```bash
# Recommended for most production workloads
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --scaling_strategy adaptive \
  --max_forks 25 \
  --max_retry_scaling 3 \
  --enable_intelligent_parallelization true \
  --enable_performance_monitoring true \
  -profile slurm
```

## Advanced SLURM Features

### Job Arrays for Large Sample Sets
```bash
# Optimize for many samples
nextflow run main.nf \
  --input many_samples.csv \
  --outdir results \
  --max_parallel_samples 100 \
  --sample_count_threshold 20 \
  --enable_intelligent_parallelization true \
  --custom_cluster_options '--array=1-100%10' \
  -profile slurm
```

### Multi-Cluster Configuration
```bash
# Configuration for multi-cluster environments
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --partitions.compute 'cluster1:compute,cluster2:normal' \
  --partitions.bigmem 'cluster1:bigmem,cluster2:large' \
  --custom_cluster_options '--clusters=cluster1,cluster2' \
  -profile slurm
```

### Reservation-Based Execution
```bash
# Use SLURM reservations
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --custom_cluster_options '--reservation=my_reservation' \
  --max_time '24.h' \
  -profile slurm
```

## Troubleshooting SLURM Issues

### Check Partition Availability
```bash
# Verify partitions exist and are accessible
sinfo -s
sinfo -p compute,bigmem,gpu,debug

# Check partition limits
scontrol show partition compute
```

### Monitor Job Status
```bash
# Check job queue
squeue -u $USER

# Check job details
scontrol show job <job_id>

# Check accounting information
sacct -j <job_id> --format=JobID,JobName,State,ExitCode,MaxRSS
```

### Debug Resource Issues
```bash
# Check resource usage
sstat -j <job_id> --format=JobID,MaxRSS,MaxVMSize,AveCPU

# Check node information
scontrol show node <node_name>
```

## Configuration File Examples

### Custom SLURM Profile
```groovy
// Add to nextflow.config
profiles {
    custom_slurm {
        process.executor = 'slurm'
        
        params {
            // Custom partition mapping
            partitions = [
                compute: 'my_compute_partition',
                bigmem: 'my_bigmem_partition',
                gpu: 'my_gpu_partition',
                quick: 'my_debug_partition'
            ]
            
            // Custom thresholds
            partition_thresholds = [
                bigmem_memory_gb: 256,
                quick_time_hours: 1,
                quick_memory_gb: 32
            ]
            
            // Custom cluster options
            custom_cluster_options = [
                '--account=my_account',
                '--qos=normal'
            ]
        }
        
        process {
            queue = { selectOptimalPartition(task.label, task.memory, task.time) }
            
            withLabel: 'process_memory_intensive' {
                clusterOptions = '--mem-per-cpu=16G --exclusive'
            }
            
            withLabel: 'process_gpu' {
                clusterOptions = '--gres=gpu:v100:1 --constraint=gpu'
            }
        }
    }
}
```

### Site-Specific Configuration
```groovy
// Site-specific configuration file: conf/site.config
params {
    // Database paths for this site
    kraken2_db = '/shared/databases/kraken2/standard'
    checkv_db = '/shared/databases/checkv/checkv-db-v1.5'
    blastdb_nt = '/shared/databases/blast/nt/nt'
    blastdb_nr = '/shared/databases/blast/nr/nr'
    diamonddb = '/shared/databases/diamond/nr.dmnd'
    
    // Site-specific partitions
    partitions = [
        compute: 'general',
        bigmem: 'himem',
        gpu: 'gpu_k80',
        quick: 'debug'
    ]
    
    // Site-specific limits
    max_cpus = 40
    max_memory = '512.GB'
    max_time = '72.h'
    
    // Account information
    custom_cluster_options = ['--account=research_group']
}

// Include in main nextflow.config:
// includeConfig 'conf/site.config'
```