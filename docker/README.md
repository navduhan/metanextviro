# MetaNextViro Container Documentation

This directory contains Docker configurations and scripts for containerized execution of the MetaNextViro pipeline.

## Overview

The MetaNextViro container supports two environment modes:
- **Unified Mode**: All tools in a single conda environment (default)
- **Per-Process Mode**: Separate conda environments for different pipeline components

## Quick Start

### Building the Container

```bash
# Build with default tag (latest)
./docker/build.sh

# Build with custom tag
./docker/build.sh v2.0.0
```

### Running the Container

```bash
# Run with unified environment (default)
docker run -it --rm metanextviro:latest

# Run with per-process environments
docker run -it --rm -e METANEXTVIRO_ENV_MODE=per_process metanextviro:latest

# Run with data volumes
docker run -it --rm \
  -v /path/to/data:/data \
  -v /path/to/results:/results \
  metanextviro:latest
```

### Using Docker Compose

```bash
# Start unified environment service
docker-compose -f docker/docker-compose.yml up -d metanextviro-unified

# Start development environment
docker-compose -f docker/docker-compose.yml up -d metanextviro-dev

# Start Jupyter notebook service
docker-compose -f docker/docker-compose.yml up -d metanextviro-jupyter
# Access at http://localhost:8888

# Run tests
docker-compose -f docker/docker-compose.yml run --rm metanextviro-test
```

## Container Structure

### Environment Modes

#### Unified Mode (Default)
- Single conda environment: `metanextviro-unified`
- All tools and dependencies in one environment
- Faster startup, simpler management
- Potential for dependency conflicts

#### Per-Process Mode
- Multiple specialized environments:
  - `metanextviro-qc`: Quality control tools
  - `metanextviro-trimming`: Read trimming tools
  - `metanextviro-assembly`: Assembly tools
  - `metanextviro-annotation`: Annotation tools
  - `metanextviro-taxonomy`: Taxonomic classification
  - `metanextviro-alignment`: Alignment tools
  - `metanextviro-viral`: Viral analysis tools

### Directory Structure

```
/workspace/          # Pipeline code and working directory
/data/              # Input data (mount point)
/results/           # Output results (mount point)
/opt/conda/envs/    # Conda environments
/usr/local/bin/     # Container scripts
```

### Container Scripts

- `/usr/local/bin/activate_env.sh`: Environment activation script
- `/usr/local/bin/validate_container.sh`: Container validation and health check

## Environment Variables

- `METANEXTVIRO_ENV_MODE`: Set to `unified` or `per_process`
- `CONDA_DEFAULT_ENV`: Default conda environment to activate

## Volume Mounts

### Recommended Mounts

```bash
docker run -it --rm \
  -v /path/to/input/data:/data:ro \
  -v /path/to/output:/results \
  -v /path/to/databases:/databases:ro \
  -v /path/to/config:/config:ro \
  metanextviro:latest
```

### Volume Descriptions

- `/data`: Input sequencing data (read-only recommended)
- `/results`: Pipeline output directory
- `/databases`: Reference databases (read-only recommended)
- `/config`: Custom configuration files (read-only recommended)

## Running the Pipeline

### Basic Pipeline Execution

```bash
# Run with sample data
docker run --rm \
  -v $(pwd)/examples:/data \
  -v $(pwd)/results:/results \
  metanextviro:latest \
  nextflow run main.nf \
    --input /data/samplesheets/valid_samplesheet.csv \
    --outdir /results \
    --profile docker
```

### Advanced Configuration

```bash
# Run with custom configuration
docker run --rm \
  -v $(pwd)/data:/data \
  -v $(pwd)/results:/results \
  -v $(pwd)/custom.config:/config/custom.config \
  metanextviro:latest \
  nextflow run main.nf \
    --input /data/samplesheet.csv \
    --outdir /results \
    --profile docker \
    -c /config/custom.config
```

## Testing and Validation

### Container Validation

```bash
# Run full validation
docker run --rm metanextviro:latest /usr/local/bin/validate_container.sh

# Run health check only
docker run --rm metanextviro:latest /usr/local/bin/validate_container.sh --health-check
```

### Comprehensive Testing

```bash
# Run all container tests
./docker/test_container.sh

# Test specific container tag
./docker/test_container.sh v2.0.0
```

### Test Categories

