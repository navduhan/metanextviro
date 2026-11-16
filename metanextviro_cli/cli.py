#!/usr/bin/env python3
"""Command-line launcher so users can run `metanextviro ...` directly."""

import os
import shutil
import subprocess
import sys
from pathlib import Path

from metanextviro_cli import __version__

GITHUB_REPO = "navduhan/metanextviro"


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

    # Convenient subcommand alias: `metanextviro setup-db ...`
    if argv and argv[0] == "setup-db":
        rest = argv[1:]
        if repo_root and (repo_root / "scripts/setup_databases.py").is_file():
            return [sys.executable, str(repo_root / "scripts/setup_databases.py"), *rest], None
        nf = ensure_nextflow()
        return [nf, "run", target, "--setup_databases", *rest], None

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
    result = subprocess.run(cmd)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
