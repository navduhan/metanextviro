# Output Structure, Column Schemas, Publishing Modes, and Cleanup

## 1. Output Directory Layout

```text
results/
├── samplesheet.csv             # Auto-generated when running directly from --reads_dir
├── fastqc/                     # Raw and trimmed read FastQC HTML/ZIP reports
├── trim_galore/                # Trimmed reads (or fastp/ / trimmed_reads/ for Flexbar)
├── host_depletion/             # Host-subtracted paired FASTQ reads (when --deplete_host)
├── megahit_assembly/           # MEGAHIT contigs (or metaspades_assembly/ / hybrid_assembly/)
├── assembly_stats/             # QUAST assembly quality metrics per sample
├── kraken2_results/            # Kraken2 read-level classification and reports
├── krona_results/              # Interactive Krona HTML taxonomy charts
├── blast_results/              # Sorted per-contig best-hit Excel (.xlsx) and TSV tables
│   ├── <sample>_best_hits_<db>.xlsx
│   ├── <sample>_best_hits_<db>.tsv
│   └── details/
│       ├── <sample>_subject_summary_<db>.tsv
│       ├── <sample>_all_hsps_<db>.tsv
│       └── <sample>_raw_<db>.txt
├── coverage/                   # Coordinate-sorted BAM/BAI, idxstats, and whole-contig depth
├── coverage_plots/             # Per-sample coverage PNG bar and distribution plots
├── organized_contigs/          # Taxonomically sorted FASTAs & needs_review/ (when --organize_contigs)
├── checkv/                     # CheckV completeness summaries (when --run_checkv)
├── genomad/                    # geNomad virus/plasmid summaries (when --run_genomad)
├── virfinder/                  # VirFinder full/filtered scores & Order/Family taxonomy
├── novel_virus_detection/      # Ranked novel candidate XLSX/TSV/FASTA, ORFs, phylogeny & details/
└── final_report/               # Cohort summary and per-sample PDF + standalone HTML reports
    ├── MetaNextViro_Summary_Report.pdf
    ├── MetaNextViro_Summary_Report.html
    └── per_sample/
        ├── <sample>_Viral_Report.pdf
        └── <sample>_Viral_Report.html
```

---

## 2. Column-by-Column Output Schemas

### A. Multi-HSP BLAST Best-Hit Table (`blast_results/<sample>_best_hits_<db>.tsv` & `.xlsx`)
Sorted descending by `alignment_length`, `bit_score`, `evalue`, `percent_identity`, and `query_length`.

