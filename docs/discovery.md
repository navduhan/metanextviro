# Algorithms: Multi-HSP Homology, Whole-Contig Coverage, and Divergent Virus Discovery

This reference documents the quantitative algorithms implemented across MetaNextViro's surveillance and opt-in discovery modules.

---

## 1. Multi-HSP Interval Union BLAST & Cached LCA Taxonomy (`bin/process_blast_results.py`)

Standard BLAST parsers either report only the single highest-scoring HSP (`qcovhsp`) or compute span from outermost start/end coordinates. On viral contigs split by internal insertions, frameshifts, or structural rearrangements, single-HSP reporting severely underestimates true viral span while outer min-max span bridges unaligned non-viral gaps to falsely report `100%` coverage.

MetaNextViro retains up to `--blast_max_target_seqs 50` subjects per contig and all reported HSPs (`--max-hsps 0 --sensitive` in DIAMOND). For a contig of length `L` and all HSPs belonging to one subject with normalized 1-based inclusive query intervals `[s_i, e_i]`:

1. Intervals are sorted by `s_i` and merged whenever overlapping or adjacent (`s_{i+1} <= e_i + 1`) to form disjoint union `U`.
2. Exact query union coverage is computed as:

```text
C_union (%) = (100 / L) * sum((b - a + 1) for [a, b] in U)
```

### Worked Split-HSP Example (`L = 1,900 bp`)
Suppose a `1,900 bp` contig contains two viral regions (`[1..720]` via overlapping HSPs `[1..488]` + `[406..720]`, and `[1,241..1,900]`) separated by a `520 bp` unaligned insertion (`[721..1,240]`):
- **Single-HSP `qcovhsp`**: Reports `720 / 1,900 = 37.9%` (drops HSP 2; `-34.7` percentage points error).
- **Outer min-max span**: Bridges the `520 bp` gap and reports `1,900 / 1,900 = 100.0%` (`+27.4` percentage points bias).
- **MetaNextViro interval union**: Merges `[1..488]` + `[406..720]` -> `[1..720]` (`720 bp`) and keeps `[1,241..1,900]` (`660 bp`), reporting `(720 + 660) / 1,900 = 72.6%` (`0.0%` error).

### Coordinate & Strand Conventions
- Coordinates are **1-based, inclusive** for both BLASTN and BLASTX/DIAMOND.
- For protein searches (`blastx`, `diamond blastx`), `qstart`, `qend`, and `qlen` are nucleotide coordinates while `alignment_length` is amino acids; `qframe` is stored as `query_frame` with derived `query_strand` and blank `subject_strand`.
- One local ETE3 SQLite connection (`TaxonomyResolver`) caches taxid lookups and intersects multi-taxid records to their lowest common ancestor (LCA) across standard NCBI ranks.

### Inter-Family Conflict Auditing (`--organize_contigs`)
`bin/organize_contigs_by_taxonomy.py` audits **all retained HSPs** (not only the top hit). If a contig aligns to conflicting viral families (for example a `5'` *Caliciviridae* HSP and a `3'` *Spinareoviridae* HSP) or carries unresolved taxids among classified hits, it is isolated in `organized_contigs/<sample>/needs_review/` alongside `classification_review.tsv` and `classification_evidence.tsv`. Contigs are never auto-split; conflicts require human review.

---

## 2. Single-Pass Whole-Contig Read Coverage (`bin/calculate_contig_coverage.sh`)

Trimmed paired reads map to assembled contigs with Bowtie2 piped directly into `samtools sort` (avoiding temporary unsorted BAMs). `bin/calculate_contig_coverage.sh` joins contig lengths `L` from `samtools idxstats` with one pass of `samtools depth`:

```text
Mean Depth D_bar = (1 / L) * sum_{p=1..L} d_p
Breadth B (%)    = (100 / L) * sum_{p=1..L} I(d_p > 0)
```

Averaging only across covered sites (`d_p > 0`) inflates abundance dramatically on short conserved islands (for example a `2,097 bp` contig with `24.1x` local depth over `29.9%` breadth has true whole-contig depth `7.2x`, a `3.34x` overestimation). Dividing by full contig length `L` eliminates island inflation and retains zero-read contigs at `0.00x` depth and `0.00%` breadth for cross-sample cohort heatmaps.

---

## 3. Automated Post-BLAST Contig Triage (`bin/triage_contigs.py`)

Discovery modules stay off by default so routine runs finish quickly. When `--discover_novel_viruses`, `--run_virfinder`, `--run_checkv`, or `--run_genomad` is enabled, `bin/triage_contigs.py` partitions contigs using BLAST results before running downstream models:

| Partition | Rule | Action |
| :--- | :--- | :--- |
| `known_virus` | Viral BLAST hit with `>= 80.0%` identity & `>= 50.0%` union coverage (no cellular conflict) | **Skipped** (already identified) |
| `known_non_viral` | Cellular/host BLAST hit with `>= 75.0%` identity & `>= 40.0%` union coverage (no viral conflict) | **Skipped** (host/bacterial background) |
| `short_unassigned` | Unassigned fragment `< 500 bp` (`--novel_min_contig_length`) | **Skipped** (too short for ORF/HMM) |
| `candidate` | Unassigned `>= 500 bp`, divergent viral hit (`< 80%` ID or `< 50%` cov), or viral-cellular conflict | **Forwarded** to discovery cascade |

Override triage with `--discovery_all_contigs` when exhaustive scoring of every contig is required.

---

## 4. Intrinsic Viral Architecture & Artifact Gates (`bin/scan_viral_architecture.py`)

Forwarded candidate contigs undergo six-frame biophysical scanning:

