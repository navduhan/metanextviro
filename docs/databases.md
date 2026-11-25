# Reference Database Setup, Component Inventory, and Offline Staging

MetaNextViro includes an automated reference database manager (`bin/setup_databases.py` and `nextflow/modules/setup_databases.nf`) that downloads, validates checksums, and indexes required databases locally on the submission node (even under `-profile slurm`).

---

## 1. Storage Presets (`--db_preset`)

| Preset (`--db_preset`) | Approx. Download | Included Components | Recommended Environment |
| :--- | :--- | :--- | :--- |
| `full_viral` *(default)* | **4.01 GB** | `taxonomy`, `refseq_viral_blastn`, `refseq_viral_protein`, `vog_hmm`, `kraken2_viral`, `checkv`, `genomad` | Complete surveillance + discovery on workstations or clusters |
| `minimal` | **1.11 GB** | `taxonomy`, `refseq_viral_blastn`, `refseq_viral_protein`, `vog_hmm`, `kraken2_viral` | Lightweight surveillance and protein/HMM discovery without CheckV/geNomad |
| `discovery_only` | **0.38 GB** | `taxonomy`, `refseq_viral_protein`, `vog_hmm` | Add-on when Kraken2 and `nt_viruses` already exist on HPC |
| `genbank_complete` | **18.83 GB** | Same as `full_viral`, replacing RefSeq viral BLASTN with full NCBI GenBank `nt_viruses` | Shared HPC cluster deployments needing full GenBank viral nucleotide coverage |

---

## 2. Per-Component Technical Inventory

| Component ID | Approx. Size | Upstream Source | Local Indexing Binary | Output Path Under `--db_dir` |
| :--- | :--- | :--- | :--- | :--- |
| `taxonomy` | 0.065 GB | NCBI `taxdump.tar.gz` (MD5 verified) | Python stdlib / ETE3 + `ktUpdateTaxonomy.sh --only-build` | `taxonomy/taxa.sqlite`, `taxonomy/krona/taxonomy.tab` |
| `refseq_viral_protein` | 0.160 GB | NCBI RefSeq viral `.protein.faa.gz` | `diamond makedb` | `viral_proteins/refseq_viral_proteins.dmnd`, `refseq_hallmark_refs.faa` |
| `vog_hmm` | 0.150 GB | VOGDB HMM archive + annotations + LCA | `hmmpress` + Python stdlib | `viral_hmm/vog_hallmarks.hmm`, `vog_hmm_taxonomy.tsv` |
| `refseq_viral_blastn` | 0.180 GB | NCBI RefSeq viral `.genomic.fna.gz` | `makeblastdb` | `blast_viruses/refseq_viral_genomic` |
| `nt_viruses` | 15.00 GB | NCBI BLAST `nt_viruses` preformatted DB | `update_blastdb.pl` | `nt_viruses/nt_viruses` |
| `kraken2_viral` | 0.550 GB | Langmead Lab AWS pre-built `k2_viral` | None (pre-built) | `kraken2_viral/hash.k2d` |
| `checkv` | 1.500 GB | NERSC CheckV v1.5 archive | None (`diamond makedb` fallback if needed) | `checkv/checkv-db-v1.5/` |
| `genomad` | 1.400 GB | Zenodo geNomad v1.9 archive | None (pre-built) | `genomad/genomad_db/` |

*Dependency resolution*: Requesting `refseq_viral_protein`, `refseq_viral_blastn`, or `vog_hmm` via `--db_components` automatically ensures `taxonomy` is built first so accession-to-taxid and LCA mappings succeed.

---

## 3. Running Database Setup

```bash
# Default full_viral preset (4.01 GB) into ~/.metanextviro/dbs
nextflow run metanextviro --setup_databases --db_dir ~/.metanextviro/dbs -profile conda

# Lighter minimal preset (1.11 GB)
nextflow run metanextviro --setup_databases --db_preset minimal --db_dir ~/.metanextviro/dbs -profile conda

# Full GenBank nt_viruses preset (18.83 GB) on shared HPC scratch
nextflow run metanextviro --setup_databases --db_preset genbank_complete --db_dir /scratch/$USER/metanextviro_dbs -profile conda

# Cherry-pick specific components
nextflow run metanextviro --setup_databases --db_components taxonomy,refseq_viral_protein,vog_hmm,checkv --db_dir ~/.metanextviro/dbs -profile conda

# Auto-download missing databases immediately prior to analysis
nextflow run metanextviro --input samplesheet.csv --auto_download_dbs --db_dir ~/.metanextviro/dbs -profile conda

# Dry-run preview without downloading files
python bin/setup_databases.py --db-dir ~/.metanextviro/dbs --dry-run
```

### Atomic Staging and Resumability
Every download streams into a `.part` temporary file, verifies MD5 (for NCBI taxdump) or SHA-256 digests, atomically renames on completion, and writes a `.completed` marker inside each component subdirectory. Re-running `--setup_databases` skips completed components and resumes interrupted downloads safely. Pass `--db_force` to rebuild existing databases.

---

## 4. Auto-Discovery, Offline HPC Staging, and Custom Overrides

Upon completion, `setup_databases.py` writes three metadata files inside `--db_dir`:
- `databases.config` — ready-to-include Nextflow parameter config (`-c <db_dir>/databases.config`)
- `databases_params.yml` — YAML parameter file (`-params-file`)
- `database_manifest.json` — machine-readable provenance manifest with timestamps and paths

During normal runs, MetaNextViro automatically discovers all installed components inside `--db_dir` without passing `-c databases.config`. For air-gapped HPC clusters, run `--setup_databases` on a connected login/data-transfer node targeting shared `/scratch` or `/project` storage, then run analysis jobs offline pointing `--db_dir` to that shared path.

### Explicit Override Parameters

| Parameter | Expected Path |
| :--- | :--- |
| `--taxonomy_db` | ETE3 NCBI taxonomy SQLite file (`taxa.sqlite`) |
| `--kraken2_db` | Kraken2 database directory containing `hash.k2d` |
| `--blastdb_viruses` | BLAST nucleotide database prefix for viral genomes |
| `--blastdb_nt` | NCBI `nt` BLAST database prefix (for `--blast_options nt` or `all`) |
| `--blastdb_nr` | NCBI `nr` BLAST database prefix (for `--blastx_tool blastx`) |
| `--diamonddb` | DIAMOND protein database `.dmnd` file for `nr` |
| `--viral_protein_db` | RefSeq viral protein `.dmnd` file for divergent ORF BLASTP |
| `--viral_hmm_db` | Viral hallmark HMM library (`vog_hallmarks.hmm`) |
| `--viral_hmm_taxonomy` | Tab-delimited VOGDB HMM-to-LCA lineage table |
| `--phylo_reference_faa` | Curated reference viral hallmark protein FASTA for phylogeny |
| `--checkv_db` | CheckV v1.5 database directory |
| `--genomad_db` | geNomad v1.9 database directory |
| `--foldseek_db` | Foldseek structural database prefix (`--foldseek_prostt5_weights` optional) |
