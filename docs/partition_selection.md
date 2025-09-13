# SLURM Partition Selection System

## Overview

The MetaNextViro pipeline includes an intelligent SLURM partition selection system that automatically chooses the most appropriate partition for each process based on resource requirements, process labels, and configurable thresholds.

## Features

### Intelligent Partition Selection
- **Memory-based Selection**: Automatically routes memory-intensive processes to bigmem partitions
- **GPU Detection**: Routes GPU-accelerated processes to GPU partitions
- **Quick Job Optimization**: Routes short, low-resource jobs to quick partitions for faster turnaround
- **Fallback Logic**: Graceful degradation when preferred partitions are unavailable

### Configurable Strategies
- **Intelligent**: Dynamic selection based on resource requirements (default)
- **Static**: All jobs go to compute partition
- **User-defined**: Custom partition mapping per process label

### Partition Types Supported
- **compute**: Standard computational workloads
- **bigmem**: Memory-intensive processes (>128GB by default)
- **gpu**: GPU-accelerated processes
- **quick**: Short-running, low-resource jobs (<1h, <16GB by default)

## Configuration

### Basic Partition Mapping
```groovy
params {
    partitions = [
        compute: 'compute',
        bigmem: 'bigmem',
        gpu: 'gpu',
        quick: 'quickq'
    ]
    default_partition = 'compute'
}
```

### Selection Strategy
```groovy
params {
    partition_selection_strategy = 'intelligent' // Options: 'intelligent', 'static', 'user_defined'
}
```

### Thresholds Configuration
```groovy
params {
    partition_thresholds = [
        bigmem_memory_gb: 128,      // Memory threshold for bigmem partition
        quick_time_hours: 1,        // Time threshold for quick partition
        quick_memory_gb: 16,        // Memory threshold for quick partition
        gpu_labels: ['process_gpu'] // Labels that require GPU partition
    ]
}
```

### Fallback Configuration
```groovy
params {
    partition_fallbacks = [
        bigmem: ['compute'],        // If bigmem unavailable, try compute
        gpu: ['compute'],           // If gpu unavailable, try compute
        quick: ['compute'],         // If quick unavailable, try compute
        compute: []                 // No fallback for compute
    ]
}
```

### Custom Partition Mapping (User-defined Strategy)
```groovy
params {
    partition_selection_strategy = 'user_defined'
    custom_partition_mapping = [
        'process_low': 'quick',
        'process_medium': 'compute',
        'process_high': 'compute',
        'process_memory_intensive': 'bigmem',
        'process_gpu': 'gpu'
    ]
}
```

## Process Labels and Partition Selection

### Automatic Selection Rules (Intelligent Strategy)

| Process Label | Memory Requirement | Time Requirement | Selected Partition |
|---------------|-------------------|------------------|-------------------|
| `process_gpu` | Any | Any | gpu → compute |
| `process_memory_intensive` | >128GB (configurable) | Any | bigmem → compute |
| `process_quick` | ≤16GB (configurable) | ≤1h (configurable) | quick → compute |
| `process_high` | ≤128GB | Any | compute |
| `process_medium` | Any | Any | compute |
| `process_low` | ≤16GB | ≤1h | quick → compute |

### Priority Order
1. **GPU processes** (highest priority)
2. **Memory-intensive processes**
3. **Quick processes**
4. **High-performance processes**
5. **Default compute partition**

## Cluster Options Generation

The system automatically generates appropriate SLURM cluster options based on the selected partition and process requirements:

### Partition-specific Options
- **bigmem**: `--constraint=bigmem`, `--exclusive` (for >256GB jobs)
- **gpu**: `--gres=gpu:1`, `--constraint=gpu`
- **quick**: `--qos=quick`, `--nice=100`
- **compute**: `--constraint=compute` (for high-CPU jobs)