| Column | Meaning |
| :--- | :--- |
| `query_id`, `query_length` | Standardized MetaNextViro contig identifier and nucleotide length (`bp`) |
| `subject_id`, `subject_title`, `subject_length` | Top reference sequence accession, title, and length |
| `percent_identity`, `alignment_length`, `evalue`, `bit_score` | Best HSP alignment metrics (`nt` for BLASTN; `aa` for DIAMOND/BLASTX) |
| `query_coverage`, `query_coverage_type` | Single-HSP coverage (`qcovhsp` on all new searches) |
| `query_union_coverage`, `hsp_count`, `query_regions` | Exact interval-merged coverage (%) across all HSPs for that subject, HSP count, and merged 1-based inclusive spans |
| `query_frame`, `query_strand`, `subject_strand` | Reading frame (BLASTX/DIAMOND) and alignment strand |
| `taxid`, `superkingdom` .. `species`, `taxonomy_status` | Cached ETE3 SQLite LCA lineage (`resolved`, `unresolved`, or `no_taxid`) |
| `sequence` | Complete nucleotide sequence in TSV (clamped cleanly at Excel's 32,767-char cell cap in XLSX with truncation note) |

### B. Whole-Contig Read Coverage (`coverage/coverage_<sample>.txt`)

| Column | Meaning |
| :--- | :--- |
| `Contig` | Standardized contig identifier (includes `0`-read contigs) |
| `Length` | Total contig length `L` from `samtools idxstats` |
| `Total_Reads` | Mapped read segments aligning to the contig |
| `Covered_Bases` | Number of nucleotide positions with depth `> 0` |
| `Average_Coverage` | Whole-contig mean depth (`sum(d_p) / L`, including uncovered positions) |
| `Coverage_Breadth` | Percentage of contig covered by at least one read (`100 * Covered_Bases / L`) |

### C. Ranked Novel Virus Candidates (`novel_virus_detection/<sample>_novel_virus_candidates.tsv` & `.xlsx`)

| Column | Meaning |
| :--- | :--- |
| `contig_id`, `contig_length` | Candidate contig ID and length (`>= 500 bp` after triage) |
| `classification_tier`, `composite_viral_score` | Mutually exclusive output tier (`high_confidence_candidate_virus`, `moderate_confidence_candidate_virus`, `possible_eve_or_provirus_needs_review`, `unconfirmed_viral_dark_matter`, or `plasmid_or_low_complexity_artifact`) and gated 0–100 score |
| `putative_kingdom` .. `putative_genus`, `taxonomy_assignment_level` | Identity-capped ICTV lineage and evidence source (e.g., `family_confident_novel_genus(48.2%_aa)` or `family_marker_taxonomy`) |
| `coding_density_pct`, `max_orf_aa`, `terminal_repeat_type`, `kmer_entropy_h3`, `stop_codons_per_kb` | Intrinsic 6-frame genome architecture, DTR/ITR repeat call, normalized 3-mer entropy, and EVE stop-density |
| `hmm_top_hit`, `vp_top_hit`, `genomad_virus_score`, `checkv_quality`, `virfinder_score`, `virfinder_qvalue` | Individual evidence layer calls supporting the composite score |
| `mean_read_depth`, `coverage_breadth_pct` | Whole-contig read depth and breadth (`< 50%` triggers EVE/chimera review) |
| `evidence_flags`, `sequence` | Pipe-delimited rationale tags and contig nucleotide sequence |

### D. VirFinder Taxonomic Summary (`virfinder/virfinder_<sample>_taxonomy.tsv` & `.xlsx`)
Created automatically whenever `--run_virfinder` is enabled, combining `virfinder_score`, `pvalue`, BH-FDR `qvalue`, `kmer_entropy`, `confidence_tier`, and putative Order/Family/Genus taxonomy inferred from multi-ORF protein/HMM/geNomad LCA.

### E. Contig Organization & Conflict Review (`organized_contigs/<sample>/`)
- `Viruses/<Family>/`: Single-family viral contigs grouped cleanly by family.
- `needs_review/`: Contigs with inter-family HSP conflicts or unresolved taxids, paired with `classification_review.tsv` and full `classification_evidence.tsv`.
- `unclassified/`: Contigs with zero BLAST hits.

### F. Cohort & Per-Sample Reports (`final_report/`)
- `MetaNextViro_Summary_Report.pdf` & `.html`: Cohort KPIs, host depletion and triage bars, viral family read-depth heatmap, promoted novel candidates table, dynamic Materials & Methods text generated from actual run parameters, and scientific interpretation guardrails.
- `per_sample/<sample>_Viral_Report.pdf` & `.html`: Dedicated single-sample reports cross-linked from the cohort HTML report.

---

## 3. Publishing Modes and Storage Safety

| Mode (`--publish_mode`) | Behavior | Portable / Cleanup-Safe? |
| :--- | :--- | :--- |
| `copy` *(default)* | Publishes independent file copies while keeping raw FASTQ inputs staged as symlinks (`stageInMode = 'symlink'`). | Yes (recommended) |
| `link` | Creates hard links on the same filesystem (`main.nf` tests hard-link compatibility before starting tasks). Treat published files as read-only. | Yes (same filesystem) |
| `symlink` / `rellink` | Links into `work/`. Removing `work/` breaks results; `bin/cleanup_work.py` refuses symlinked output directories. | No |

---

## 4. Safe Post-Run Work Cleanup (`bin/cleanup_work.py`)

Keep `work/` while debugging or using `-resume`. After verifying published outputs, locate the completed run name via `nextflow log` in the original launch directory, run a dry-run preview, and then apply cleanup:

```bash
# 1. Dry-run preview (verifies run status == OK and checks published copies contain zero symlinks)
python bin/cleanup_work.py \
  --run RUN_NAME \
  --launch-dir /path/to/launch_dir \
  --results /path/to/results

# 2. Remove cached task payloads while preserving Nextflow execution logs (-keep-logs)
python bin/cleanup_work.py \
  --run RUN_NAME \
  --launch-dir /path/to/launch_dir \
  --results /path/to/results \
  --apply
```

The helper automatically refuses failed runs, unfinished resumed sessions, empty result trees, symlinked results, and overlapping work/result paths. Cleaned tasks cannot be resumed.
