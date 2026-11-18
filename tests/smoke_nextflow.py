#!/usr/bin/env python3
# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""End-to-end local smoke test executing MEGAHIT, BLAST+, DIAMOND, Bowtie2, SAMtools, Nextflow resume, publishing modes, and log-preserving cleanup on synthetic data in a temporary directory.

Run inside the pipeline environment: python tests/smoke_nextflow.py
Requires Nextflow, Java, MEGAHIT, BLAST+, DIAMOND, Bowtie2, SAMtools, and Python dependencies.
"""

import csv
import hashlib
import re
import os
import random
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

from Bio.Seq import Seq
from ete3.ncbi_taxonomy.ncbiquery import DB_VERSION

ROOT = Path(__file__).resolve().parents[1]
BASE = Path(tempfile.mkdtemp(prefix='metanextviro-smoke-'))
ENV = dict(os.environ, NXF_OFFLINE='true', NXF_DISABLE_CHECK_LATEST='true', NXF_SYNTAX_PARSER='v2')
JAVA = Path(sys.prefix) / 'lib/jvm'
if JAVA.is_dir():
    ENV['JAVA_HOME'] = str(JAVA)


def run(command, name, cwd=BASE, expected=0):
    result = subprocess.run([str(arg) for arg in command], cwd=cwd, env=ENV,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (BASE / f'{name}.log').write_text(result.stdout)
    if result.returncode != expected:
        raise RuntimeError(f'{name} failed; inspect {BASE / (name + ".log")}\n{result.stdout[-5000:]}')
    return result.stdout


def table(path):
    with open(path) as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


print(f'Synthetic smoke artifacts: {BASE}', flush=True)
(BASE / 'nextflow').symlink_to(ROOT / 'nextflow', target_is_directory=True)
rng = random.Random(23)
codons = [a+b+c for a in 'ACGT' for b in 'ACGT' for c in 'ACGT' if a+b+c not in ['TAA','TAG','TGA']]
refs = {name: ''.join(rng.choice(codons) for _ in range(150)) for name in ['refA', 'refB']}
query = refs['refA'][:225] + 'N'*60 + refs['refB'] + 'N'*60 + refs['refA'][225:]
(BASE / 'query.fa').write_text('>contig\n' + query + '\n')
(BASE / 'refs.fa').write_text(''.join(f'>{name}\n{seq}\n' for name, seq in refs.items()))
(BASE / 'proteins.fa').write_text(''.join(f'>{name}\n{Seq(seq).translate()}\n' for name, seq in refs.items()))
(BASE / 'taxids.txt').write_text('lcl|refA 11\nlcl|refB 22\n')
(BASE / 'accessions.tsv').write_text('accession\taccession.version\ttaxid\tgi\nrefA\trefA\t11\t0\nrefB\trefB\t22\t0\n')

# Minimal synthetic taxonomy; it does not represent real virus taxa.
nodes = [(1,1,'no rank','root'), (10239,1,'superkingdom','Viruses'),
         (10,10239,'family','Family_A'), (11,10,'species','Synthetic_A'),
         (20,10239,'family','Family_B'), (22,20,'species','Synthetic_B')]
parents = {node: parent for node, parent, _, _ in nodes}
with sqlite3.connect(BASE / 'taxonomy.sqlite') as db:
    db.execute('CREATE TABLE stats (version INTEGER)')
    db.execute('INSERT INTO stats VALUES (?)', (DB_VERSION,))
    db.execute('CREATE TABLE species (taxid INTEGER PRIMARY KEY, parent INTEGER, spname TEXT, common TEXT, rank TEXT, track TEXT)')
    db.execute('CREATE TABLE merged (taxid_old INTEGER, taxid_new INTEGER)')
    for node, parent, rank, name in nodes:
        lineage = [node]
        while lineage[-1] != 1:
            lineage.append(parents[lineage[-1]])
        db.execute('INSERT INTO species VALUES (?,?,?,?,?,?)', (node,parent,name,'',rank,','.join(map(str,lineage))))
(BASE / 'nodes.dmp').write_text(''.join(f'{node}\t|\t{parent}\t|\t{rank}\t|\t\t|\t0\t|\t0\t|\t1\t|\t0\t|\t0\t|\t0\t|\t0\t|\t0\t|\t\t|\n' for node,parent,rank,_ in nodes))
run(['makeblastdb','-in','refs.fa','-dbtype','nucl','-parse_seqids','-taxid_map','taxids.txt','-out','nt'], 'makeblastdb_nt')
run(['makeblastdb','-in','proteins.fa','-dbtype','prot','-parse_seqids','-taxid_map','taxids.txt','-out','nr'], 'makeblastdb_nr')
run(['diamond','makedb','--in','proteins.fa','--db','proteins','--taxonmap','accessions.tsv','--taxonnodes','nodes.dmp'], 'diamond_makedb')

# Paired reads from a separate unambiguous reference for the assembler fixture.
reference = ''.join(rng.choice('ACGT') for _ in range(1600))
reads = [[], []]
for start in range(0, 1300, 10):
    for mate, seq in enumerate([reference[start:start+100], str(Seq(reference[start+200:start+300]).reverse_complement())]):
        reads[mate].append(f'@r{start}/{mate+1}\n{seq}\n+\n' + 'I'*len(seq) + '\n')
for mate in range(2):
    (BASE / f'reads{mate+1}.fq').write_text(''.join(reads[mate]))

(BASE / 'smoke.nf').write_text('''
include { blastn as NT } from './nextflow/modules/blastn'
include { blastn_viruses as VIRUSES } from './nextflow/modules/blastn_viruses'
include { blastx as PROTEIN } from './nextflow/modules/blastx'
include { megahit as ASSEMBLER } from './nextflow/modules/megahit'
include { coverage as COVERAGE } from './nextflow/modules/coverage'
include { ORGANIZE_CONTIGS } from './nextflow/subworkflow/organize_contigs'
workflow {
    def queries = Channel.of(['sample', file(params.fasta)])
    NT(queries)
    VIRUSES(queries)
    PROTEIN(queries)
    ASSEMBLER(Channel.of(['sample', file(params.r1), file(params.r2)]))
    COVERAGE(Channel.of(['sample', file(params.fasta), file(params.r1), file(params.r2)]))
    ORGANIZE_CONTIGS(NT.out.formatted_blast_output.join(queries))
}
''')
(BASE / 'smoke.config').write_text(f'''
includeConfig '{ROOT / 'nextflow.config'}'
params.outdir = '{BASE / 'results'}'
params.fasta = '{BASE / 'query.fa'}'
params.r1 = '{BASE / 'reads1.fq'}'
params.r2 = '{BASE / 'reads2.fq'}'
params.blastdb_nt = '{BASE / 'nt'}'
params.blastdb_viruses = '{BASE / 'nt'}'
params.blastdb_nr = '{BASE / 'nr'}'
params.diamonddb = '{BASE / 'proteins.dmnd'}'
params.taxonomy_db = '{BASE / 'taxonomy.sqlite'}'
process.executor = 'local'
process.cpus = 1
process.memory = '1 GB'
process.errorStrategy = 'terminate'
trace.overwrite = true
''')
command = ['nextflow', '-c', 'smoke.config', 'run', 'smoke.nf', '-ansi-log', 'false', '-with-trace', 'trace.tsv']
run(command, 'nextflow_diamond')
for suffix in ['nt','viruses','nr']:
    best_tsv = BASE / f'results/blast_results/sample_best_hits_{suffix}.tsv'
    best_xlsx = BASE / f'results/blast_results/sample_best_hits_{suffix}.xlsx'
    summary_tsv = BASE / f'results/blast_results/details/sample_subject_summary_{suffix}.tsv'
    hsps_tsv = BASE / f'results/blast_results/details/sample_all_hsps_{suffix}.tsv'
    raw_txt = BASE / f'results/blast_results/details/sample_raw_{suffix}.txt'
    assert best_tsv.is_file() and best_xlsx.is_file() and summary_tsv.is_file(), suffix
    best_rows = table(best_tsv)
    assert len(best_rows) == 1 and best_rows[0]['sequence'], best_rows
    hits = table(hsps_tsv)
    assert len(hits) >= (2 if suffix == 'nr' else 3), (suffix, hits)
    raw_lines = raw_txt.read_text().splitlines()
    assert len(hits) == len(raw_lines), 'a reported HSP was lost'
    assert {row['subject_id'].split('|')[-1] for row in hits} == {'refA','refB'}, hits
    assert {row['family'] for row in hits} == {'Family_A','Family_B'}
    if suffix == 'nr':
        assert all(row['query_frame'] and not row['subject_strand'] for row in hits)
assert (BASE / 'results/organized_contigs/sample/needs_review/contig.fasta').exists()
assembly = BASE / 'results/megahit_assembly/sample'
assert (assembly / 'sample_metanextviro_megahit_contigs.fa').stat().st_size > 0
assert (assembly / 'intermediate_contigs').is_dir(), 'assembler intermediates were not published'

# The default publication must create independent regular files, including nested outputs.
checked = 0
for published in (BASE / 'results').rglob('*'):
    assert not published.is_symlink(), published
    if not published.is_file():
        continue
    candidates = [p for p in (BASE / 'work').rglob(published.name) if not p.is_symlink() and p.is_file()]
    assert candidates, published
    assert not any(os.path.samefile(published, candidate) for candidate in candidates), published
    checked += 1
assert checked > 10
for read_name in ['reads1.fq', 'reads2.fq']:
    staged = list((BASE / 'work').glob(f'*/*/{read_name}'))
    assert staged and all(path.is_symlink() for path in staged), staged

run(command + ['-resume'], 'nextflow_resume')
assert all(row['status'] == 'CACHED' for row in table(BASE / 'trace.tsv'))
# Hard-link publication remains an explicit option and can republish cached tasks.
run(command + ['--publish_mode', 'link', '--outdir', str(BASE / 'results_hardlinks'), '-resume'], 'nextflow_hardlinks')
for published in (BASE / 'results_hardlinks').rglob('*'):
    if published.is_file() and not published.is_symlink():
        candidates = [p for p in (BASE / 'work').rglob(published.name) if p.is_file() and not p.is_symlink()]
        assert any(os.path.samefile(published, candidate) for candidate in candidates), published
blastx_run = run(command + ['--blastx_tool','blastx','-resume'], 'nextflow_blastx')
assert len(table(BASE / 'results/blast_results/details/sample_all_hsps_nr.tsv')) >= 2

# Native coverage regression: 5 covered bases at depth 2 in a length-10 contig
# must mean depth 1, breadth 50%; a completely unused contig must remain present.
(BASE / 'tiny.sam').write_text('@HD\tVN:1.6\tSO:coordinate\n@SQ\tSN:partial\tLN:10\n@SQ\tSN:unused\tLN:10\n'
    'r1\t0\tpartial\t1\t60\t5M\t*\t0\t0\tACGTA\tIIIII\n'
    'r2\t0\tpartial\t1\t60\t5M\t*\t0\t0\tACGTA\tIIIII\n')
run(['samtools','sort','-o','tiny.bam','tiny.sam'], 'samtools_sort')
run(['samtools','index','tiny.bam'], 'samtools_index')
run(['bash',ROOT / 'bin/calculate_contig_coverage.sh','tiny.bam','coverage.tsv','idxstats.tsv'], 'coverage')
stats = {row['Contig']: row for row in table(BASE / 'coverage.tsv')}
assert float(stats['partial']['Average_Coverage']) == 1
assert float(stats['partial']['Coverage_Breadth']) == 50
assert float(stats['unused']['Average_Coverage']) == 0
assert float(stats['unused']['Coverage_Breadth']) == 0
# Compile the real pipeline entry point and exercise its storage preflight.
(BASE / 'samples.csv').write_text(f'id,reads1,reads2\nsample,{BASE}/reads1.fq,{BASE}/reads2.fq\n')
entry = ['nextflow', 'run', ROOT / 'main.nf', '--input', BASE / 'samples.csv',
         '--outdir', BASE / 'entry-results', '-ansi-log', 'false']
for assembler in ['megahit', 'metaspades', 'hybrid']:
    run(entry + ['-preview', '--assembler', assembler, '--blast_options', 'all',
                 '--organize_contigs'], f'preview_{assembler}')
run(entry + ['-preview', '--assembler', 'invalid'], 'invalid_assembler', expected=1)
run(entry + ['-preview', '--publish_mode', 'move'], 'invalid_publish_mode', expected=1)
run(entry + ['-preview', '--blast_max_target_seqs', '0'], 'invalid_subject_limit', expected=1)
skip = [f'--skip_{name}' for name in ['quality', 'trimming', 'assembly', 'blast_annotation',
        'taxonomic_profiling', 'viral_analysis', 'coverage_analysis', 'contig_organization', 'visualization']]
run(entry + skip, 'entry_storage_preflight')
assert not list((BASE / 'entry-results').glob('.metanextviro-link-check-*'))
assert not list((BASE / 'work').glob('.metanextviro-link-check-*'))
# Move an ordinary copy of the default results, then clean only this synthetic run.
# Both result trees must remain unchanged, and task execution logs must survive.
def checksums(directory):
    return {str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.rglob('*') if path.is_file()}

expected_results = checksums(BASE / 'results')
shutil.copytree(BASE / 'results', BASE / 'transferred_results')
assert checksums(BASE / 'transferred_results') == expected_results
run_name = re.search(r'Launching .*?\[([^]]+)\]', blastx_run).group(1)
cleanup = [sys.executable, ROOT / 'bin/cleanup_work.py', '--run', run_name,
           '--results', BASE / 'results', '--launch-dir', BASE]
work_bams = [path for path in (BASE / 'work').glob('*/*/sample.bam') if not path.is_symlink()]
assert work_bams
run(cleanup, 'cleanup_preview')
assert all(path.exists() for path in work_bams), 'preview removed files'
run(cleanup + ['--apply'], 'cleanup_apply')
assert all(not path.exists() for path in work_bams), 'task BAM was not cleaned'
assert list((BASE / 'work').glob('*/*/.command.sh')), 'execution logs were removed'
assert checksums(BASE / 'results') == expected_results
assert checksums(BASE / 'transferred_results') == expected_results
assert (BASE / 'reads1.fq').is_file() and (BASE / 'reads2.fq').is_file()
print(f'PASS: real MEGAHIT, BLASTN, BLASTX, DIAMOND, taxonomy, organization, resume, coverage; {checked} independent published files; opt-in hard links; transfer and log-preserving cleanup.')
print(f'Artifacts retained at {BASE}')
