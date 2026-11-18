#!/usr/bin/env python3
# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""Previews and executes log-preserving cleanup of task work files for a completed Nextflow run. Verifies run status and checks that published results contain real files before calling nextflow clean."""

import argparse
import csv
import shlex
import subprocess
from pathlib import Path


def nextflow_output(executable, args, launch_dir):
    result = subprocess.run([executable, *args], cwd=launch_dir, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or 'Nextflow command failed')
    return result.stdout


def successful_run(history, identifier):
    """Use the status of the last history entry matching an explicit name/session."""
    rows = [{key.strip(): value.strip() for key, value in row.items()}
            for row in csv.DictReader(history.splitlines(), delimiter='\t')]
    if not rows or not {'RUN NAME', 'SESSION ID', 'STATUS'}.issubset(rows[0]):
        raise ValueError('Cannot read Nextflow run history; run nextflow log in the launch directory.')
    matches = [row for row in rows if identifier in (row['RUN NAME'], row['SESSION ID'])]
    if not matches:
        raise ValueError(f'Run not found in this launch directory: {identifier}')
    if matches[-1]['STATUS'] != 'OK':
        raise ValueError(f"Run {identifier} did not finish successfully (status: {matches[-1]['STATUS']}).")
    session = matches[-1]['SESSION ID']
    latest = [row for row in rows if row['SESSION ID'] == session][-1]
    if latest['STATUS'] != 'OK':
        raise ValueError('A later attempt of this session is unfinished or failed; keep its work files for debugging.')
    return matches[-1]['RUN NAME']


def validate_results(results, workdirs):
    """Require a separate, nonempty result tree with no symbolic links."""
    if results.is_symlink() or not results.is_dir():
        raise ValueError('Results must be an existing real directory, not a symbolic link.')
    results = results.resolve()
    found_file = False
    for entry in results.rglob('*'):
        if entry.is_symlink():
            raise ValueError(f'Results contain a symbolic link: {entry}. Publish with --publish_mode copy before cleanup.')
        found_file = found_file or entry.is_file()
    if not found_file:
        raise ValueError('Results directory contains no files; cleanup refused.')
    for workdir in workdirs:
        workdir = workdir.resolve()
        if results.is_relative_to(workdir) or workdir.is_relative_to(results):
            raise ValueError('Results and task work directories overlap; cleanup refused.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', required=True, help='Explicit Nextflow run name or session ID; never defaults to latest.')
    parser.add_argument('--results', required=True, type=Path, help='Published results you have validated.')
    parser.add_argument('--launch-dir', type=Path, default=Path.cwd(), help='Original run launch directory containing .nextflow history.')
    parser.add_argument('--nextflow', default='nextflow', help='Nextflow executable, if not on PATH.')
    parser.add_argument('--apply', action='store_true', help='Remove task data after validating results; keeps logs and prevents resume of cleaned tasks.')
    args = parser.parse_args(argv)
    try:
        launch_dir = args.launch_dir.resolve(strict=True)
        history = nextflow_output(args.nextflow, ['log'], launch_dir)
        run_name = successful_run(history, args.run)
        output = nextflow_output(args.nextflow, ['log', run_name, '-f', 'workdir'], launch_dir)
        workdirs = [Path(line.strip()) for line in output.splitlines() if line.strip()]
        workdirs = [path if path.is_absolute() else launch_dir / path for path in workdirs]
        results = args.results if args.results.is_absolute() else launch_dir / args.results
        validate_results(results, workdirs)
        command = [args.nextflow, 'clean', run_name, '-keep-logs', '-force' if args.apply else '-dry-run']
        print('Command:', shlex.join(command), flush=True)
        print('Task data will be removed; execution logs stay. Cleaned tasks cannot resume.' if args.apply
              else 'Preview only; no files will be removed. Validate published results before using --apply.', flush=True)
        subprocess.run(command, cwd=launch_dir, check=True)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Cleanup refused or failed: {exc}\n')


if __name__ == '__main__':
    main()
