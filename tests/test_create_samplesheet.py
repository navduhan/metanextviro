# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""Unit tests checking paired FASTQ filename parsing across Illumina, R1/R2, and SRA patterns, multi-lane handling, and unpaired mate errors in create_samplesheet.py."""

import csv
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_create_samplesheet():
    spec = importlib.util.spec_from_file_location(
        "create_samplesheet", ROOT / "bin" / "create_samplesheet.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cs = load_create_samplesheet()


class CreateSamplesheetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def test_discovers_illumina_standard_and_sra_paired_fastqs(self):
        fq_dir = self.base / "fastqs"
        fq_dir.mkdir()
        for fname in [
            "Avian_Swab_S1_L001_R1_001.fastq.gz",
            "Avian_Swab_S1_L001_R2_001.fastq.gz",
            "Swine_Nasal_R1.fq.gz",
            "Swine_Nasal_R2.fq.gz",
            "SRR998877_1.fastq",
            "SRR998877_2.fastq",
        ]:
            (fq_dir / fname).write_text("@r\nACGT\n+\nIIII\n")

        out_csv = self.base / "samplesheet.csv"
        rows = cs.generate_samplesheet(fq_dir, out_csv)
        self.assertEqual([r[0] for r in rows], ["Avian_Swab", "SRR998877", "Swine_Nasal"])

        with open(out_csv, newline="") as handle:
            parsed = list(csv.DictReader(handle))
        self.assertEqual(list(parsed[0].keys()), ["sample", "fastq_1", "fastq_2"])
        self.assertEqual(len(parsed), 3)
        self.assertTrue(parsed[0]["fastq_1"].endswith("Avian_Swab_S1_L001_R1_001.fastq.gz"))
        self.assertTrue(parsed[0]["fastq_2"].endswith("Avian_Swab_S1_L001_R2_001.fastq.gz"))

    def test_preserves_lane_suffix_when_multi_lane_sample_present(self):
        fq_dir = self.base / "multilane"
        fq_dir.mkdir()
        for fname in [
            "FlockA_S2_L001_R1_001.fastq.gz",
            "FlockA_S2_L001_R2_001.fastq.gz",
            "FlockA_S2_L002_R1_001.fastq.gz",
            "FlockA_S2_L002_R2_001.fastq.gz",
        ]:
            (fq_dir / fname).write_text("@r\nACGT\n+\nIIII\n")

        rows = cs.discover_paired_samples(fq_dir)
        self.assertEqual([r[0] for r in rows], ["FlockA_L001", "FlockA_L002"])

    def test_rejects_unpaired_mate_by_default_and_supports_cli(self):
        fq_dir = self.base / "broken"
        fq_dir.mkdir()
        (fq_dir / "LonelySample_R1.fastq.gz").write_text("@r\nACGT\n+\nIIII\n")

        with self.assertRaisesRegex(ValueError, "Incomplete paired-end FASTQ mates"):
            cs.discover_paired_samples(fq_dir)

        (fq_dir / "LonelySample_R2.fastq.gz").write_text("@r\nACGT\n+\nIIII\n")
        out_csv = self.base / "cli_out.csv"
        proc = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "create_samplesheet.py"), "-i", str(fq_dir), "-o", str(out_csv)],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("Created samplesheet", proc.stdout)
        self.assertTrue(out_csv.is_file())


if __name__ == "__main__":
    unittest.main()
