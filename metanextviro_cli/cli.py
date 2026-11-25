#!/usr/bin/env python3
# Author: Naveen Duhan
# SPDX-License-Identifier: MIT
"""Thin command-line wrapper that forwards metanextviro arguments to nextflow run and provides shortcuts for pull, setup-db, create-samplesheet, and cleanup."""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from metanextviro_cli import __version__

GITHUB_REPO = "navduhan/metanextviro"


def _java_major(java_bin):
    try:
        out = subprocess.run([str(java_bin), "-version"], capture_output=True, text=True, timeout=5)
        m = re.search(r'"(\d+)', (out.stdout or "") + "\n" + (out.stderr or ""))
        return int(m.group(1)) if m else None
    except Exception:
        return None


def ensure_compatible_java_env(env):
    """Ensure JAVA_HOME points to Java 17..26 for Nextflow when system JAVA_HOME is OpenJDK 27+."""
    jh = env.get("JAVA_HOME")
    if jh:
        maj = _java_major(Path(jh) / "bin/java")
        if maj is not None and 17 <= maj <= 26:
            return
    candidates = []
    if env.get("CONDA_PREFIX"):
        candidates.append(Path(env["CONDA_PREFIX"]) / "lib/jvm")
    for p in (
        "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
        "/opt/homebrew/opt/openjdk@21",
        "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
        "/opt/homebrew/opt/openjdk@17",
    ):
        candidates.append(Path(p))
    home = Path.home()
    for base in ("miniconda3/envs", "miniforge3/envs", "mambaforge/envs", "anaconda3/envs"):
        envs_dir = home / base
        if envs_dir.is_dir():
            for child in sorted(envs_dir.iterdir()):
                candidates.append(child / "lib/jvm")
    for cand in candidates:
        maj = _java_major(cand / "bin/java")
        if maj is not None and 17 <= maj <= 26:
            env["JAVA_HOME"] = str(cand)
            env["JAVA_CMD"] = str(cand / "bin/java")
            return


def resolve_pipeline_target():
    """Prefer a local repository checkout's main.nf when available; otherwise use GitHub repo."""
    repo_root = Path(__file__).resolve().parents[1]
    local_main = repo_root / "main.nf"
    if local_main.is_file() and (repo_root / "nextflow.config").is_file():
        return str(local_main), repo_root
    return GITHUB_REPO, None


def ensure_nextflow():
    nf = shutil.which("nextflow")
    if not nf:
        sys.stderr.write(
            "Error: 'nextflow' executable not found on PATH.\n"
            "Install Nextflow with Conda (`conda install -c bioconda nextflow`) "
            "or `curl -s https://get.nextflow.io | bash`.\n"
        )
        sys.exit(1)
    return nf


def build_nextflow_command(argv):
    target, repo_root = resolve_pipeline_target()
    if argv and argv[0] in ("-v", "--version", "version"):
        return None, f"MetaNextViro v{__version__} (target: {target})"

    # Convenient subcommand alias: `metanextviro pull` (caches navduhan/metanextviro so `nextflow run metanextviro` works)
    if argv and argv[0] == "pull":
        nf = ensure_nextflow()
        return [nf, "pull", GITHUB_REPO, *argv[1:]], None

    # Convenient subcommand alias: `metanextviro setup-db ...`
    if argv and argv[0] == "setup-db":
        rest = argv[1:]
        if repo_root and (repo_root / "bin/setup_databases.py").is_file():
            return [sys.executable, str(repo_root / "bin/setup_databases.py"), *rest], None
        nf = ensure_nextflow()
        return [nf, "run", target, "--setup_databases", *rest], None

    # Convenient subcommand alias: `metanextviro create-samplesheet ...`
    if argv and argv[0] in ("create-samplesheet", "samplesheet"):
        rest = argv[1:]
        if repo_root and (repo_root / "bin/create_samplesheet.py").is_file():
            return [sys.executable, str(repo_root / "bin/create_samplesheet.py"), *rest], None
        nf = ensure_nextflow()
        return [nf, "run", target, "--create_samplesheet", *rest], None

    # Convenient subcommand alias: `metanextviro cleanup ...`
    if argv and argv[0] == "cleanup" and repo_root and (repo_root / "bin/cleanup_work.py").is_file():
        return [sys.executable, str(repo_root / "bin/cleanup_work.py"), *argv[1:]], None

    nf = ensure_nextflow()
    if not argv:
        return [nf, "run", target, "--help"], None
    if argv[0] == "run":
        argv = argv[1:]
    return [nf, "run", target, *argv], None


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    cmd, info_msg = build_nextflow_command(args)
    if info_msg is not None:
        print(info_msg)
        return 0
    env = os.environ.copy()
    ensure_compatible_java_env(env)
    result = subprocess.run(cmd, env=env)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
