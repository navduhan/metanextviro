# Performance Optimization Features

The MetaNextViro pipeline includes comprehensive performance optimization features designed to automatically scale resources, optimize parallelization, and provide detailed performance monitoring and recommendations.

## Overview

The performance optimization system consists of four main components:

1. **Dynamic Resource Scaling** - Automatically adjusts CPU, memory, and time allocations based on input data characteristics
2. **Intelligent Parallelization** - Optimizes parallel processing strategies for multi-sample workflows
3. **Resource Monitoring** - Collects detailed performance metrics during pipeline execution
4. **Performance Profiling** - Analyzes bottlenecks and generates optimization recommendations

## Features

### Dynamic Resource Scaling

The pipeline automatically calculates optimal resource allocations based on:

- **Input Data Size**: Larger datasets receive proportionally more resources
- **Sample Count**: Multi-sample processing gets optimized parallelization
- **Process Type**: Different process labels receive appropriate resource scaling
- **System Capabilities**: Resource allocation respects system limits

#### Scaling Strategies

- **Adaptive** (default): Balances performance and resource efficiency
- **Conservative**: Minimal resource scaling for stable environments
- **Aggressive**: Maximum performance optimization for high-throughput scenarios

#### Process-Specific Scaling

```groovy
// Memory-intensive processes (assembly, large databases)
process_memory_intensive:
  - Memory scaling factor: 2.5x
  - CPU scaling factor: 1.2x
  - Time scaling factor: 2.0x

// High-performance processes (BLAST, alignment)
process_high:
  - Memory scaling factor: 1.5x
  - CPU scaling factor: 2.0x
  - Time scaling factor: 1.5x

// GPU-accelerated processes
process_gpu:
  - Memory scaling factor: 1.8x
  - CPU scaling factor: 1.3x
  - Time scaling factor: 0.7x (GPU acceleration)
```

### Intelligent Parallelization

The system optimizes parallelization based on:

#### Process Characteristics
- **I/O Bound Processes**: Higher parallelization (process_low, process_quick)
- **Memory Intensive**: Limited parallelization to prevent memory contention
- **CPU Intensive**: Balanced parallelization for optimal throughput
- **GPU Processes**: Exclusive execution per GPU

#### Sample-Based Optimization
- **Small Datasets** (< 5 samples): Sequential or low parallelization
- **Medium Datasets** (5-20 samples): Balanced parallelization
- **Large Datasets** (> 20 samples): High parallelization with batching

#### Batch Processing
Automatically calculates optimal batch sizes:
```groovy
process_quick: batch_size = min(10, sample_count / 2)
process_memory_intensive: batch_size = min(2, sample_count / 5)
process_medium: batch_size = min(5, sample_count / 3)
```

### Resource Monitoring

Comprehensive monitoring includes:

#### System Metrics
- CPU utilization and load average
- Memory usage (RSS, VmHWM, swap)
- I/O statistics (read/write bytes, IOPS)
- Disk usage and available space

#### Process Metrics
- Execution time and queue time
- Resource allocation vs. actual usage
- Exit codes and error patterns
- Performance bottleneck identification

#### GPU Monitoring (when applicable)
- GPU utilization percentage
- GPU memory usage
- GPU temperature
- CUDA/OpenCL performance metrics

### Performance Profiling

#### Bottleneck Detection
Automatically identifies:
- **Memory Bottlenecks**: > 95% memory utilization
- **CPU Underutilization**: < 30% average CPU usage
- **Time Bottlenecks**: > 90% of allocated time used
- **I/O Wait Issues**: High I/O wait times

#### Optimization Recommendations
Generates actionable recommendations:
- Resource allocation adjustments
- Parallelization improvements
- Configuration optimizations
- Hardware upgrade suggestions

## Configuration

### Enabling Performance Optimization

```groovy
// Enable all performance features
params {
    enable_performance_optimization = true
    enable_dynamic_scaling = true
    enable_intelligent_parallelization = true
    enable_performance_monitoring = true
}
```

### Scaling Configuration

```groovy
params {
    // Scaling strategy
    scaling_strategy = 'adaptive'  // 'adaptive', 'conservative', 'aggressive'
    
    // Scaling thresholds
    input_size_threshold_gb = 10
    sample_count_threshold = 5
    
    // Scaling factors
    scaling_factors = [
        memory_scaling_factor: 1.5,
        cpu_scaling_factor: 1.2,
        time_scaling_factor: 1.3
    ]
}
```

### Parallelization Configuration

```groovy
params {
    // Parallelization settings
    intelligent_fork_calculation = true
    max_parallel_samples = 20
    batch_processing_enabled = true
    
    // Process-specific settings
    process_optimization = [
        'process_memory_intensive': [
            memory_multiplier: 2.0,
            enable_memory_scaling: true
        ],
        'process_gpu': [
            enable_gpu_monitoring: true,
            gpu_memory_threshold: 0.8
        ]
    ]
}
```

### Monitoring Configuration

```groovy
params {
    // Monitoring settings
    collect_performance_stats = true
    generate_optimization_reports = true
    performance_profiling_level = 'standard'  // 'minimal', 'standard', 'detailed'
    
    // Enable Nextflow reports
    trace.enabled = true
    timeline.enabled = true
    report.enabled = true
}
```

## Usage Examples

### Basic Performance Optimization

