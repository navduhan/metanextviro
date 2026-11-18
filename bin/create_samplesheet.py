#!/usr/bin/env python3
# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""Scans a directory of paired-end FASTQ files and writes a validated MetaNextViro samplesheet CSV. Matches Illumina, standard R1/R2, and SRA 1/2 naming patterns and checks that every sample has both mates."""

import argparse
import csv
import re
import sys
from pathlib import Path

FASTQ_EXT_RE = re.compile(r"\.(?:fastq|fq)(?:\.gz)?$", re.IGNORECASE)

# Priority-ordered mate patterns applied after stripping FASTQ extensions
MATE_PATTERNS = [
    # Illumina BCLConvert / Casava: Sample_S1_L001_R1_001, Sample_L001_R1, Sample_S1_R1_001
    re.compile(
        r"^(?P<base>.+?)(?:_S\d+)?(?P<lane>_L\d{3})?[_.-]R(?P<mate>[12])(?:_\d{3})?$",
        re.IGNORECASE,
    ),
    # Trimmed / QC paired suffixes: Sample_R1_trimmed, Sample_R1_val_1
    re.compile(
        r"^(?P<base>.+?)(?P<lane>_L\d{3})?[_.-]R(?P<mate>[12])[_.-](?:trimmed|clean|paired|val_[12])$",
        re.IGNORECASE,
    ),
    # SRA / ENA / generic _1 / _2 suffixes: SRR123456_1, Sample.1
    re.compile(
        r"^(?P<base>.+?)(?P<lane>_L\d{3})?[_.-](?P<mate>[12])$",
        re.IGNORECASE,
    ),
]


def parse_fastq_filename(filename: str):
    """Return (base_sample, lane_suffix, mate_int) or None if not a recognized FASTQ pair member."""
    if not FASTQ_EXT_RE.search(filename):
        return None
    stem = FASTQ_EXT_RE.sub("", filename)
    for pattern in MATE_PATTERNS:
        match = pattern.match(stem)
        if match:
            base = match.group("base").strip("._- ")
            lane = (match.groupdict().get("lane") or "").upper()
            mate = int(match.group("mate"))
            if base:
                return base, lane, mate
    return None


def discover_paired_samples(reads_dir: Path, recursive: bool = False, allow_unpaired: bool = False):
    """Scan `reads_dir` and return a sorted list of (sample_id, r1_abs_path, r2_abs_path) tuples."""
    if not reads_dir.exists() or not reads_dir.is_dir():
        raise ValueError(f"FASTQ directory does not exist or is not a directory: {reads_dir}")

    iterator = reads_dir.rglob("*") if recursive else reads_dir.iterdir()
    parsed_entries = []
    unrecognized_fastqs = []

    for entry in sorted(iterator):
        if entry.name.startswith(".") or not entry.is_file():
            continue
        if not FASTQ_EXT_RE.search(entry.name):
            continue
        parsed = parse_fastq_filename(entry.name)
        if parsed is None:
            unrecognized_fastqs.append(entry.name)
            continue
        base, lane, mate = parsed
        # Preserve absolute path without resolving symlinks away if user staged symlinks,
        # or resolve to canonical path so Nextflow can read from any launch directory.
        abs_path = str(entry.resolve())
        parsed_entries.append((base, lane, mate, abs_path, entry.name))

    if not parsed_entries:
        hint = (
            f" Unrecognized FASTQ filenames: {', '.join(unrecognized_fastqs[:5])}."
            if unrecognized_fastqs
            else ""
        )
        raise ValueError(
            f"No paired FASTQ files (*_R1/*_R2 or *_1/*_2) found in '{reads_dir}'.{hint}"
        )

    # Check whether any sample base has multiple lanes (e.g. _L001 and _L002)
    lanes_per_base = {}
    for base, lane, _mate, _path, _name in parsed_entries:
        lanes_per_base.setdefault(base, set()).add(lane)

    grouped = {}
    for base, lane, mate, abs_path, orig_name in parsed_entries:
        use_lane = len(lanes_per_base[base]) > 1 and lane
        sample_id = f"{base}{lane}" if use_lane else base
        slot = grouped.setdefault(sample_id, {})
        if mate in slot:
            raise ValueError(
                f"Duplicate R{mate} FASTQ files detected for sample '{sample_id}': "
                f"'{slot[mate]}' and '{abs_path}'."
            )
        slot[mate] = abs_path

    rows = []
    incomplete = []
    for sample_id in sorted(grouped):
        mates = grouped[sample_id]
        r1 = mates.get(1)
        r2 = mates.get(2)
        if not r1 or not r2:
            if allow_unpaired:
                rows.append((sample_id, r1 or "NA", r2 or "NA"))
            else:
                missing = "R2" if r1 else "R1"
                incomplete.append(f"{sample_id} (missing {missing})")
        else:
            rows.append((sample_id, r1, r2))

    if incomplete:
        raise ValueError(
            "Incomplete paired-end FASTQ mates for: "
            + ", ".join(incomplete)
            + ". Supply matching R1/R2 files or pass --allow-unpaired."
        )

    if not rows:
        raise ValueError(f"No valid paired-end samples discovered in '{reads_dir}'.")

    return rows


def generate_samplesheet(
    reads_dir: Path,
    output_csv: Path,
    recursive: bool = False,
    allow_unpaired: bool = False,
    legacy_header: bool = False,
):
    """Write a MetaNextViro CSV samplesheet and return the discovered rows."""
    rows = discover_paired_samples(
        Path(reads_dir), recursive=recursive, allow_unpaired=allow_unpaired
    )
    output_csv = Path(output_csv)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    header = ["id", "reads1", "reads2"] if legacy_header else ["sample", "fastq_1", "fastq_2"]

    with open(output_csv, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        for sample_id, r1, r2 in rows:
            writer.writerow([sample_id, r1, r2])

    return rows


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate a MetaNextViro samplesheet CSV from a directory of paired FASTQ files."
    )
    parser.add_argument(
        "-i",
        "--reads-dir",
        "--input_dir",
        dest="reads_dir",
        required=True,
        type=Path,
        help="Directory containing paired FASTQ files (.fastq.gz, .fq.gz, .fastq, .fq).",
    )
    parser.add_argument(
        "-o",
        "--output",
        "--output_file",
        dest="output",
        default=Path("samplesheet.csv"),
        type=Path,
        help="Output CSV path (default: samplesheet.csv).",
    )
    parser.add_argument(
        "-r",
        "--recursive",
        action="store_true",
        help="Recursively scan subdirectories under --reads-dir.",
    )
    parser.add_argument(
        "--allow-unpaired",
        action="store_true",
        help="Allow samples missing R1 or R2 (writes NA instead of raising an error).",
    )
    parser.add_argument(
        "--legacy-header",
        action="store_true",
        help="Write 'id,reads1,reads2' header instead of 'sample,fastq_1,fastq_2'.",
    )
    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        rows = generate_samplesheet(
            reads_dir=args.reads_dir,
            output_csv=args.output,
            recursive=args.recursive,
            allow_unpaired=args.allow_unpaired,
            legacy_header=args.legacy_header,
        )
    except ValueError as exc:
        sys.stderr.write(f"Error: {exc}\n")
        return 1

    print(f"Created samplesheet '{args.output}' with {len(rows)} paired-end sample(s):")
    for sample_id, r1, r2 in rows:
        print(f"  - {sample_id}: {Path(r1).name} | {Path(r2).name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
