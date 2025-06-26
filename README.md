# MetaNextViro: High-Throughput Virus Identification and Metagenomic Analysis Pipeline

<p align="center">
  <img src="logo.png" alt="MetaNextViro Logo" width="180"/>
</p>

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
   git clone https://github.com/yourusername/metanextviro.git
   cd metanextviro
   ```

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
   - Taxonomic annotation of contigs
6. **Viral Analysis**
   - CheckV genome completion
   - **VirFinder classification with custom filtering** (full and high-confidence results)
7. **Contig Organization**
   - Organize contigs by taxonomy and family
8. **Coverage Analysis**
   - **Contig-level coverage calculation** and statistics
   - Coverage plot generation
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

### Version 2.0 (Latest)
- **Enhanced VirFinder Analysis**: Custom R script with dual output format (full and filtered results)
- **Improved Coverage Analysis**: Contig-level coverage calculation instead of nucleotide-level depth
- **Final Report Generation**: Guaranteed completion order with comprehensive HTML report
- **Better Error Handling**: Robust handling of missing files and edge cases
- **Performance Improvements**: More efficient processing and reduced dependencies

## Citations

If you use this pipeline, please cite:
- [Your paper/preprint]
- [Tools used in the pipeline]

## Support

For issues, questions, or suggestions:
- Create an issue on GitHub
- Contact: [Your contact information]

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

For more information about the GNU GPL v3.0, visit: https://www.gnu.org/licenses/gpl-3.0.en.html

## Authors

- Naveen Duhan
- [Other contributors]
