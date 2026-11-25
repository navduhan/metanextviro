# Quick Start and End-to-End Walkthrough

This guide walks through installing the Nextflow launcher, pulling MetaNextViro from GitHub, generating a samplesheet from raw FASTQ files, provisioning reference databases, running routine viral surveillance, and running divergent virus discovery.

---

## 1. Prerequisites

MetaNextViro requires:

- **Nextflow** `>= 22.10.0` (tested through Nextflow `26.10.x` strict parser v2)
- **Java** `17` to `26` (verify with `java -version`)
- **One software execution backend**:
  - **Conda or Mamba** (recommended on workstations and SLURM clusters without container runtimes)
  - **Docker** (recommended on Linux/macOS workstations and CI)
  - **Singularity or Apptainer** (recommended on HPC clusters)

### Option A: Create the Lightweight Conda Launcher (Recommended if Nextflow is Missing)

Top-level `environment.yml` installs only Nextflow, OpenJDK 21, Python 3.11, and pip (~15 seconds). Bioinformatics tools live in isolated tiered environments under `envs/` and are built automatically by Nextflow on demand.

```bash
conda create -n metanextviro -c conda-forge -c bioconda nextflow openjdk=21 python=3.11 pip
conda activate metanextviro
nextflow -version
```

### Option B: Use Existing HPC Modules

If your HPC cluster provides Nextflow and Singularity/Apptainer modules, skip Conda creation:

```bash
module load nextflow singularity
nextflow -version
```

---

## 2. Pull MetaNextViro Once (Enables Short `nextflow run metanextviro`)

Running `nextflow pull` once caches the repository in `~/.nextflow/assets/navduhan/metanextviro`. Every subsequent command on that machine can run with the short name `metanextviro` from any directory:

```bash
nextflow pull navduhan/metanextviro

# Check available options and defaults
nextflow run metanextviro --help
```

To update to the latest commit later, re-run `nextflow pull navduhan/metanextviro`, or pin a specific release tag with `-r v1.0.0` for reproducible publications.

### Optional `pip` CLI Wrapper

If you prefer typing `metanextviro ...` instead of `nextflow run metanextviro ...`, install the thin Python launcher:

```bash
pip install git+https://github.com/navduhan/metanextviro.git
metanextviro --version
metanextviro pull
```

---

## 3. Prepare Your Samplesheet

MetaNextViro accepts CSV, TSV, XLS, and XLSX samplesheets using either `sample,fastq_1,fastq_2` or `id,reads1,reads2` column headers.

### Automatic Generation From a FASTQ Directory

`--create_samplesheet` runs `bin/create_samplesheet.py` using Python stdlib only (no Conda environment or database download needed) and finishes in under one second:

```bash
nextflow run metanextviro \
  --create_samplesheet \
  --reads_dir ./raw_fastqs \
  --samplesheet samplesheet.csv
```

Supported paired-end filename patterns:

| Sequencing Source | Example R1 / R2 Filenames | Extracted Sample ID |
| :--- | :--- | :--- |
| Illumina BCLConvert / Casava | `Avian01_S1_L001_R1_001.fastq.gz` / `Avian01_S1_L001_R2_001.fastq.gz` | `Avian01` |
| Multi-lane Illumina | `FlockA_S2_L001_R1_001.fastq.gz` and `FlockA_S2_L002_R1_001.fastq.gz` | `FlockA_L001`, `FlockA_L002` |
| Standard `_R1` / `_R2` | `Swine02_R1.fq.gz` / `Swine02_R2.fq.gz` | `Swine02` |
| SRA / ENA `_1` / `_2` | `SRR1987654_1.fastq.gz` / `SRR1987654_2.fastq.gz` | `SRR1987654` |

Add `--recursive_reads` if sample FASTQs sit inside nested subdirectories. If any sample is missing R1 or R2, the script exits immediately and names the incomplete sample.

### Manual Samplesheet Example

```csv
sample,fastq_1,fastq_2
Avian_Tracheal_01,/data/virome/Avian_Tracheal_01_R1.fastq.gz,/data/virome/Avian_Tracheal_01_R2.fastq.gz
Swine_Nasal_02,/data/virome/Swine_Nasal_02_R1.fastq.gz,/data/virome/Swine_Nasal_02_R2.fastq.gz
```

