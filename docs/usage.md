# Usage, Parameters, and Execution Profiles

## Execution Modes

MetaNextViro runs directly through Nextflow (`nextflow run navduhan/metanextviro`, or `nextflow run metanextviro` after running `nextflow pull navduhan/metanextviro` once).

### 1. Standalone Samplesheet Creation

`--create_samplesheet` scans a directory of paired FASTQ files (`.fastq.gz`, `.fq.gz`, `.fastq`, `.fq`) across Illumina (`_S1_L001_R1_001`), standard (`_R1`/`_R2`), and SRA (`_1`/`_2`) naming patterns and writes a validated CSV file. This mode uses only Python stdlib and does not download Conda environments or reference databases.

```bash
nextflow run metanextviro \
  --create_samplesheet \
  --reads_dir ./raw_fastqs \
  --samplesheet samplesheet.csv
```

Pass `--recursive_reads` to scan subdirectories under `--reads_dir`.

### 2. Direct FASTQ Directory Execution

If you omit `--input` and supply `--reads_dir`, MetaNextViro generates `${outdir}/samplesheet.csv` automatically and starts the full analysis workflow in one command:

```bash
nextflow run metanextviro \
  --reads_dir ./raw_fastqs \
  --outdir results \
  -profile conda
```

### 3. Routine Targeted Surveillance (Default)

By default, MetaNextViro runs FastQC, Trim Galore, MEGAHIT, QUAST, Kraken2 + Krona, viral BLASTN (`--blast_options viruses`), whole-contig Bowtie2 + SAMtools coverage, and cohort plus per-sample PDF/HTML reporting. Heavy discovery modules stay disabled until explicitly enabled.

```bash
nextflow run metanextviro \
  --input samplesheet.csv \
  --outdir results \
  -profile conda
```

### 4. Divergent Virus Discovery & VirFinder

```bash
nextflow run metanextviro \
  --input samplesheet.csv \
  --outdir results \
  --deplete_host --host_fasta host_genome.fa \
  --discover_novel_viruses \
  --run_virfinder \
  --run_checkv \
  --run_genomad \
  --run_viral_hmm \
  --run_viral_protein_blast \
  --run_novel_phylogeny \
  -profile conda
```

---

## Complete Parameter Reference

### Input, Output, and Samplesheet Options

| Parameter | Description | Default |
| :--- | :--- | :--- |
| `--input` | Input samplesheet path (`csv`, `tsv`, `xls`, or `xlsx`) | `null` |
| `--reads_dir` | Directory of paired FASTQ files (alias: `--fastq_dir`) | `null` |
| `--create_samplesheet` | Generate samplesheet CSV from `--reads_dir` and exit | `false` |
| `--samplesheet` | Output CSV path for `--create_samplesheet` | `samplesheet.csv` |
| `--recursive_reads` | Recursively scan subdirectories under `--reads_dir` | `false` |
| `--outdir` | Published output directory | `results` |
| `--publish_mode` | Publishing mode: `copy`, `link`, `symlink`, or `rellink` | `copy` |
| `--conda_cache_dir` | Shared directory for cached tiered Conda/Mamba environments | `~/.metanextviro/conda_envs` |
| `--container_image` | Primary Docker/Singularity image for core/assembly/discovery tasks | `ghcr.io/navduhan/metanextviro:latest` |
| `--max_cores` | Maximum CPU threads allocated per local task | `16` |
| `--max_forks` | Maximum concurrent Nextflow tasks executed in parallel | `10` |
| `--queue` | SLURM partition/queue override (`compute` when omitted in `slurm`/`sdsu`) | `null` |
| `--account` | SLURM account passed as `--account=<name>` (uses scheduler default if omitted) | `null` |

### Preprocessing, Assembly, and Homology Options

| Parameter | Description | Default |
| :--- | :--- | :--- |
| `--trimming_tool` | Trimming engine: `trim_galore`, `fastp`, or `flexbar` | `trim_galore` |
| `--quality` | Phred quality cutoff for read trimming | `30` |
| `--adapters` | Adapter FASTA used by Flexbar | `assets/illumina_adapter.fa` |
| `--deplete_host` | Subtract host reads before assembly via Bowtie2 | `false` |
| `--host_fasta` | Host reference genome FASTA for Bowtie2 index creation | `null` |
| `--host_bowtie2_index` | Pre-built Bowtie2 index prefix for host depletion | `null` |
| `--assembler` | Assembler: `megahit`, `metaspades`, or `hybrid` | `megahit` |
| `--min_contig_length` | Minimum assembled contig length in bp | `200` |
| `--blast_options` | Databases: `viruses` (alias `nt_viruses`), `nt`, `nr`, `all`, or comma-separated list | `viruses` |
| `--blast_max_target_seqs` | Maximum retained subjects per contig (all HSPs retained) | `50` |
| `--blastx_tool` | Protein alignment engine for `nr`: `diamond` or `blastx` | `diamond` |
| `--organize_contigs` | Sort contigs by taxonomy and isolate inter-family conflicts into `needs_review/` | `false` |

### Opt-In Novel Virus Discovery and Classification Options