```bash
# Run with performance optimization enabled
nextflow run main.nf \
    --input samplesheet.csv \
    --enable_performance_optimization true \
    --scaling_strategy adaptive \
    --performance_profiling_level standard
```

### High-Performance Configuration

```bash
# Aggressive optimization for large datasets
nextflow run main.nf \
    --input large_dataset.csv \
    --enable_performance_optimization true \
    --scaling_strategy aggressive \
    --max_parallel_samples 50 \
    --performance_profiling_level detailed
```

### Conservative Configuration

```bash
# Conservative optimization for shared systems
nextflow run main.nf \
    --input samplesheet.csv \
    --enable_performance_optimization true \
    --scaling_strategy conservative \
    --max_forks 4 \
    --performance_profiling_level minimal
```

## Performance Profiles

### Optimized Profiles

The pipeline includes pre-configured performance profiles:

```bash
# Performance optimized profile
nextflow run main.nf -profile performance_optimized

# Conservative performance profile
nextflow run main.nf -profile conservative_performance

# Aggressive performance profile
nextflow run main.nf -profile aggressive_performance
```

### Profile Characteristics

#### performance_optimized
- Dynamic scaling: enabled
- Intelligent parallelization: enabled
- Detailed monitoring: enabled
- Adaptive retry scaling
- Enhanced error handling

#### conservative_performance
- Dynamic scaling: disabled
- Standard parallelization
- Standard monitoring
- Conservative resource allocation

#### aggressive_performance
- Maximum dynamic scaling
- High parallelization
- Detailed monitoring
- Aggressive scaling factors (2.0x memory, 1.5x CPU)

## Output and Reports

### Performance Reports

The pipeline generates comprehensive performance reports:

```
results/
├── performance/
│   ├── trace.txt                    # Nextflow trace report
│   ├── timeline.html               # Execution timeline
│   ├── report.html                 # Resource usage report
│   ├── dag.svg                     # Workflow DAG
│   ├── pipeline_performance_summary.json
│   ├── performance_analysis.html
│   ├── optimization_recommendations.json
│   └── optimization_report.html
```

### Performance Metrics

#### Summary Statistics
- Total pipeline execution time
- Resource utilization efficiency
- Parallelization effectiveness
- Bottleneck identification

#### Process-Level Metrics
- Individual process performance
- Resource allocation vs. usage
- Optimization opportunities
- Scaling effectiveness

#### Optimization Recommendations
- Resource allocation suggestions
- Parallelization improvements
- Configuration optimizations
- Estimated performance gains

## Troubleshooting

### Common Issues

#### High Memory Usage
```bash
# Check memory-intensive processes
grep "process_memory_intensive" results/performance/trace.txt

# Recommended actions:
# 1. Enable bigmem partition
# 2. Increase memory scaling factor
# 3. Reduce parallelization for memory-intensive processes
```

#### Poor CPU Utilization
```bash
# Check CPU usage patterns
grep "cpu" results/performance/optimization_recommendations.json

# Recommended actions:
# 1. Increase parallelization
# 2. Reduce CPU allocation for underutilized processes
# 3. Enable intelligent fork calculation
```

#### Long Execution Times
```bash
# Identify bottleneck processes
grep "bottleneck" results/performance/performance_analysis.html

# Recommended actions:
# 1. Enable aggressive scaling strategy
# 2. Increase resource allocation for bottleneck processes
# 3. Optimize parallelization strategy
```

### Performance Tuning Tips

1. **Start with adaptive scaling** for most use cases
2. **Monitor resource utilization** in the first few runs
3. **Adjust scaling factors** based on your system characteristics
4. **Use conservative settings** on shared HPC systems
5. **Enable detailed monitoring** for optimization analysis

### System Requirements

#### Minimum Requirements
- 4 CPU cores
- 16 GB RAM
- 100 GB available disk space

#### Recommended for Performance Optimization
- 16+ CPU cores
- 64+ GB RAM
- SSD storage
- High-speed network (for shared storage)

#### Optimal Configuration
- 32+ CPU cores
- 128+ GB RAM
- NVMe SSD storage
- GPU acceleration (optional)
- Dedicated compute nodes

## Advanced Configuration

### Custom Scaling Functions

You can define custom scaling functions for specific processes:

```groovy
process {
    withName: 'CUSTOM_PROCESS' {
        cpus = { 
            def inputSize = task.ext.inputSize ?: 0
            def baseCpus = 4
            def scalingFactor = Math.log(inputSize / (1024*1024*1024) + 1) + 1
            return Math.min(32, baseCpus * scalingFactor)
        }
        
        memory = { 
            def inputSize = task.ext.inputSize ?: 0
            def baseMemory = 8
            def memoryGB = baseMemory * (inputSize / (1024*1024*1024) * 0.1 + 1)
            return "${Math.ceil(memoryGB)}.GB"
        }
    }
}
```

### Integration with External Monitoring

The performance optimization system can integrate with external monitoring tools:

```groovy
// Custom monitoring integration
params {
    external_monitoring = [
        prometheus_endpoint: "http://monitoring.example.com:9090",
        grafana_dashboard: "http://grafana.example.com/dashboard",
        custom_metrics_collector: "/path/to/custom/collector.sh"
    ]
}
```

This comprehensive performance optimization system ensures that the MetaNextViro pipeline runs efficiently across different computing environments while providing detailed insights for continuous improvement.