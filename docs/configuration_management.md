# Enhanced Configuration Management System

## Overview

The MetaNextViro pipeline now includes an enhanced configuration management system that provides:

- **Standardized Resource Profiles**: Consistent resource allocation across different computing environments
- **Dynamic Resource Scaling**: Automatic resource adjustment based on retry attempts
- **Configuration Validation**: Comprehensive validation of resource settings and database paths
- **Intelligent Partition Selection**: Automatic SLURM partition selection based on job requirements

## Configuration Files

### Base Configuration (`nextflow/configs/base.config`)

The base configuration provides standardized resource profiles that are inherited by all execution profiles:

- `process_low`: Light computational tasks (2-4 CPUs, 4-8GB memory)
- `process_medium`: Standard analysis tasks (4-8 CPUs, 8-16GB memory)  
- `process_high`: Intensive computational tasks (8-16 CPUs, 16-32GB memory)
- `process_memory_intensive`: Memory-heavy tasks (4-8 CPUs, 32-64GB+ memory)
- `process_gpu`: GPU-accelerated tasks
- `process_quick`: Fast, small tasks for quick queues

### Profile-Specific Configurations

#### Local Profile (`nextflow/configs/local.config`)
- Optimized for workstation environments
- Conservative resource allocation
- Automatic detection of system capabilities
- Limited parallelization to prevent resource contention

#### SLURM Profile (`nextflow/configs/slurm.config`)
- Optimized for HPC cluster environments
- Intelligent partition selection based on job requirements
- Dynamic cluster options generation
- Support for multiple partition types (compute, bigmem, gpu, quickq)

### Resource Profiles (`nextflow/configs/resource_profiles.config`)
Pre-defined resource profiles for different system sizes:
- `test`: Minimal resources for testing
- `small`: Small workstation (4 CPUs, 16GB RAM)
- `medium`: Medium workstation (16 CPUs, 64GB RAM)
- `large_hpc`: Large HPC system (128+ CPUs, 1TB+ RAM)
- `gpu_enabled`: GPU-accelerated systems

## Dynamic Resource Scaling

The system implements retry scaling where resources automatically increase with each retry attempt:

```groovy
cpus = { check_max(base_cpus * task.attempt, max_cpus) }
memory = { check_max(base_memory * task.attempt, max_memory) }
time = { check_max(base_time * task.attempt, max_time) }
```

### Benefits:
- **Automatic Recovery**: Failed jobs get more resources on retry
- **Resource Efficiency**: Start with minimal resources, scale as needed
- **Failure Resilience**: Handles transient resource issues automatically

## Configuration Parameters

### Resource Management
```groovy
params {
    max_cpus = 16                    // Maximum CPUs per process
    max_memory = '64.GB'             // Maximum memory per process
    max_time = '24.h'                // Maximum time per process
    max_forks = 10                   // Maximum parallel processes
    max_retry_scaling = 3            // Maximum retry scaling factor
    enable_retry_scaling = true      // Enable/disable retry scaling
}
```

### SLURM Partition Configuration
```groovy
params {
    partitions = [
        compute: 'compute',          // Standard compute partition
        bigmem: 'bigmem',           // High-memory partition
        gpu: 'gpu',                 // GPU partition
        quick: 'quickq'             // Quick/short job partition
    ]
    default_partition = 'compute'    // Fallback partition
}
```

### Validation Settings
```groovy
params {
    validate_resources = true        // Enable resource validation
    validate_databases = true        // Enable database path validation
    strict_validation = false        // Enable strict validation mode
}
```

## Configuration Validation

### Automatic Validation
The system automatically validates:
- Resource parameter consistency
- Database path accessibility
- Profile configuration completeness
- Executor-specific settings

### Manual Validation
Run configuration validation manually:
```bash
nextflow run nextflow/bin/validate_config.nf -profile <your_profile>
```

### Validation Categories
1. **Resource Configuration**: CPU, memory, and time limits
2. **Profile Consistency**: Required process labels and scaling logic
3. **Executor Configuration**: SLURM, local, or other executor settings
4. **Database Paths**: Required and optional database accessibility

## Configuration Initialization

### Auto-Detection
Initialize configuration for your system:
```bash
nextflow run nextflow/bin/init_config.nf
```

This script will:
- Detect system capabilities (CPUs, memory)
- Recommend appropriate resource profile
- Generate example configuration
- Provide optimization suggestions