### Label-specific Options
- **process_memory_intensive**: `--mem-per-cpu=8G`
- **process_gpu**: `--gres=gpu:1`
- **process_quick**: `--nice=100`, `--no-requeue`
- **process_high**: `--exclusive`
- **process_low**: `--share`

## Usage Examples

### Running with Default Configuration
```bash
nextflow run main.nf -profile slurm
```

### Custom Partition Configuration
```bash
nextflow run main.nf -profile slurm \
  --partitions.compute 'my_compute' \
  --partitions.bigmem 'my_bigmem' \
  --partition_thresholds.bigmem_memory_gb 256
```

### Static Partition Selection
```bash
nextflow run main.nf -profile slurm \
  --partition_selection_strategy 'static' \
  --partitions.compute 'my_partition'
```

### User-defined Mapping
```bash
nextflow run main.nf -profile slurm \
  --partition_selection_strategy 'user_defined' \
  --custom_partition_mapping.process_high 'special_partition'
```

## Validation and Testing

### Configuration Validation
The system includes comprehensive validation for:
- Partition mapping completeness
- Threshold value ranges
- Fallback configuration consistency
- Circular fallback detection

### Testing Partition Selection
Use the included test script to validate partition selection logic:
```bash
nextflow run nextflow/bin/test_partition_selection.nf
```

This generates a detailed report showing:
- Expected vs. actual partition selection for each process type
- Generated cluster options
- Pass/fail status for each test case

### Validation Functions
```groovy
// Validate partition configuration
def results = ConfigValidator.validatePartitionConfiguration(params)

// Test partition selection
def testResults = PartitionManager.validatePartitionSelection(params)
```

## Troubleshooting

### Common Issues

1. **Partition Not Available**
   - Check SLURM partition names with `sinfo`
   - Verify partition mapping in configuration
   - Check fallback configuration

2. **Jobs Stuck in Queue**
   - Verify resource requirements don't exceed partition limits
   - Check partition availability and resource usage
   - Review cluster options generation

3. **Unexpected Partition Selection**
   - Run partition selection tests
   - Check threshold configuration
   - Verify process labels are correct

### Debug Mode
Enable debug logging for partition selection:
```groovy
params {
    enable_partition_validation = true
}
```

This logs partition selection decisions for each process.

### Manual Override
Override partition selection for specific processes:
```groovy
process {
    withName: 'SPECIFIC_PROCESS' {
        queue = 'my_custom_partition'
    }
}
```

## Advanced Configuration

### GPU-specific Configuration
```groovy
params {
    gpu_type = 'v100'  // Specific GPU type
    gpu_memory_required = '32G'  // Minimum GPU memory
}
```

### Custom Cluster Options
```groovy
params {
    custom_cluster_options = ['--account=my_account', '--reservation=my_reservation']
}
```

### Environment-specific Partitions
```groovy
// Development environment
if (params.env == 'dev') {
    params.partitions.compute = 'dev_compute'
    params.partitions.bigmem = 'dev_bigmem'
}

// Production environment
if (params.env == 'prod') {
    params.partitions.compute = 'prod_compute'
    params.partitions.bigmem = 'prod_bigmem'
}
```

## Integration with Other Systems

### SGE/PBS Adaptation
The partition selection system can be adapted for other schedulers by:
1. Modifying cluster options generation
2. Updating partition availability checks
3. Adjusting scheduler-specific parameters

### Cloud Integration
For cloud environments, partition selection can be mapped to:
- Instance types (compute, memory-optimized, GPU instances)
- Spot vs. on-demand instances
- Different availability zones

## Performance Considerations

### Resource Efficiency
- Quick jobs avoid blocking large partitions
- Memory-intensive jobs get appropriate resources
- GPU jobs only use GPU partitions when needed

### Queue Optimization
- Intelligent selection reduces queue wait times
- Fallback logic prevents job failures
- Priority-based selection optimizes resource utilization

### Monitoring
Monitor partition selection effectiveness:
- Job completion times by partition
- Queue wait times
- Resource utilization efficiency
- Failed job rates by partition type