---

## 4. Download and Index Reference Databases (One-Time Setup)

MetaNextViro defaults to the **`full_viral`** preset (~4.0 GB compressed download), which builds ETE3 NCBI taxonomy SQLite, RefSeq viral nucleotide BLASTN, RefSeq viral protein DIAMOND, VOGDB hallmark HMMs + LCA table, Kraken2 viral index, CheckV v1.5, and geNomad v1.9 inside `--db_dir`:

```bash
nextflow run metanextviro \
  --setup_databases \
  --db_dir ~/.metanextviro/dbs \
  -profile conda
```

Under `-profile conda`, Nextflow creates only the lightweight `envs/setup_db.yml` environment (cached in `~/.metanextviro/conda_envs`) and executes database setup locally on the submission node even when combined with `-profile slurm,conda`. See [`docs/databases.md`](databases.md) for lighter (`minimal`, `discovery_only`) and full GenBank (`genbank_complete`) presets.

---

## 5. Run Analysis

### Scenario A: Fast Routine Viral Surveillance (Default)

Runs FastQC, Trim Galore (`Q >= 30`), MEGAHIT de novo assembly, QUAST, Kraken2 + Krona, multi-HSP viral BLASTN (`50` subjects, all HSPs), single-pass whole-contig Bowtie2 + SAMtools coverage, and cohort plus per-sample PDF and HTML reports.

```bash
# Using a samplesheet:
nextflow run metanextviro \
  --input samplesheet.csv \
  --outdir results_surveillance \
  -profile conda

# Or directly from a directory of paired FASTQs (auto-writes results_surveillance/samplesheet.csv):
nextflow run metanextviro \
  --reads_dir ./raw_fastqs \
  --outdir results_surveillance \
  -profile conda
```

### Scenario B: Host-Depleted Divergent Virus Discovery + Phylogeny

Adds Bowtie2 host read depletion, automated post-BLAST triage (skipping known viral and cellular contigs), 6-frame ORF/DTR/entropy/EVE scanning, VOGDB HMMs, DIAMOND viral protein BLASTP, CheckV, geNomad, FDR-controlled VirFinder with putative Order/Family taxonomy, and MAFFT + FastTree RdRp trees:

```bash
nextflow run metanextviro \
  --input samplesheet.csv \
  --outdir results_discovery \
  --deplete_host --host_fasta host_genome.fa \
  --discover_novel_viruses \
  --run_virfinder \
  --run_checkv \
  --run_genomad \
  --run_viral_hmm \
  --run_viral_protein_blast \
  --run_novel_phylogeny \
  --organize_contigs \
  -profile conda
```

### Scenario C: Reproducible Runs With `-params-file` and `-resume`

Store parameters in a version-controlled YAML file (`params.yml`) instead of long command lines:

```yaml
# params.yml
input: samplesheet.csv
outdir: results_cohort_2026
db_dir: /scratch/user/metanextviro_dbs
conda_cache_dir: /scratch/user/metanextviro_envs
deplete_host: true
host_fasta: /scratch/user/refs/gallus_gallus.fa
assembler: megahit
blast_options: viruses
discover_novel_viruses: true
run_virfinder: true
run_checkv: true
run_genomad: true
organize_contigs: true
```

```bash
nextflow run metanextviro -params-file params.yml -profile slurm,mamba --account my_lab -resume
```

---

## 6. Inspect Results and Clean Up `work/`

1. Open `results/final_report/MetaNextViro_Summary_Report.html` (or `.pdf`) for cohort metrics and click into `results/final_report/per_sample/<sample>_Viral_Report.html` (or `.pdf`).
2. Inspect `results/blast_results/<sample>_best_hits_viruses.xlsx` and (when discovery is enabled) `results/novel_virus_detection/<sample>_novel_virus_candidates.xlsx` and `results/virfinder/virfinder_<sample>_taxonomy.xlsx`.
3. Once outputs are verified and `-resume` is no longer needed, recover scratch space safely using `bin/cleanup_work.py` (see [`docs/output.md`](output.md)).