### Example Output
```
Detected system capabilities:
  CPUs: 16
  Memory: 64GB
  Executor: local

Recommended configuration profile: medium

Configuration suggestions for your system:
  max_forks: 8
  max_cpus: 16
  max_memory: '51.GB'
```

## SLURM Partition Selection

### Automatic Selection Logic
The system automatically selects appropriate SLURM partitions based on:

1. **Memory Requirements**: 
   - `> 128GB` → bigmem partition
   - `≤ 128GB` → compute partition

2. **Process Labels**:
   - `process_memory_intensive` → bigmem partition
   - `process_gpu` → gpu partition
   - `process_quick` → quick partition

3. **Time Requirements**:
   - `≤ 1 hour` → quick partition (if available)
   - `> 1 hour` → compute partition

### Custom Partition Mapping
Override default partition selection:
```groovy
params {
    partitions = [
        compute: 'my_compute_queue',
        bigmem: 'my_bigmem_queue',
        gpu: 'my_gpu_queue',
        quick: 'my_quick_queue'
    ]
}
```

## Error Handling and Recovery

### Enhanced Error Strategy
```groovy
errorStrategy = { task.exitStatus in [143,137,104,134,139] ? 'retry' : 'finish' }
```

Automatically retries on:
- `143`: SIGTERM (job killed by scheduler)
- `137`: SIGKILL (out of memory)
- `104`: Connection reset
- `134`: SIGABRT (abort signal)
- `139`: SIGSEGV (segmentation fault)

### Resource Scaling on Failure
When a job fails due to resource constraints:
1. **Retry Attempt**: Automatically increases resources
2. **Scaling Factor**: Multiplies by `task.attempt`
3. **Maximum Limits**: Respects configured maximum values
4. **Fallback**: Uses alternative partitions if available

## Usage Examples

### Basic Usage with Profile
```bash
nextflow run main.nf -profile slurm --max_cpus 32 --max_memory '128.GB'
```

### Custom Resource Profile
```bash
nextflow run main.nf -profile medium --enable_retry_scaling true --max_retry_scaling 2
```

### SLURM with Custom Partitions
```bash
nextflow run main.nf -profile slurm \
    --partitions.compute 'my_compute' \
    --partitions.bigmem 'my_bigmem' \
    --default_partition 'my_compute'
```

### Validation and Testing
```bash
# Validate configuration
nextflow run nextflow/bin/validate_config.nf -profile slurm

# Initialize configuration
nextflow run nextflow/bin/init_config.nf

# Test with minimal resources
nextflow run main.nf -profile test --max_cpus 2 --max_memory '4.GB'
```

## Best Practices

### Resource Allocation
1. **Start Conservative**: Use base resource profiles and let retry scaling handle increases
2. **Monitor Usage**: Check resource utilization reports to optimize settings
3. **Environment-Specific**: Use appropriate profiles for your computing environment
4. **Database Location**: Place databases on fast local storage when possible

### SLURM Configuration
1. **Partition Mapping**: Configure partition names to match your cluster
2. **Queue Limits**: Respect cluster policies for job limits and priorities
3. **Resource Requests**: Ensure resource requests match partition capabilities
4. **Fallback Strategy**: Always configure a default partition

### Validation and Testing
1. **Pre-Run Validation**: Always validate configuration before large runs
2. **Test Profiles**: Use test profile for initial validation
3. **Incremental Scaling**: Test with small datasets before full-scale analysis
4. **Monitor Failures**: Review failed jobs to optimize resource allocation

## Troubleshooting

### Common Issues

#### Configuration Validation Failures
```
Error: max_memory must be greater than 0
```
**Solution**: Ensure memory values include units (e.g., '64.GB' not '64')

#### SLURM Partition Errors
```
Error: Invalid partition 'bigmem'
```
**Solution**: Update partition mapping to match your cluster configuration

#### Resource Scaling Issues
```
Warning: max_retry_scaling is very high (10)
```
**Solution**: Reduce max_retry_scaling to prevent excessive resource usage

#### Database Path Errors
```
Error: Database path does not exist: kraken2_db = /path/to/db
```
**Solution**: Verify database paths and ensure they are accessible from compute nodes

### Debug Mode
Enable detailed logging for troubleshooting:
```bash
nextflow run main.nf -profile slurm --validate_resources true --strict_validation true -with-trace -with-report
```

This will generate detailed execution reports and validation information to help diagnose configuration issues.