| Parameter | Description | Default |
| :--- | :--- | :--- |
| `--discover_novel_viruses` | Enable post-BLAST triage, 6-frame ORF/DTR/EVE scan, synthesis, and XLSX/TSV reports | `false` |
| `--discovery_all_contigs` | Evaluate all contigs instead of skipping confident BLAST hits | `false` |
| `--novel_min_contig_length` | Minimum contig length forwarded to discovery (bp) | `500` |
| `--novel_min_orf_aa` | Minimum translated ORF length (amino acids) | `60` |
| `--known_virus_identity` | Nucleotide identity threshold (%) to skip known viruses at triage | `80.0` |
| `--known_virus_coverage` | Union query coverage threshold (%) to skip known viruses at triage | `50.0` |
| `--run_virfinder` | Enable VirFinder 8-mer scoring with BH-FDR and Order/Family follow-up | `false` |
| `--virfinder_min_score` | High-confidence VirFinder score threshold | `0.9` |
| `--virfinder_moderate_score` | Moderate-confidence VirFinder score threshold | `0.7` |
| `--virfinder_max_qvalue` | High-confidence VirFinder FDR q-value threshold | `0.05` |
| `--run_checkv` | Run CheckV completeness and host-gene assessment | `false` |
| `--run_genomad` | Run geNomad viral, plasmid, and provirus classification | `false` |
| `--run_viral_hmm` | Search candidate ORFs against VOGDB hallmark HMMs (`--hmm_evalue 1e-5`) | `false` |
| `--run_viral_protein_blast` | Run DIAMOND BLASTP against RefSeq viral proteins (`--viral_protein_evalue 1e-4`) | `false` |
| `--run_foldseek` | Run Foldseek 3D structural homology search (`--foldseek_db`) | `false` |
| `--run_novel_phylogeny` | Build MAFFT + FastTree/IQ-TREE (`--phylo_tool`) trees for promoted hallmark ORFs | `false` |

### Skip Flags

`--skip_quality`, `--skip_trimming`, `--skip_host_depletion`, `--skip_assembly`, `--skip_blast_annotation`, `--skip_taxonomic_profiling`, `--skip_viral_analysis`, `--skip_novel_detection`, `--skip_coverage_analysis`, `--skip_contig_organization`, `--skip_visualization`, `--skip_final_report`.

---

## Execution Profiles

Combine one **executor/site profile** with one **software profile** using a comma (no spaces), for example `-profile slurm,mamba` or `-profile sdsu,singularity`:

- **Executors / Sites**: `local`, `slurm`, `sdsu` (SLURM with pre-configured SDSU `/mmfs1` reference database paths).
- **Software Backends**: `conda`, `mamba`, `docker`, `singularity`, `apptainer`.

### Tiered Conda Environments (`envs/`)

When `-profile conda` or `-profile mamba` is enabled, Nextflow builds only the YAML files required by the processes you invoke and caches them in `--conda_cache_dir`:

| Environment File | Used By | Notes |
| :--- | :--- | :--- |
| `environment.yml` | Head node launcher | Lightweight Nextflow + OpenJDK 21 + Python launcher |
| `envs/setup_db.yml` | `setup_databases` | Native cross-platform (`linux-64`, `osx-arm64`, `osx-64`) BLAST+, DIAMOND, HMMER, ETE3 |
| `envs/core.yml` | Routine surveillance, BLAST, Kraken2, coverage, triage, reporting | Single environment built for default surveillance runs |
| `envs/quast.yml` | `quast` | Isolated QUAST >= 5.2.0 assembly statistics environment |
| `envs/assembly_extra.yml` | `metaspades`, `hybrid` | `spades` + `cd-hit` |
| `envs/virfinder.yml` | `virfinder` | Isolated R 4.3 + `r-virfinder` |
| `envs/checkv.yml` | `checkv` | Isolated CheckV environment |
| `envs/genomad.yml` | `genomad` | Isolated geNomad environment |
| `envs/discovery.yml` | `viral_hmm`, `novel_phylogeny` | `hmmer`, `mafft`, `fasttree`, `iqtree` |
| `envs/foldseek.yml` | `foldseek_viral` | Isolated Foldseek environment |
| `envs/flexbar.yml` / `envs/multiqc.yml` | `flexbar`, `multiqc` | Isolated optional utilities |

### Hybrid Container Strategy (Docker, Singularity, Apptainer)

- **27 core, assembly, discovery, and reporting processes** use `ghcr.io/navduhan/metanextviro:latest` (built from `Dockerfile` using Micromamba and `envs/core.yml`, `assembly_extra.yml`, `discovery.yml`, and `foldseek.yml`).
- **6 isolated single-tool processes** pull pinned official BioContainers on demand:
  - `quast`: `quay.io/biocontainers/quast:5.2.0--py310pl5321h6cc9453_3`
  - `genomad`: `quay.io/biocontainers/genomad:1.13.0--pyhdfd78af_0`
  - `checkv`: `quay.io/biocontainers/checkv:1.1.1--pyh106432d_1`
  - `virfinder`: `quay.io/biocontainers/r-virfinder:1.1--r44h503566f_8`
  - `flexbar`: `quay.io/biocontainers/flexbar:3.5.0--hdfd68b8_12`
  - `multiqc`: `quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2`

---

## SLURM Resource Labels (`nextflow/configs/slurm.config`)

| Label | CPUs | Memory | Time Limit | Typical Tasks |
| :--- | :--- | :--- | :--- | :--- |
| Default (unlabeled) | 2 | 8 GB | 4h | Lightweight helper tasks |
| `low` | 10 | 50 GB | 8h | FastQC, trimming, QUAST, triage, reporting |
| `medium` | 25 | 100 GB | 11h | Host depletion, viral BLASTN, coverage, CheckV, geNomad, HMMER |
| `high` | 40 | 200 GB | 11h | MEGAHIT, Kraken2, NCBI `nt` BLASTN, `nr` DIAMOND/BLASTX |
| `vhigh` | 40 | 250 GB | 11h | metaSPAdes assembly |

On SLURM clusters with small `$HOME` quotas, place `--conda_cache_dir` and `--db_dir` on shared scratch storage accessible from all compute nodes.
