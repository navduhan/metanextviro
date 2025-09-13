# Performance Tuning Guide

This guide provides recommendations for optimizing MetaNextViro performance across different data sizes, computing environments, and system configurations.

## Table of Contents

- [Performance Overview](#performance-overview)
- [Data Size Categories](#data-size-categories)
- [System-Specific Optimizations](#system-specific-optimizations)
- [Resource Scaling Strategies](#resource-scaling-strategies)
- [Tool-Specific Optimizations](#tool-specific-optimizations)
- [Monitoring and Profiling](#monitoring-and-profiling)
- [Benchmarking Results](#benchmarking-results)

## Performance Overview

MetaNextViro includes several performance optimization features:

- **Dynamic Resource Scaling**: Automatically adjusts resources based on input size
- **Intelligent Parallelization**: Optimizes parallel processing for multi-sample workflows
- **Resource Monitoring**: Tracks performance metrics and identifies bottlenecks
- **Adaptive Scaling Strategies**: Choose from conservative, adaptive, or aggressive approaches

### Key Performance Parameters

| Parameter | Description | Impact | Recommended Values |
|-----------|-------------|--------|-------------------|
| `max_forks` | Maximum parallel processes | High | 5-50 (depends on system) |
| `scaling_strategy` | Resource scaling approach | High | `adaptive` (default) |
| `max_parallel_samples` | Parallel sample processing | Medium | 5-20 (depends on data size) |
| `enable_performance_optimization` | Enable optimization features | High | `true` |
| `performance_profiling_level` | Monitoring detail level | Low | `standard` |

## Data Size Categories

### Small Datasets (< 10 GB total)

**Characteristics:**
- 1-5 samples
- < 2 GB per sample
- Quick turnaround needed

**Optimized Configuration:**
```bash
nextflow run main.nf \
  --input small_dataset.csv \
  --outdir results \
  --scaling_strategy conservative \
  --max_forks 10 \
  --max_parallel_samples 5 \
  --partition_thresholds.quick_time_hours 2 \
  --partition_thresholds.quick_memory_gb 32 \
  -profile slurm
```

**Expected Runtime:** 2-6 hours

### Medium Datasets (10-100 GB total)

**Characteristics:**
- 5-20 samples
- 2-10 GB per sample
- Standard processing requirements

**Optimized Configuration:**
```bash
nextflow run main.nf \
  --input medium_dataset.csv \
  --outdir results \
  --scaling_strategy adaptive \
  --max_forks 20 \
  --max_parallel_samples 10 \
  --enable_performance_optimization true \
  --enable_intelligent_parallelization true \
  -profile slurm
```

**Expected Runtime:** 6-24 hours

### Large Datasets (100 GB - 1 TB)

**Characteristics:**
- 20-100 samples
- 5-20 GB per sample
- High-performance requirements

**Optimized Configuration:**
```bash
nextflow run main.nf \
  --input large_dataset.csv \
  --outdir results \
  --scaling_strategy aggressive \
  --max_forks 50 \
  --max_parallel_samples 20 \
  --partition_thresholds.bigmem_memory_gb 64 \
  --enable_performance_optimization true \
  --performance_profiling_level detailed \
  -profile slurm
```

**Expected Runtime:** 1-3 days

### Very Large Datasets (> 1 TB)

**Characteristics:**
- 100+ samples
- > 10 GB per sample
- Requires specialized optimization

**Optimized Configuration:**
```bash
nextflow run main.nf \
  --input very_large_dataset.csv \
  --outdir results \
  --scaling_strategy aggressive \
  --max_forks 100 \
  --max_parallel_samples 50 \
  --input_size_threshold_gb 5 \
  --sample_count_threshold 10 \
  --enable_performance_optimization true \
  --enable_dynamic_scaling true \
  --performance_profiling_level detailed \
  -profile slurm
```

**Expected Runtime:** 3-7 days

## System-Specific Optimizations

### Local Workstations

**System Characteristics:**
- 8-32 CPU cores
- 32-128 GB RAM
- Local storage

**Optimized Settings:**
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --max_forks 4 \
  --max_parallel_samples 2 \
  --scaling_strategy conservative \
  --max_cpus 16 \
  --max_memory '64.GB' \
  -profile local
```

**Performance Tips:**
- Use SSD storage for work directory
- Limit parallel processes to avoid system overload
- Monitor system resources during execution
- Consider using `--assembler megahit` for faster assembly

### HPC Clusters (SLURM)

**System Characteristics:**
- 100s-1000s of CPU cores
- Shared storage (NFS/Lustre)
- Job scheduling system

**Optimized Settings:**
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --max_forks 50 \
  --max_parallel_samples 20 \
  --scaling_strategy adaptive \
  --partition_selection_strategy intelligent \
  --enable_performance_optimization true \
  -profile slurm
```

**Performance Tips:**
- Use appropriate partitions for different job types
- Optimize I/O patterns for shared storage
- Balance job submission rate with cluster policies
- Use `--blastx_tool diamond` for faster annotation

### Cloud Environments

**System Characteristics:**
- Elastic scaling
- Network-attached storage
- Pay-per-use model

**Optimized Settings:**
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --scaling_strategy aggressive \
  --max_forks 100 \
  --enable_dynamic_scaling true \
  --enable_intelligent_parallelization true \
  -profile awsbatch  # or gcp, azure
```

**Performance Tips:**
- Use spot instances for cost optimization
- Optimize data transfer and storage costs
- Consider regional data locality
- Use containerized execution for consistency

## Resource Scaling Strategies

### Conservative Strategy

**When to Use:**
- Shared systems with resource constraints
- Development and testing
- Small to medium datasets

**Configuration:**
```bash
--scaling_strategy conservative \
--max_retry_scaling 2 \
--max_forks 5 \
--max_parallel_samples 3
```

**Characteristics:**
- Lower resource usage
- Longer runtime
- Higher reliability
- Better for shared systems

### Adaptive Strategy (Default)

**When to Use:**
- Most production workloads
- Mixed dataset sizes
- Standard HPC environments

**Configuration:**
```bash
--scaling_strategy adaptive \
--max_retry_scaling 3 \
--enable_dynamic_scaling true \
--enable_intelligent_parallelization true
```

**Characteristics:**
- Balanced resource usage
- Moderate runtime
- Good reliability
- Adapts to system conditions

### Aggressive Strategy

**When to Use:**
- Dedicated systems
- Large datasets
- Time-critical analysis

**Configuration:**
```bash
--scaling_strategy aggressive \
--max_retry_scaling 5 \
--max_forks 50 \
--max_parallel_samples 25
```

**Characteristics:**
- High resource usage
- Shortest runtime
- May stress system resources
- Best for dedicated environments

## Tool-Specific Optimizations

### Assembly Optimization

**MEGAHIT (Fast, Memory Efficient):**
```bash
--assembler megahit \
--min_contig_length 500
```
- Best for: Large datasets, limited memory
- Runtime: Fastest
- Memory: Lowest
- Quality: Good

**metaSPAdes (High Quality):**
```bash
--assembler metaspades \
--min_contig_length 200
```
- Best for: High-quality assemblies, sufficient resources
- Runtime: Slowest
- Memory: Highest
- Quality: Best

**Hybrid (Balanced):**
```bash
--assembler hybrid \
--min_contig_length 300
```
- Best for: Balanced performance and quality
- Runtime: Medium
- Memory: Medium
- Quality: Very good

### Annotation Optimization

**DIAMOND (Recommended):**
```bash
--blastx_tool diamond \
--diamonddb /path/to/nr.dmnd
```
- 100-1000x faster than BLAST
- Lower memory usage
- Comparable sensitivity

**Traditional BLASTX:**
```bash
--blastx_tool blastx \
--blastdb_nr /path/to/nr
```
- Higher sensitivity
- Much slower
- Higher memory usage

### Trimming Tool Optimization

**fastp (Fastest):**
```bash
--trimming_tool fastp \
--quality 20
```

**trim_galore (Most Features):**
```bash
--trimming_tool trim_galore \
--quality 30
```

**flexbar (Balanced):**
```bash
--trimming_tool flexbar \
--quality 25
```

## Monitoring and Profiling

### Enable Performance Monitoring

```bash
nextflow run main.nf \
  --enable_performance_monitoring true \
  --performance_profiling_level detailed \
  -profile slurm
```

### Monitoring Levels

**Minimal:**
- Basic resource usage
- Process completion times
- Error rates

**Standard (Default):**
- CPU and memory usage
- I/O statistics
- Queue times
- Resource efficiency

**Detailed:**
- Per-process profiling
- Bottleneck identification
- Optimization recommendations
- Performance trends

### Performance Metrics

The pipeline tracks several key metrics:

| Metric | Description | Target Range |
|--------|-------------|--------------|
| CPU Efficiency | CPU usage vs. allocated | > 80% |
| Memory Efficiency | Memory usage vs. allocated | 60-90% |
| Queue Time | Time waiting in queue | < 10% of runtime |
| I/O Wait | Time waiting for I/O | < 20% of runtime |
| Process Success Rate | Successful vs. failed processes | > 95% |

### Performance Reports

Performance reports are generated in `results/performance/`:

- `performance_summary.html`: Overall performance overview
- `resource_utilization.png`: Resource usage plots
- `bottleneck_analysis.txt`: Identified bottlenecks
- `optimization_recommendations.txt`: Specific recommendations

## Benchmarking Results

### Sample Performance Data

**Test System:** SLURM cluster with 40-core nodes, 256 GB RAM

| Dataset Size | Samples | Strategy | Runtime | Peak Memory | CPU Hours |
|--------------|---------|----------|---------|-------------|-----------|
| 5 GB | 3 | Conservative | 4h 30m | 32 GB | 48 |
| 5 GB | 3 | Adaptive | 3h 15m | 48 GB | 52 |
| 5 GB | 3 | Aggressive | 2h 45m | 64 GB | 58 |
| 50 GB | 15 | Conservative | 18h 20m | 128 GB | 420 |
| 50 GB | 15 | Adaptive | 12h 45m | 192 GB | 485 |
| 50 GB | 15 | Aggressive | 8h 30m | 256 GB | 520 |
| 200 GB | 50 | Adaptive | 2d 8h | 384 GB | 1,680 |
| 200 GB | 50 | Aggressive | 1d 16h | 512 GB | 1,920 |

### Tool Performance Comparison

**Assembly Tools (50 GB dataset):**
- MEGAHIT: 4h 20m, 64 GB peak memory
- metaSPAdes: 12h 45m, 256 GB peak memory
- Hybrid: 8h 15m, 128 GB peak memory

**Annotation Tools (1M contigs):**
- DIAMOND: 2h 30m, 16 GB memory
- BLASTX: 18h 45m, 32 GB memory

## Optimization Recommendations

### General Guidelines

1. **Start Conservative:** Begin with conservative settings and scale up
2. **Monitor Resources:** Use performance monitoring to identify bottlenecks
3. **Balance Speed vs. Quality:** Choose tools based on requirements
4. **Consider System Limits:** Respect shared system policies
5. **Test Scaling:** Validate performance improvements with test datasets

### System-Specific Tips

**For Workstations:**
- Use local storage for work directory
- Limit parallel processes
- Consider overnight runs for large datasets
- Use DIAMOND for annotation

**For HPC Clusters:**
- Optimize for cluster policies
- Use appropriate partitions
- Balance job submission rate
- Monitor queue times

**For Cloud:**
- Use spot instances when possible
- Optimize data transfer
- Consider regional placement
- Use auto-scaling features

### Troubleshooting Performance Issues

**Slow Performance:**
1. Check resource utilization
2. Verify tool selection
3. Optimize parallelization
4. Check I/O bottlenecks

**High Memory Usage:**
1. Use conservative scaling
2. Reduce parallel processes
3. Choose memory-efficient tools
4. Monitor swap usage

**Long Queue Times:**
1. Use appropriate partitions
2. Reduce resource requests
3. Submit during off-peak hours
4. Consider job arrays

### Advanced Optimization

**Custom Resource Profiles:**
```groovy
// Add to nextflow.config
process {
    withName: 'ASSEMBLY' {
        cpus = { Math.min(32, task.attempt * 8) }
        memory = { Math.min(256.GB, task.attempt * 64.GB) }
        time = { Math.min(48.h, task.attempt * 12.h) }
    }
}
```

**Conditional Optimization:**
```bash
# Optimize based on dataset size
if [ $(du -sb input_data | cut -f1) -gt 107374182400 ]; then
    STRATEGY="aggressive"
    FORKS=50
else
    STRATEGY="adaptive"
    FORKS=20
fi

nextflow run main.nf \
  --scaling_strategy $STRATEGY \
  --max_forks $FORKS \
  -profile slurm
```