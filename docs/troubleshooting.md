# Troubleshooting and Frequently Asked Questions

## 1. Nextflow and Java Issues

### `ERROR: Cannot find Java or it's a wrong version`
Nextflow `25.x`–`26.x` requires **Java 17 to 26** (Java 27+ or Java 8–11 will fail). Check which JVM is active:

```bash
java -version
echo "$JAVA_HOME"
```

If Homebrew or the system installed Java 27, activate the MetaNextViro Conda launcher (`openjdk=21`) or point `JAVA_HOME` explicitly to a Java 17–21 installation before running `nextflow`.

### `nextflow run metanextviro` fails with repository not found
Without a cached local pull, Nextflow resolves bare names without an owner prefix against `nextflow-io/<name>`. Run `nextflow pull navduhan/metanextviro` once on the machine; every subsequent run can use `nextflow run metanextviro`.

---

## 2. Conda, Mamba, and HPC Offline Compute Nodes

### SLURM compute nodes have no internet access
When using `-profile slurm,conda` or `-profile slurm,mamba`, Nextflow builds tiered Conda environments on the **login/submission node** before dispatching SLURM jobs. Ensure `--conda_cache_dir` points to a **shared filesystem** readable by all compute nodes (never `/tmp`):

```bash
nextflow run metanextviro \
  --input samplesheet.csv \
  --conda_cache_dir /scratch/$USER/metanextviro_envs \
  -profile slurm,mamba
```

### Home directory quota exceeded during Conda or Singularity caching
Move both the Conda cache and database directory (and `NXF_SINGULARITY_CACHEDIR` if using Singularity/Apptainer) onto shared scratch storage:

```bash
export NXF_SINGULARITY_CACHEDIR=/scratch/$USER/singularity_cache
nextflow run metanextviro \
  --input samplesheet.csv \
  --db_dir /scratch/$USER/metanextviro_dbs \
  --conda_cache_dir /scratch/$USER/metanextviro_envs \
  -profile slurm,singularity
```

### Apple Silicon (`arm64` macOS) Conda environments
All MetaNextViro Conda environments (`setup_db.yml`, `core.yml`, `quast.yml`, `discovery.yml`, `checkv.yml`, `genomad.yml`, `virfinder.yml`, `assembly_extra.yml`, `flexbar.yml`, `foldseek.yml`, and `multiqc.yml`) resolve natively on `osx-arm64`, `osx-64`, and `linux-64` without Rosetta 2 (`-profile local,conda`). For `--run_virfinder`, `bin/run_virfinder.R` compiles the bundled `bin/vendor/VirFinder_1.1.tar.gz` source archive once offline into `~/.metanextviro/r_libs/<platform>-R<major>.<minor>` whenever `VirFinder` is not preinstalled in the active R environment.

---

## 3. Containers (Docker, Singularity, Apptainer)

### `denied: permission_denied` when pulling `ghcr.io/navduhan/metanextviro:latest`
For public pulls without `docker login`, the GitHub Container Registry package visibility under GitHub Packages must be set to **Public** (or log in with a GitHub PAT carrying `read:packages`). Alternatively, override the core image with `--container_image <your_local_image>` or run `-profile conda` / `-profile mamba`.

### Singularity fails to bind-mount input FASTQ paths
MetaNextViro sets `singularity.autoMounts = true` and `apptainer.autoMounts = true`. On clusters that restrict overlay mounts, pass explicit bind paths in a small site config (`-c site.config`):

```groovy
singularity.runOptions = "-B /scratch:/scratch -B ${projectDir}:${projectDir}:ro"
```

---

## 4. Reference Databases and Taxonomy

### Interrupted database downloads
`bin/setup_databases.py` writes atomic `.part` files and `.completed` markers. Simply re-run the exact same `--setup_databases` command; completed components are skipped automatically, and incomplete downloads restart cleanly. Pass `--db_force` only if you want to overwrite completed components.

### `No Kraken2 database found` or `No viral BLAST database found`
Check that `--db_dir` matches where you ran `--setup_databases` (default `~/.metanextviro/dbs`). Alternatively, pass `--auto_download_dbs`, supply explicit paths (`--kraken2_db`, `--blastdb_viruses`), or use `-profile sdsu` on SDSU HPC.

### `ete3` tries to access the internet during annotation
Provide `--taxonomy_db /path/to/taxa.sqlite` (automatically configured when running `--setup_databases`). `bin/process_blast_results.py` opens one local read-only SQLite connection and never contacts NCBI during annotation.

---

## 5. Assembly, BLAST, Discovery, and Cleanup

### metaSPAdes runs out of memory on complex metagenomes
MEGAHIT (`--assembler megahit`, default) uses substantially less RAM and runs ~28x faster on routine samples. Use `--assembler metaspades` or `--assembler hybrid` only when maximum terminal contig recovery is required and `vhigh` memory (`250 GB` on SLURM) is available, or override memory in `-c custom.config`:

```groovy
process {
    withName: 'metaspades' {
        memory = '384 GB'
        time   = '72h'
    }
}
```

### Zero candidate contigs after post-BLAST triage
This is expected when every assembled contig `>= 500 bp` already matched a known virus (`>= 80%` identity and `>= 50%` union coverage) or cellular reference in BLAST. Inspect `novel_virus_detection/details/<sample>_triage_summary.txt` to verify counts, or pass `--discovery_all_contigs` if you want VirFinder/CheckV/geNomad to score all contigs regardless of BLAST hits.

### `bin/cleanup_work.py` refuses to delete `work/`
The cleanup script intentionally blocks deletion if:
1. The latest run or resumed session did not finish with status `OK`.
2. `--results` contains symbolic links (for example from `--publish_mode symlink`).
3. `--results` is empty or overlaps with a task work directory.

Run `nextflow log` inside the launch directory to verify run status and confirm you published with `--publish_mode copy` (default) before retrying cleanup.

---

## 6. Frequently Asked Questions

- **Can I analyze single-end reads?** Input samplesheets currently expect paired `fastq_1` and `fastq_2` columns; paired-end shotgun Illumina libraries are the primary supported input.
- **Why are VirFinder scores paired with protein/HMM taxonomy?** Raw 8-mer scores have high false-positive rates on repeats, plasmids, and pseudogenized EVEs and provide no Order or Family label. MetaNextViro applies BH-FDR q-values, 3-mer Shannon entropy gating, and conservative protein/HMM LCA follow-up so VirFinder hits receive calibrated higher-rank taxonomy without species over-classification.
- **How do I resume a failed run?** Re-run the exact same Nextflow command with `-resume`. Do not run `bin/cleanup_work.py --apply` until you no longer need `-resume`.
