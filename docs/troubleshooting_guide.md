# Troubleshooting Guide

This guide helps resolve common issues when running MetaNextViro on different computing environments.

## Table of Contents

- [Configuration Issues](#configuration-issues)
- [Resource Management Problems](#resource-management-problems)
- [Environment Management Issues](#environment-management-issues)
- [SLURM Partition Problems](#slurm-partition-problems)
- [Database and Input Validation](#database-and-input-validation)
- [Performance Issues](#performance-issues)
- [Container and Singularity Issues](#container-and-singularity-issues)
- [Common Error Messages](#common-error-messages)

## Configuration Issues

### Problem: "Process label not recognized"

**Symptoms:**
```
ERROR ~ Process 'PROCESS_NAME' declares an unknown label 'old_label'
```

**Cause:** Using outdated process labels from previous versions.

**Solution:**
Update process labels to standardized format:
- `low` → `process_low`
- `medium` → `process_medium` 
- `high` → `process_high`
- `vhigh` → `process_memory_intensive`
- `blast` → `process_high`

**Fix:**
```bash
# Check your custom configuration files for old labels
grep -r "withLabel.*'low'" nextflow/configs/
grep -r "withLabel.*'vhigh'" nextflow/configs/

# Update to new standardized labels
sed -i "s/withLabel: 'low'/withLabel: 'process_low'/g" nextflow/configs/*.config
```

### Problem: "Configuration file not found"

**Symptoms:**
```
ERROR ~ Configuration file 'nextflow/configs/missing.config' not found
```

**Cause:** Missing or incorrectly referenced configuration files.

**Solution:**
1. Verify all configuration files exist:
```bash
ls -la nextflow/configs/
```

2. Check `nextflow.config` for correct include paths:
```groovy
includeConfig 'nextflow/configs/base.config'
includeConfig 'nextflow/configs/validation.config'
```

### Problem: "Invalid parameter value"

**Symptoms:**
```
ERROR ~ Invalid value 'invalid_option' for parameter 'env_mode'
```

**Cause:** Using invalid parameter values.

**Valid Parameter Values:**
- `env_mode`: `unified`, `per_process`
- `partition_selection_strategy`: `intelligent`, `static`, `user_defined`
- `assembler`: `megahit`, `metaspades`, `hybrid`
- `trimming_tool`: `fastp`, `flexbar`, `trim_galore`
- `blastx_tool`: `diamond`, `blastx`

## Resource Management Problems

### Problem: "Out of memory" errors

**Symptoms:**
```
ERROR ~ Process 'ASSEMBLY' terminated with an error exit status (137)
Command error:
  Killed
```

**Cause:** Insufficient memory allocation for the process.

**Solutions:**

1. **Enable retry scaling:**
```bash
nextflow run main.nf \
  --enable_retry_scaling true \
  --max_retry_scaling 3 \
  -profile slurm
```

2. **Increase memory limits:**
```bash
nextflow run main.nf \
  --max_memory '500.GB' \
  -profile slurm
```

3. **Use memory-intensive partition:**
```bash
nextflow run main.nf \
  --partition_thresholds.bigmem_memory_gb 64 \
  -profile slurm
```

### Problem: "CPU limit exceeded"

**Symptoms:**
```
ERROR ~ Process terminated due to CPU limit
```

**Solutions:**

1. **Adjust CPU limits:**
```bash
nextflow run main.nf \
  --max_cpus 64 \
  -profile slurm
```

2. **Reduce parallel processes:**
```bash
nextflow run main.nf \
  --max_forks 5 \
  -profile slurm
```

### Problem: "Time limit exceeded"

**Symptoms:**
```
ERROR ~ Process 'ASSEMBLY' terminated with an error exit status (124)
SLURM: Job exceeded time limit
```

**Solutions:**

1. **Increase time limits:**
```bash
nextflow run main.nf \
  --max_time '48.h' \
  -profile slurm
```

2. **Use appropriate partition:**
```bash
nextflow run main.nf \
  --partition_thresholds.quick_time_hours 0.5 \
  -profile slurm
```

## Environment Management Issues

### Problem: "Conda environment creation failed"

**Symptoms:**
```
ERROR ~ Failed to create conda environment
ResolvePackageNotFound: Package 'tool_name' not found
```

**Cause:** Package conflicts or unavailable packages.

**Solutions:**

1. **Use per-process environments:**
```bash
nextflow run main.nf \
  --env_mode per_process \
  -profile conda
```

2. **Update conda channels:**
```bash
conda config --add channels bioconda
conda config --add channels conda-forge
```

3. **Force environment recreation:**
```bash
# Remove existing environments
rm -rf work/conda/
nextflow run main.nf -profile conda -resume
```

### Problem: "Tool not found in PATH"

**Symptoms:**
```
ERROR ~ Command 'tool_name' not found
```

**Cause:** Tool not installed or not in PATH.

**Solutions:**

1. **Verify conda environment:**
```bash
conda activate metanextviro
which tool_name
```

2. **Check environment configuration:**
```bash
# Verify environment.yml contains the tool
grep -i tool_name environment.yml
```

3. **Use container execution:**
```bash
nextflow run main.nf -profile singularity
```

### Problem: "Environment conflicts"

**Symptoms:**
```
ERROR ~ Conda environment has conflicting dependencies
```

**Solutions:**

1. **Enable conflict resolution:**
```bash
nextflow run main.nf \
  --auto_resolve_conflicts true \
  -profile conda
```

2. **Use per-process environments:**
```bash
nextflow run main.nf \
  --env_mode per_process \
  -profile conda
```

## SLURM Partition Problems

### Problem: "Partition not available"

**Symptoms:**
```
ERROR ~ sbatch: error: Batch job submission failed: Invalid partition name specified
```

**Cause:** Specified partition doesn't exist on the cluster.

**Solutions:**

1. **Check available partitions:**
```bash
sinfo -s
```

2. **Update partition configuration:**
```bash
nextflow run main.nf \
  --partitions.compute 'your_compute_partition' \
  --partitions.bigmem 'your_bigmem_partition' \
  -profile slurm
```

3. **Use static partition selection:**
```bash
nextflow run main.nf \
  --partition_selection_strategy static \
  --default_partition 'available_partition' \
  -profile slurm
```

### Problem: "Partition access denied"

**Symptoms:**
```
ERROR ~ sbatch: error: Access denied to partition 'restricted_partition'
```

**Solutions:**

1. **Configure accessible partitions:**
```bash
nextflow run main.nf \
  --partitions.compute 'accessible_partition' \
  -profile slurm
```

2. **Add account information:**
```bash
nextflow run main.nf \
  --custom_cluster_options '--account=your_account' \
  -profile slurm
```

### Problem: "Queue limits exceeded"

**Symptoms:**
```
ERROR ~ sbatch: error: QOSMaxSubmitJobPerUserLimit exceeded
```

**Solutions:**

1. **Reduce parallel jobs:**
```bash
nextflow run main.nf \
  --max_forks 5 \
  -profile slurm
```

2. **Add QOS specification:**
```bash
nextflow run main.nf \
  --custom_cluster_options '--qos=normal' \
  -profile slurm
```

## Database and Input Validation

### Problem: "Database not found"

**Symptoms:**
```
ERROR ~ Kraken2 database not found at: /path/to/kraken2_db
```

**Solutions:**

1. **Verify database paths:**
```bash
ls -la /path/to/kraken2_db/
ls -la /path/to/checkv_db/
```

2. **Update database paths:**
```bash
nextflow run main.nf \
  --kraken2_db /correct/path/to/kraken2_db \
  --checkv_db /correct/path/to/checkv_db
```

3. **Disable database validation (not recommended):**
```bash
nextflow run main.nf \
  --validate_databases false
```

### Problem: "Invalid samplesheet format"

**Symptoms:**
```
ERROR ~ Invalid samplesheet format: Missing required column 'sample'
```

**Solutions:**

1. **Check samplesheet format:**
```csv
sample,fastq_1,fastq_2
sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
```

2. **Verify file paths exist:**
```bash
# Check if input files exist
while IFS=, read -r sample fastq1 fastq2; do
    [ -f "$fastq1" ] || echo "Missing: $fastq1"
    [ -f "$fastq2" ] || echo "Missing: $fastq2"
done < samplesheet.csv
```

### Problem: "Input files not accessible"

**Symptoms:**
```
ERROR ~ Input file not found: /path/to/sample_R1.fastq.gz
```

**Solutions:**

1. **Check file permissions:**
```bash
ls -la /path/to/sample_R1.fastq.gz
```

2. **Use absolute paths:**
```bash
# Convert relative to absolute paths
realpath sample_R1.fastq.gz
```

3. **Verify network mounts:**
```bash
# Check if network storage is mounted
df -h | grep /path/to/data
```

## Performance Issues

### Problem: "Pipeline running slowly"

**Symptoms:** Pipeline takes much longer than expected.

**Solutions:**

1. **Enable performance optimization:**
```bash
nextflow run main.nf \
  --enable_performance_optimization true \
  --scaling_strategy aggressive \
  -profile slurm
```

2. **Increase parallelization:**
```bash
nextflow run main.nf \
  --max_forks 20 \
  --max_parallel_samples 10 \
  -profile slurm
```

3. **Use faster tools:**
```bash
nextflow run main.nf \
  --blastx_tool diamond \
  --assembler megahit \
  -profile slurm
```

### Problem: "High memory usage"

**Solutions:**

1. **Use memory-efficient settings:**
```bash
nextflow run main.nf \
  --scaling_strategy conservative \
  --max_forks 5 \
  -profile slurm
```

2. **Enable memory monitoring:**
```bash
nextflow run main.nf \
  --enable_performance_monitoring true \
  --performance_profiling_level detailed \
  -profile slurm
```

## Container and Singularity Issues

### Problem: "Singularity image not found"

**Symptoms:**
```
ERROR ~ Singularity image not found: docker://metanextviro:latest
```

**Solutions:**

1. **Build Singularity image manually:**
```bash
singularity build metanextviro.sif docker://metanextviro:latest
```

2. **Use local Docker image:**
```bash
# Build Docker image first
docker build -t metanextviro:latest .

# Then run with Singularity
nextflow run main.nf -profile singularity
```

### Problem: "Container permission issues"

**Symptoms:**
```
ERROR ~ Permission denied when accessing files in container
```

**Solutions:**

1. **Fix Docker permissions:**
```bash
nextflow run main.nf \
  -profile docker \
  --docker_runOptions '-u $(id -u):$(id -g)'
```

2. **Use Singularity instead:**
```bash
nextflow run main.nf -profile singularity
```

## Common Error Messages

### Exit Status Codes

| Exit Code | Meaning | Solution |
|-----------|---------|----------|
| 1 | General error | Check process logs for specific error |
| 2 | Misuse of shell command | Verify command syntax |
| 124 | Time limit exceeded | Increase time limit or use faster partition |
| 125 | Container error | Check container configuration |
| 126 | Command not executable | Check file permissions |
| 127 | Command not found | Verify tool installation |
| 130 | Process terminated by Ctrl+C | User interruption |
| 137 | Out of memory (SIGKILL) | Increase memory allocation |
| 139 | Segmentation fault | Check input data integrity |
| 143 | Process terminated (SIGTERM) | Usually resource limits |

### Debugging Commands

```bash
# Check Nextflow log
cat .nextflow.log

# Check process work directory
ls -la work/*/

# Check SLURM job logs
squeue -u $USER
sacct -j <job_id> --format=JobID,JobName,State,ExitCode

# Monitor resource usage
sstat -j <job_id> --format=JobID,MaxRSS,MaxVMSize

# Check container logs
docker logs <container_id>
```

### Getting Help

1. **Check pipeline logs:**
```bash
tail -f .nextflow.log
```

2. **Enable debug mode:**
```bash
nextflow run main.nf -profile slurm --debug
```

3. **Validate configuration:**
```bash
nextflow run main.nf \
  --validate_resources true \
  --strict_validation true \
  -profile slurm
```

4. **Test with minimal dataset:**
```bash
# Create small test dataset
head -2 samplesheet.csv > test_samplesheet.csv
nextflow run main.nf --input test_samplesheet.csv -profile local
```

## Prevention Tips

1. **Always validate inputs before running:**
```bash
# Check samplesheet format
head samplesheet.csv

# Verify file existence
cat samplesheet.csv | cut -d, -f2,3 | tail -n +2 | tr ',' '\n' | xargs ls -la
```

2. **Start with conservative settings:**
```bash
nextflow run main.nf \
  --max_forks 5 \
  --max_retry_scaling 2 \
  --scaling_strategy conservative \
  -profile slurm
```

3. **Use appropriate profiles:**
- Local testing: `-profile local`
- HPC with modules: `-profile slurm`
- Containerized: `-profile singularity`
- Development: `-profile conda`

4. **Monitor resource usage:**
```bash
# Enable monitoring
nextflow run main.nf \
  --enable_performance_monitoring true \
  -profile slurm
```