- **Edge-open viral ORFs**: Translates all six frames (`>= 60 aa` from ATG, GTG, or TTG codons), retaining 5' and 3' partial edge ORFs common on metagenomic contigs and allowing realistic viral gene overlaps (`<= 60 bp` or `<= 25%` of ORF length).
- **Direct & Inverted Terminal Repeats (DTR / ITR)**: Detects exact terminal repeats of `20` to `500 bp` indicating circular or complete linear viral genomes.
- **Normalized 3-mer Shannon entropy (`H3_hat`)**:
  ```text
  H3_hat = -(1 / 6) * sum_{k in {A,C,G,T}^3} p_k * log2(p_k)
  ```
  Contigs with `H3_hat < 0.65` or `> 10%` ambiguous (`N`) bases are flagged as low-complexity repeat artifacts.
- **Pseudogenized EVE stop-density gate**: Contigs `>= 1,500 bp` with coding density `< 40.0%` (or max ORF `< 90 aa`) and `> 8.0` stop codons/kb across all six frames are flagged for endogenous viral element (EVE) review.
- **Enhanced VirFinder (`bin/run_virfinder.R`)**: Pairs VirFinder 8-mer scoring with `VF.qvalue` and automatic Benjamini-Hochberg FDR fallback when spline fitting fails on small candidate sets, plus `H3_hat` low-complexity gating.

---

## 5. Eight-Source Composite Score, Gating, and ICTV Taxonomic Rank Calibration (`bin/synthesize_novel_viruses.py`)

Evidence across up to eight layers accumulates into an additive support score capped at `100.0` points prior to artifact gating:

| Evidence Layer | Threshold / Trigger | Points |
| :--- | :--- | :--- |
| VOGDB / RdRp profile HMM (`--run_viral_hmm`) | Core hallmark (`RdRp`, `Capsid_Coat`, `Portal_Terminase`, `Helicase_Rep`) / other VOG (`E <= 1e-5`) | `+40` / `+30` |
| RefSeq viral protein DIAMOND (`--run_viral_protein_blast`) | `E <= 1e-10` / `1e-10 < E <= 1e-4` | `+28` / `+18` |
| geNomad neural classifier (`--run_genomad`) | `virus_score >= 0.70` and `virus_score >= plasmid_score` | `+24` |
| Foldseek ProstT5 3D search (`--run_foldseek`) | `prob >= 0.85` or `E <= 1e-4` | `+22` |
| CheckV (`--run_checkv`) | Viral genes `>= 1` or Medium/High/Complete quality | `+20` |
| Divergent BLASTN hit | Viral hit with `< 80.0%` identity or `< 50.0%` union coverage | `+20` |
| VirFinder FDR tier (`--run_virfinder`) | High (`score >= 0.90`, `q <= 0.05`, `H3 >= 0.65`) / moderate (`>= 0.70`, `q <= 0.10`) | `+18` / `+10` |
| Intrinsic architecture & read breadth | Coding `>= 75%` & max ORF `>= 150 aa` (`+10`); DTR/ITR (`+10`); breadth `>= 85%` at `>= 2x` (`+8`) | up to `+28` |

### Five Mutually Exclusive Output Tiers
1. **`plasmid_or_low_complexity_artifact`** *(excluded; 75% score penalty)*: `H3_hat < 0.65`, `> 10%` Ns, or geNomad `plasmid_score >= 0.70 > virus_score`.
2. **`possible_eve_or_provirus_needs_review`** *(manual review; `discovery_score` capped at `min(44.0, 0.50 * score)`)*: CheckV host genes or provirus call, cellular BLAST conflict, EVE stop-density signature, or mapped read breadth `< 50.0%`.
3. **`high_confidence_candidate_virus`** *(promoted)*: Intact candidate with score `>= 45`, hallmark HMM or `>= 2` independent viral signals, and breadth `>= 70.0%` when mapped.
4. **`moderate_confidence_candidate_virus`** *(promoted)*: Intact candidate with `>= 1` viral signal or DTR/ITR plus dense viral coding architecture (`>= 75%`).
5. **`unconfirmed_viral_dark_matter`** *(excluded)*: Unassigned contig `>= 500 bp` lacking viral homology or architecture cues.

### Bit-Score-Weighted Multi-ORF LCA & ICTV Identity Rank Caps
For top protein alignments `r in O` (`E <= 1e-4`) with bit scores `b_r` and percent identities `I_r`, weighted amino-acid identity is `I_AA = sum(b_r * I_r) / sum(b_r)`. Each taxonomic rank is retained only if one taxon accounts for `>= 60%` of total bit score, halting at any inter-ORF conflict, and is then capped conservatively:

| Mean AA Identity (`I_AA`) | Deepest Retained Rank | Cleared Ranks | Rationale |
| :--- | :--- | :--- | :--- |
| `< 25.0%` | Order / Class | Family, Genus, Species | Twilight-zone homology; prevents false family/genus calls |
| `25.0%` to `< 65.0%` | Putative Family | Genus, Species | Novel genus within known viral family |
| `>= 65.0%` | Putative Genus | Species | Species always withheld on divergent candidates |

Fallback hierarchy when protein alignments are absent: **geNomad marker LCA** (`virus_score >= 0.70`) -> **VOGDB HMM LCA** -> **divergent BLASTN** (`< 70%` NT clears genus). Enabling `--run_virfinder` automatically triggers this lookup and exports `virfinder/virfinder_<sample>_taxonomy.xlsx` and `.tsv`. When `--run_novel_phylogeny` is enabled, promoted hallmark ORFs are aligned with MAFFT (`--auto`) and placed into midpoint-rooted maximum-likelihood trees using FastTree or IQ-TREE (`--phylo_tool`).