1. **Startup Tests**: Basic container functionality
2. **Environment Tests**: Conda environment management
3. **Tool Tests**: Availability of bioinformatics tools
4. **Package Tests**: Python and R package imports
5. **Resource Tests**: Memory and CPU usage
6. **Permission Tests**: File system access

## Troubleshooting

### Common Issues

#### Container Build Failures

```bash
# Check Docker daemon
docker info

# Clean build cache
docker builder prune

# Build with no cache
docker build --no-cache -t metanextviro:latest .
```

#### Environment Activation Issues

```bash
# Check available environments
docker run --rm metanextviro:latest conda env list

# Test environment activation
docker run --rm metanextviro:latest /usr/local/bin/activate_env.sh

# Check specific environment
docker run --rm metanextviro:latest conda activate metanextviro-unified
```

#### Tool Not Found Errors

```bash
# Check tool installation
docker run --rm metanextviro:latest bash -c "source activate metanextviro-unified && which fastqc"

# List installed packages
docker run --rm metanextviro:latest bash -c "source activate metanextviro-unified && conda list"
```

#### Memory Issues

```bash
# Run with increased memory
docker run --rm --memory=8g metanextviro:latest

# Check memory usage
docker run --rm metanextviro:latest free -h
```

### Performance Optimization

#### Resource Allocation

```bash
# Allocate specific resources
docker run --rm \
  --cpus=4 \
  --memory=8g \
  --shm-size=2g \
  metanextviro:latest
```

#### Volume Performance

```bash
# Use tmpfs for temporary files
docker run --rm \
  --tmpfs /tmp:rw,noexec,nosuid,size=2g \
  metanextviro:latest
```

## Development

### Building Development Images

```bash
# Build development image with latest changes
docker build -t metanextviro:dev .

# Build with build arguments
docker build \
  --build-arg PYTHON_VERSION=3.9 \
  --build-arg CONDA_VERSION=4.12.0 \
  -t metanextviro:dev .
```

### Interactive Development

```bash
# Start development container
docker-compose -f docker/docker-compose.yml up -d metanextviro-dev

# Attach to running container
docker exec -it metanextviro-dev bash

# Or start new interactive session
docker run -it --rm \
  -v $(pwd):/workspace \
  metanextviro:dev bash
```

### Testing Changes

```bash
# Test container after changes
./docker/test_container.sh dev

# Run specific test suites
docker run --rm metanextviro:dev /usr/local/bin/validate_container.sh
```

## Security Considerations

### User Permissions

The container runs as root by default. For production use, consider:

```bash
# Run as specific user
docker run --rm --user $(id -u):$(id -g) metanextviro:latest

# Create non-root user in container
# (Add to Dockerfile)
RUN useradd -m -s /bin/bash metanextviro
USER metanextviro
```

### Network Security

```bash
# Run without network access
docker run --rm --network none metanextviro:latest

# Run with restricted network
docker run --rm --network bridge metanextviro:latest
```

### File System Security

```bash
# Mount volumes as read-only where appropriate
docker run --rm \
  -v /path/to/data:/data:ro \
  -v /path/to/databases:/databases:ro \
  metanextviro:latest
```

## Support and Maintenance

### Container Updates

```bash
# Pull latest base image
docker pull continuumio/miniconda3:4.12.0

# Rebuild container
./docker/build.sh

# Update environments
docker run --rm metanextviro:latest conda update --all
```

### Monitoring

```bash
# Monitor container resources
docker stats metanextviro-container

# Check container logs
docker logs metanextviro-container

# Inspect container configuration
docker inspect metanextviro:latest
```

### Backup and Recovery

```bash
# Export container image
docker save metanextviro:latest | gzip > metanextviro-latest.tar.gz

# Import container image
gunzip -c metanextviro-latest.tar.gz | docker load

# Backup volumes
docker run --rm \
  -v metanextviro-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/data-backup.tar.gz /data
```

## Integration with HPC Systems

### Singularity Conversion

```bash
# Convert Docker image to Singularity
singularity build metanextviro.sif docker://metanextviro:latest

# Run with Singularity
singularity exec metanextviro.sif nextflow run main.nf
```

### SLURM Integration

```bash
# Submit container job to SLURM
sbatch --wrap="singularity exec metanextviro.sif nextflow run main.nf --profile slurm"
```

For more information, see the main pipeline documentation and the Nextflow configuration files.