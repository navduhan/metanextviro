# MetaNextViro: High-Throughput Virus Identification and Metagenomic Analysis Pipeline

<p align="center">
  <img src="logo.png" alt="MetaNextViro Logo" width="180"/>
</p>

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/navduhan/metanextviro)](https://github.com/navduhan/metanextviro/releases)
[![GitHub license](https://img.shields.io/github/license/navduhan/metanextviro)](https://github.com/navduhan/metanextviro/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/navduhan/metanextviro)](https://github.com/navduhan/metanextviro/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/navduhan/metanextviro)](https://github.com/navduhan/metanextviro/network)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A5%2021.10.3-brightgreen.svg)](https://www.nextflow.io/)
[![Docker](https://img.shields.io/badge/docker-available-blue.svg)](https://www.docker.com/)
[![Singularity](https://img.shields.io/badge/singularity-available-orange.svg)](https://sylabs.io/singularity/)

<p align="center">
  metagenomics • virology • bioinformatics • nextflow • virus-discovery • metagenomic-assembly • taxonomic-classification • viral-analysis • coverage-analysis • checkv • virfinder • kraken2 • blast • docker • singularity • hpc • slurm
</p>

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Features](#features)
- [Key Improvements](#key-improvements)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the Pipeline](#running-the-pipeline)
- [Pipeline Steps](#pipeline-steps)
- [Output Structure](#output-structure)
- [Key Output Files](#key-output-files)
- [Configuration](#configuration)
- [Resource Requirements](#resource-requirements)
- [Docker & Singularity Support](#docker--singularity-support)
- [Recent Updates](#recent-updates)
- [Citations](#citations)
- [Support](#support)
- [License](#license)
- [Authors](#authors)

## Overview

MetaNextViro is a robust, modular Nextflow pipeline designed primarily for **virus identification and characterization** from metagenomic sequencing data. While it also supports bacterial profiling, its main focus is on the detection, classification, and annotation of viral sequences in complex samples such as environmental, clinical, or animal/human microbiome datasets.

The pipeline integrates state-of-the-art tools for:
- **Quality control and preprocessing** of raw reads (FastQC, fastp, flexbar, trim_galore, MultiQC)
- **Assembly** of metagenomic data (MEGAHIT, metaSPAdes, or hybrid)
- **Taxonomic classification** with Kraken2 and visualization with Krona
- **Viral genome completion and quality assessment** (CheckV)
- **Viral sequence identification** (VirFinder with custom filtering)
- **BLAST-based annotation** for both viral and bacterial contigs
- **Automated organization of contigs** by taxonomy and family
- **Contig-level coverage analysis and visualization** for assembled contigs
- **Comprehensive reporting** with MultiQC, coverage plots, and an interactive HTML summary

MetaNextViro is suitable for:
- Discovery of known and novel viruses in metagenomic samples
- Viral diversity and abundance profiling
- Viral genome recovery and annotation
- Comparative virome analysis across samples or conditions
- Integrated viral and bacterial community profiling (optional)

The pipeline is highly portable and reproducible, supporting Conda, Docker, and Singularity environments, and can be run on local workstations, HPC clusters (SLURM), or in the cloud. It is ideal for virome research, outbreak investigations, environmental surveillance, and any project requiring robust viral metagenomics.

## Quick Start

### Prerequisites
- Nextflow (>=21.10.3)
- Java (>=8)
- Conda, Docker, or Singularity

### Basic Usage
```bash
# Clone the repository
git clone https://github.com/navduhan/metanextviro.git
cd metanextviro

# Run with conda (recommended for first-time users)
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /path/to/kraken2_db \
  --checkv_db /path/to/checkv_db \
  -profile conda

# Run with singularity (recommended for HPC)
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /path/to/kraken2_db \
  --checkv_db /path/to/checkv_db \
  -profile singularity
```

### Sample Input Format
Create a `samplesheet.csv` file:
```csv
sample,fastq_1,fastq_2
sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
```

## Features

- Quality control and adapter/quality trimming (FastQC, fastp, flexbar, trim_galore, MultiQC)
- Multiple assembly options (MEGAHIT, metaSPAdes, or hybrid)
- BLAST-based and Kraken2-based taxonomic annotation
- Automated organization of contigs by taxonomy and family
- Viral genome completion (CheckV) and classification (VirFinder with custom filtering)
- **Contig-level coverage analysis** and visualization
- Comparative heatmap visualization
- **Comprehensive HTML report** generated after all processes complete
- Structured, per-sample output organization

## Key Improvements

### Enhanced VirFinder Analysis
- **Custom R script** (`run_virfinder.R`) for improved control over filtering criteria
- **Dual output format**: Full results and high-confidence filtered results (score ≥ 0.9, p-value ≤ 0.05)
- **Better integration** with downstream analysis and reporting

### Improved Coverage Analysis
- **Contig-level coverage calculation** instead of nucleotide-level depth
- **Custom bash script** (`calculate_contig_coverage.sh`) for efficient processing
- **Bar plot visualizations** showing coverage distribution across contigs
- **No additional dependencies** - uses standard tools (samtools, awk)

### Final Report Generation
- **Guaranteed completion order**: HTML report generated only after all analysis steps complete
- **Comprehensive content**: Includes all pipeline outputs in one place
- **Robust error handling**: Graceful handling of missing files
- **Enhanced user experience**: Complete report only when everything is done

## Prerequisites

- Nextflow (>=21.10.3)
- Java (>=8)
- Python (>=3.8)
- Conda (recommended)
- Docker or Singularity (optional, for containerized execution)

### Required Tools and Packages
All dependencies can be installed using the provided `environment.yml` file or automatically with the conda profile.

- FastQC, MultiQC, fastp, flexbar, trim-galore
- MEGAHIT, SPAdes, BLAST+, DIAMOND, Kraken2, QUAST
- Bowtie2, Samtools, Bedtools
- CheckV, VirFinder (R)
- Python: biopython, pandas, matplotlib, seaborn, ete3, pathlib
- R: r-base, r-virfinder

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/navduhan/metanextviro.git
   cd metanextviro
   ```

   Or download the latest release from: [https://github.com/navduhan/metanextviro](https://github.com/navduhan/metanextviro)

2. **Create and activate the conda environment (platform-specific):**

| Platform                | Command to Use                                      |
|-------------------------|-----------------------------------------------------|
| **Linux**               | `conda env create -f environment.yml`               |
| **Intel/AMD Mac**       | `conda env create -f environment.yml`               |
| **Apple Silicon (M1/M2)** | `CONDA_SUBDIR=osx-64 conda env create -f environment.yml` |

- **Linux and Intel/AMD Macs:**
  - You can create the environment with the standard command:
    ```bash
    conda env create -f environment.yml
    conda activate metanextviro
    ```
  - No special variables are needed.

- **Apple Silicon (M1/M2) Macs:**
  - Some bioinformatics tools are not yet available as native ARM64 (osx-arm64) conda packages. To ensure compatibility, you should force conda to use Intel (osx-64) packages:
    ```bash
    CONDA_SUBDIR=osx-64 conda env create -f environment.yml
    conda activate metanextviro
    ```
  - This tells conda to install Intel-compatible binaries, which work via Rosetta 2 on Apple Silicon.

**Why is this needed?**
- Many bioinformatics tools are only available as osx-64 (Intel) binaries.
- On Linux, all packages are natively supported, so no workaround is needed.
- On Intel Macs, you also do not need this workaround.

Or let Nextflow manage it automatically with `-profile conda`.

## Conda Environment

For platform-specific conda environment setup instructions, see the Installation section above.

## Running the Pipeline

### With Conda (Recommended, Nextflow-managed)
Nextflow can automatically manage all dependencies using the conda profile:
```bash
nextflow run main.nf --input samplesheet.csv --outdir results -profile conda
```
This will create and use the environment defined in `environment.yml` for each process.

### With a Manually Activated Conda Environment
If you prefer to manage the environment yourself, you can create and activate the conda environment, then run the pipeline with the `local` or `slurm` profile:
```bash
conda env create -f environment.yml
conda activate metanextviro
nextflow run main.nf --input samplesheet.csv --outdir results -profile local
# or
nextflow run main.nf --input samplesheet.csv --outdir results -profile slurm
```
This approach gives you full control over the environment and is especially useful on clusters where you want to use a single environment for all jobs.

### With Docker (Recommended for Portability)
You can use a Docker container for full reproducibility. You can use the provided Dockerfile or build your own image:

1. **Build the Docker image:**
   ```bash
   docker build -t metanextviro:latest .
   ```

2. **Run the pipeline with Docker (Nextflow-managed):**
   ```bash
   nextflow run main.nf --input samplesheet.csv --outdir results -profile docker
   ```
   This will use the Docker image for all processes.

3. **Run the pipeline with Docker and local/slurm profiles:**
   If you want to submit jobs on SLURM or run locally but still use Docker, activate Docker and use the appropriate profile:
   ```bash
   export NXF_DOCKER_ENABLE=true
   export NXF_DOCKER_IMAGE=metanextviro:latest
   nextflow run main.nf --input samplesheet.csv --outdir results -profile local
   # or
   nextflow run main.nf --input samplesheet.csv --outdir results -profile slurm
   ```
   This will use your custom Docker image for all jobs, whether run locally or on SLURM.

> **Note:** You can customize the container image in `nextflow.config` or by setting the `NXF_DOCKER_IMAGE` environment variable.

### With Singularity (Recommended for HPC)
If your HPC cluster supports Singularity (most do), you can use the singularity profile. Nextflow will automatically convert your Docker image to a Singularity image on the fly:

```bash
nextflow run main.nf --input samplesheet.csv --outdir results -profile singularity
```

Or, to use Singularity with SLURM:
```bash
nextflow run main.nf --input samplesheet.csv --outdir results -profile slurm,singularity
```

This is the most portable and secure way to run on HPC clusters. You do **not** need to manually build a Singularity image; Nextflow will handle it for you using the Docker image as the base.

### With Local or SLURM Profiles (Native)
You can also use the pipeline with your local environment or on a cluster:
```bash
nextflow run main.nf --input samplesheet.csv --outdir results -profile local
# or
nextflow run main.nf --input samplesheet.csv --outdir results -profile slurm
```

### Input Format
The pipeline requires a samplesheet CSV file with the following format:
```csv
sample,fastq_1,fastq_2
sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
```

### Parameters
All parameters can be set on the command line or in `nextflow.config`.

| Parameter           | Description                                                        | Default         |
|---------------------|--------------------------------------------------------------------|-----------------|
| --input             | Path to input samplesheet (CSV)                                    | (required)      |
| --outdir            | Output directory                                                   | ./results       |
| --adapters          | Path to adapters file (for trimming)                              | (optional)      |
| --trimming_tool     | Trimming tool: fastp, flexbar, trim_galore                        | fastp           |
| --assembler         | Assembler: megahit, metaspades, hybrid                            | hybrid          |
| --kraken2_db        | Path to Kraken2 database                                           | (required)      |
| --blastdb_viruses   | Path to BLAST viruses database                                    | (optional)      |
| --blastdb_nt        | Path to BLAST nt database                                         | (optional)      |
| --blastdb_nr        | Path to BLAST nr database                                         | (optional)      |
| --diamonddb         | Path to DIAMOND protein database                                  | (optional)      |
| --checkv_db         | Path to CheckV database (for viral genome completion)             | (required)      |
| --min_contig_length | Minimum contig length for assembly                                | 200             |
| --quality           | Quality threshold for trimming                                    | 30              |
| --profile           | Nextflow profile (local, slurm, conda, docker, singularity, etc.) | slurm           |
| --help              | Show help message and exit                                        |                 |

### Example
```bash
nextflow run main.nf \
  --input samplesheet.csv \
  --outdir results \
  --trimming_tool fastp \
  --assembler hybrid \
  --kraken2_db /path/to/kraken2_db \
  --checkv_db /path/to/checkv_db \
  -profile singularity
```

## Pipeline Steps

1. **Input Parsing**
   - Validates input files and sample sheet
2. **Preprocessing**
   - FastQC on raw reads
   - Adapter/quality trimming (fastp, flexbar, or trim_galore)
   - FastQC on trimmed reads
   - MultiQC aggregation
3. **Taxonomic Profiling**
   - Kraken2 classification
   - Krona visualization
4. **Assembly**
   - MEGAHIT, metaSPAdes, or hybrid assembly
   - QUAST quality assessment
5. **BLAST Annotation**
   - Taxonomic annotation of contigs against multiple databases (NT, NR, viruses)
   - **Contig organization uses comprehensive NT database results to avoid viral bias**
6. **Viral Analysis**
   - CheckV genome completion
   - **VirFinder classification with custom filtering** (full and high-confidence results)
7. **Contig Organization**
   - Organize contigs by taxonomy and family using NT database results
   - **Unbiased classification using comprehensive nucleotide database**
8. **Coverage Analysis**
   - **Contig-level coverage calculation** and statistics
   - **Enhanced coverage plots with intelligent x-axis labeling** (adapts to contig count)
   - **Statistics box** with summary metrics
   - **Mean coverage line** for reference
   - **Sorted by coverage** for better visualization
   - **Coverage distribution histograms** for datasets with >100 contigs
9. **Final Report Generation**
   - **Comprehensive HTML report** generated after all processes complete
   - Includes all pipeline outputs in one place

## Output Structure

```
results/
├── fastp/                # Trimmed reads and fastp reports
├── fastqc/               # Raw and trimmed read QC reports
├── multiqc/              # MultiQC summary report
├── assembly/             # Assembly results
│   └── quast/            # Assembly quality reports
├── blast_results/        # BLAST annotation results
├── kraken2_results/      # Kraken2 classification results
├── krona_results/        # Krona HTML visualizations
├── organized_contigs/    # Organized contigs by taxonomy
├── checkv/               # CheckV viral genome completion
├── virfinder/            # VirFinder results (full and filtered)
├── coverage/             # BAM files and contig-level coverage stats
├── coverage_plots/       # Coverage plots (PNG)
├── heatmaps/             # Comparative heatmaps
├── final_report/         # Comprehensive HTML report (final step)
└── ...                   # Other outputs as configured
```

## Key Output Files

### VirFinder Results
- `virfinder_full_*.txt`: Complete VirFinder results for all contigs
- `virfinder_filtered_*.txt`: High-confidence viral contigs (score ≥ 0.9, p-value ≤ 0.05)

### Coverage Analysis
- `coverage_*.txt`: Contig-level coverage statistics with columns:
  - Contig: Contig identifier
  - Length: Contig length in bp
  - Average_Coverage: Mean coverage across the contig
  - Total_Reads: Number of mapped reads
- `coverage_plot_*.png`: Enhanced coverage plots with:
  - **Intelligent x-axis labeling** (adapts to contig count)
  - **Statistics box** with summary metrics
  - **Mean coverage line** for reference
  - **Sorted by coverage** for better visualization
- `coverage_distribution_*.png`: Coverage distribution histograms (for >100 contigs)

### Final Report
- `final_report.html`: Comprehensive HTML report generated after all processes complete
  - Includes all pipeline outputs
  - Links to all result files
  - Generated only when all analyses are finished

## Configuration

- `nextflow.config`: Main configuration file (edit to set default parameters, resources, and profiles)
- `environment.yml`: Conda environment for all dependencies
- `Dockerfile`: (Optional) Build your own container for full reproducibility
- `nextflow/bin/`: Custom scripts for enhanced functionality
  - `run_virfinder.R`: Custom VirFinder analysis with filtering
  - `calculate_contig_coverage.sh`: Contig-level coverage calculation

## Resource Requirements

- Small tasks: 4GB RAM, 2 CPUs
- Medium tasks: 8GB RAM, 4 CPUs
- Large tasks: 16GB RAM, 8 CPUs
- High-memory tasks: 32GB RAM, 8 CPUs

## Docker & Singularity Support

- **Docker:** Use the provided Dockerfile to build an image for full reproducibility. Works with local, slurm, or docker profiles.
- **Singularity:** On HPC, use the singularity profile. Nextflow will automatically convert your Docker image to a Singularity image on the fly. No need to manually build a Singularity image.

### Example (HPC with SLURM and Singularity)
```bash
nextflow run main.nf --input samplesheet.csv --outdir results -profile slurm,singularity
```

## Recent Updates

### Version 1.0 (Latest Release)
- **Enhanced VirFinder Analysis**: Custom R script with dual output format (full and filtered results)
- **Improved Coverage Analysis**: Contig-level coverage calculation instead of nucleotide-level depth
- **Final Report Generation**: Guaranteed completion order with comprehensive HTML report
- **Better Error Handling**: Robust handling of missing files and edge cases
- **Performance Improvements**: More efficient processing and reduced dependencies
- **Comprehensive Documentation**: Complete README with citations, badges, and usage examples

## Citations

If you use this pipeline, please cite:

- **MetaNextViro Pipeline**: [https://github.com/navduhan/metanextviro](https://github.com/navduhan/metanextviro)
- **Nextflow**: Di Tommaso, P., Chatzou, M., Floden, E. W., Barja, P. P., Palumbo, E., & Notredame, C. (2017). Nextflow enables reproducible computational workflows. Nature Biotechnology, 35(4), 316-319. [https://doi.org/10.1038/nbt.3820](https://doi.org/10.1038/nbt.3820)
- **FastQC**: Andrews, S. (2010). FastQC: a quality control tool for high throughput sequence data. [https://www.bioinformatics.babraham.ac.uk/projects/fastqc/](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
- **MEGAHIT**: Li, D., Liu, C. M., Luo, R., Sadakane, K., & Lam, T. W. (2015). MEGAHIT: an ultra-fast single-node solution for large and complex metagenomics assembly via succinct de Bruijn graph. Bioinformatics, 31(10), 1674-1676. [https://doi.org/10.1093/bioinformatics/btv033](https://doi.org/10.1093/bioinformatics/btv033)
- **SPAdes**: Bankevich, A., Nurk, S., Antipov, D., Gurevich, A. A., Dvorkin, M., Kulikov, A. S., ... & Pevzner, P. A. (2012). SPAdes: a new genome assembly algorithm and its applications to single-cell sequencing. Journal of Computational Biology, 19(5), 455-477. [https://doi.org/10.1089/cmb.2012.0021](https://doi.org/10.1089/cmb.2012.0021)
- **Kraken2**: Wood, D. E., Lu, J., & Langmead, B. (2019). Improved metagenomic analysis with Kraken 2. Genome Biology, 20(1), 1-13. [https://doi.org/10.1186/s13059-019-1891-0](https://doi.org/10.1186/s13059-019-1891-0)
- **CheckV**: Nayfach, S., Camargo, A. P., Schulz, F., Eloe-Fadrosh, E., Roux, S., & Kyrpides, N. C. (2021). CheckV assesses the quality and completeness of metagenome-assembled viral genomes. Nature Biotechnology, 39(5), 578-585. [https://doi.org/10.1038/s41587-020-00774-7](https://doi.org/10.1038/s41587-020-00774-7)
- **VirFinder**: Ren, J., Ahlgren, N. A., Lu, Y. Y., Fuhrman, J. A., & Sun, F. (2017). VirFinder: a novel k-mer based tool for identifying viral sequences from assembled metagenomic data. Microbiome, 5(1), 1-20. [https://doi.org/10.1186/s40168-017-0283-5](https://doi.org/10.1186/s40168-017-0283-5)
- **BLAST**: Altschul, S. F., Gish, W., Miller, W., Myers, E. W., & Lipman, D. J. (1990). Basic local alignment search tool. Journal of Molecular Biology, 215(3), 403-410. [https://doi.org/10.1016/S0022-2836(05)80360-2](https://doi.org/10.1016/S0022-2836(05)80360-2)
- **Bowtie2**: Langmead, B., & Salzberg, S. L. (2012). Fast gapped-read alignment with Bowtie 2. Nature Methods, 9(4), 357-359. [https://doi.org/10.1038/nmeth.1923](https://doi.org/10.1038/nmeth.1923)
- **Samtools**: Li, H., Handsaker, B., Wysoker, A., Fennell, T., Ruan, J., Homer, N., ... & Durbin, R. (2009). The Sequence Alignment/Map format and SAMtools. Bioinformatics, 25(16), 2078-2079. [https://doi.org/10.1093/bioinformatics/btp352](https://doi.org/10.1093/bioinformatics/btp352)
- **MultiQC**: Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics, 32(19), 3047-3048. [https://doi.org/10.1093/bioinformatics/btw354](https://doi.org/10.1093/bioinformatics/btw354)
- **Krona**: Ondov, B. D., Bergman, N. H., & Phillippy, A. M. (2011). Interactive metagenomic visualization in a Web browser. BMC Bioinformatics, 12(1), 1-10. [https://doi.org/10.1186/1471-2105-12-385](https://doi.org/10.1186/1471-2105-12-385)

## Support

For issues, questions, or suggestions:
- Create an issue on GitHub
- Contact: naveen.duhan@outlook.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

For more information about the MIT License, visit: https://opensource.org/licenses/MIT

## Authors

- Naveen Duhan
- [Other contributors]
