#!/usr/bin/env python3
# Author: Naveen Duhan
# License: MIT (see LICENSE)
"""Downloads, verifies checksums, and indexes MetaNextViro reference databases across four storage presets. Writes ready-to-use Nextflow database configuration, YAML parameter files, and a JSON manifest."""

import argparse
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

NCBI_TAXDUMP_URL = 'https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz'
NCBI_TAXDUMP_MD5_URL = 'https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz.md5'
NCBI_REFSEQ_VIRAL_DIR_URL = 'https://ftp.ncbi.nlm.nih.gov/refseq/release/viral/'
VOG_BASE_URLS = [
    'https://fileshare.lisc.univie.ac.at/vog/latest',
    'https://fileshare.csb.univie.ac.at/vog/latest',
]
KRAKEN2_BUCKET_LIST_URL = 'https://genome-idx.s3.amazonaws.com/?prefix=kraken/k2_viral_'
KRAKEN2_FALLBACK_URL = 'https://genome-idx.s3.amazonaws.com/kraken/k2_viral_20240605.tar.gz'
CHECKV_ZENODO_URL = 'https://zenodo.org/records/15949601/files/checkv-db-v1.5.tar.gz?download=1'
GENOMAD_ZENODO_URL = 'https://zenodo.org/records/14886553/files/genomad_db_v1.9.tar.gz?download=1'

ALL_COMPONENTS = [
    'taxonomy',
    'refseq_viral_blastn',
    'nt_viruses',
    'refseq_viral_protein',
    'vog_hmm',
    'kraken2_viral',
    'checkv',
    'genomad',
]

PRESETS = {
    'full_viral': [
        'taxonomy',
        'refseq_viral_blastn',
        'refseq_viral_protein',
        'vog_hmm',
        'kraken2_viral',
        'checkv',
        'genomad',
    ],
    'minimal': [
        'taxonomy',
        'refseq_viral_blastn',
        'refseq_viral_protein',
        'vog_hmm',
        'kraken2_viral',
    ],
    'discovery_only': [
        'taxonomy',
        'refseq_viral_protein',
        'vog_hmm',
    ],
    'genbank_complete': [
        'taxonomy',
        'nt_viruses',
        'refseq_viral_protein',
        'vog_hmm',
        'kraken2_viral',
        'checkv',
        'genomad',
    ],
}

COMPONENT_INFO = {
    'taxonomy': {
        'approx_size': '~65 MB download',
        'description': 'NCBI taxdump + local ETE3 taxa.sqlite + nodes.dmp/names.dmp',
        'required_bins': [],
    },
    'refseq_viral_blastn': {
        'approx_size': '~180 MB download',
        'description': 'NCBI RefSeq viral genomic nucleotide BLAST database (with taxids)',
        'required_bins': ['makeblastdb'],
    },
    'nt_viruses': {
        'approx_size': '~12-18 GB download',
        'description': 'Full NCBI GenBank nt_viruses BLAST database via update_blastdb.pl',
        'required_bins': ['update_blastdb.pl'],
    },
    'refseq_viral_protein': {
        'approx_size': '~160 MB download',
        'description': 'NCBI RefSeq viral protein DIAMOND DB (with taxids) + phylogeny hallmark refs',
        'required_bins': ['diamond'],
    },
    'vog_hmm': {
        'approx_size': '~150 MB download',
        'description': 'VOGDB viral profile-HMM database + LCA taxonomic lineage mapping table',
        'required_bins': [],
    },
    'kraken2_viral': {
        'approx_size': '~550 MB download',
        'description': 'Pre-built Kraken2 RefSeq viral index (k2_viral)',
        'required_bins': [],
    },
    'checkv': {
        'approx_size': '~1.5 GB download',
        'description': 'CheckV viral genome completeness & contamination database',
        'required_bins': [],
    },
    'genomad': {
        'approx_size': '~1.4 GB download',
        'description': 'geNomad marker + neural network virus/plasmid database',
        'required_bins': [],
    },
}

BRACKET_ORG_RE = re.compile(r'\[([^\[\]]+)\]\s*$')
HALLMARK_KEYWORDS = (
    'rna-dependent rna polymerase', 'rdrp', 'replicase', 'capsid',
    'coat protein', 'major capsid', 'terminase large', 'polyprotein'
)


def fetch_text(url, timeout=60):
    req = urllib.request.Request(url, headers={'User-Agent': 'MetaNextViro-DB-Setup/1.0'})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode('utf-8', errors='replace')


def download_file(url, dest_path, retries=3, expected_md5=None):
    dest = Path(dest_path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_file() and dest.stat().st_size > 0:
        if not expected_md5 or compute_hash(dest, 'md5') == expected_md5:
            print(f'  [cached] {dest.name}')
            return dest

    part = dest.with_suffix(dest.suffix + '.part')
    last_err = None
    for attempt in range(1, retries + 1):
        try:
            print(f'  [download {attempt}/{retries}] {url} -> {dest.name}')
            req = urllib.request.Request(url, headers={'User-Agent': 'MetaNextViro-DB-Setup/1.0'})
            with urllib.request.urlopen(req, timeout=180) as resp, open(part, 'wb') as out:
                shutil.copyfileobj(resp, out, length=1024 * 1024)
            if expected_md5:
                actual_md5 = compute_hash(part, 'md5')
                if actual_md5 != expected_md5:
                    part.unlink(missing_ok=True)
                    raise RuntimeError(f'MD5 mismatch for {dest.name}: expected {expected_md5}, got {actual_md5}')
            part.replace(dest)
            return dest
        except Exception as exc:
            last_err = exc
            part.unlink(missing_ok=True)
            if attempt < retries:
                time.sleep(2 * attempt)
    raise RuntimeError(f'Failed to download {url}: {last_err}')


def compute_hash(path, algo='sha256'):
    h = hashlib.new(algo)
    with open(path, 'rb') as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def run_cmd(cmd, cwd=None):
    str_cmd = [str(x) for x in cmd]
    print(f'  [exec] {" ".join(str_cmd)}')
    subprocess.run(str_cmd, cwd=cwd, check=True)


def check_required_binaries(components):
    missing = []
    for comp in components:
        for binary in COMPONENT_INFO[comp]['required_bins']:
            if shutil.which(binary) is None:
                missing.append((comp, binary))
    if missing:
        details = ', '.join(f'{binary} (needed by {comp})' for comp, binary in missing)
        raise RuntimeError(
            f'Missing required executables on PATH: {details}. '
            'Activate your Conda/container environment first or exclude those components.'
        )


def resolve_selected_components(preset, components_arg):
    if components_arg:
        selected = [c.strip() for c in components_arg.split(',') if c.strip()]
        invalid = [c for c in selected if c not in ALL_COMPONENTS]
        if invalid:
            raise ValueError(f'Unknown component(s): {invalid}. Valid options: {ALL_COMPONENTS}')
    else:
        selected = list(PRESETS[preset])

    # Ensure taxonomy is built first whenever RefSeq BLASTN or RefSeq DIAMOND is requested
    if any(c in selected for c in ('refseq_viral_blastn', 'refseq_viral_protein')) and 'taxonomy' not in selected:
        selected.insert(0, 'taxonomy')
    return selected


def discover_refseq_viral_urls(pattern):
    html = fetch_text(NCBI_REFSEQ_VIRAL_DIR_URL)
    filenames = sorted(set(re.findall(pattern, html)))
    if not filenames:
        raise RuntimeError(f'No files matching {pattern} found at {NCBI_REFSEQ_VIRAL_DIR_URL}')
    return [NCBI_REFSEQ_VIRAL_DIR_URL + name for name in filenames]


def discover_latest_kraken2_viral_url():
    try:
        xml_text = fetch_text(KRAKEN2_BUCKET_LIST_URL)
        keys = sorted(set(re.findall(r'kraken/k2_viral_\d{8}\.tar\.gz', xml_text)))
        if keys:
            return f'https://genome-idx.s3.amazonaws.com/{keys[-1]}'
    except Exception:
        pass
    return KRAKEN2_FALLBACK_URL


def load_ncbi_name_to_taxid(names_dmp_path):
    """Map lowercased NCBI scientific and synonym names to taxids from names.dmp."""
    scientific = {}
    fallback = {}
    with open(names_dmp_path, encoding='utf-8', errors='replace') as handle:
        for line in handle:
            parts = [p.strip() for p in line.split('|')]
            if len(parts) < 4 or not parts[0].isdigit():
                continue
            tid = int(parts[0])
            name_lc = parts[1].lower()
            name_class = parts[3]
            if name_class == 'scientific name':
                scientific[name_lc] = tid
            elif name_class in ('equivalent name', 'synonym', 'genbank common name', 'acronym'):
                fallback.setdefault(name_lc, tid)
    fallback.update(scientific)
    return fallback


def lookup_organism_taxid(org_name, name_to_taxid, default_taxid=10239):
    if not org_name:
        return default_taxid
    clean = org_name.strip()
    candidates = [
        clean.lower(),
        re.split(r'\b(?:isolate|strain|segment|complete|partial|chromosome|genomic)\b|,', clean, maxsplit=1)[0].strip().lower(),
    ]
    tokens = clean.split()
    if len(tokens) >= 3:
        candidates.append(' '.join(tokens[:3]).lower())
    if len(tokens) >= 2:
        candidates.append(' '.join(tokens[:2]).lower())
    for cand in candidates:
        if cand and cand in name_to_taxid:
            return name_to_taxid[cand]
    return default_taxid


def setup_taxonomy(db_dir, force=False):
    tax_dir = db_dir / 'taxonomy'
    sqlite_path = tax_dir / 'taxa.sqlite'
    nodes_path = tax_dir / 'nodes.dmp'
    names_path = tax_dir / 'names.dmp'
    if not force and sqlite_path.is_file() and nodes_path.is_file() and names_path.is_file():
        print('[taxonomy] Already built; skipping.')
        return sqlite_path

    tax_dir.mkdir(parents=True, exist_ok=True)
    md5_text = fetch_text(NCBI_TAXDUMP_MD5_URL).strip().split()[0]
    tar_path = download_file(NCBI_TAXDUMP_URL, tax_dir / 'taxdump.tar.gz', expected_md5=md5_text)

    with tarfile.open(tar_path, 'r:gz') as tar:
        for member_name in ('nodes.dmp', 'names.dmp', 'merged.dmp'):
            member = tar.getmember(member_name)
            member.name = Path(member.name).name
            tar.extract(member, path=tax_dir)

    try:
        from ete3 import NCBITaxa
        print('  [build] Building local ETE3 SQLite taxonomy database...')
        NCBITaxa(dbfile=str(sqlite_path), taxdump_file=str(tar_path), update=False)
    except ImportError:
        print('  [warn] ete3 not installed in current Python; extracted nodes.dmp/names.dmp only.')

    return sqlite_path


def setup_refseq_viral_blastn(db_dir, threads=4, force=False):
    out_dir = db_dir / 'blast_viruses'
    db_prefix = out_dir / 'refseq_viral_genomic'
    marker = out_dir / '.completed'
    if not force and marker.is_file():
        print('[refseq_viral_blastn] Already built; skipping.')
        return db_prefix

    out_dir.mkdir(parents=True, exist_ok=True)
    urls = discover_refseq_viral_urls(r'viral\.\d+\.1\.genomic\.fna\.gz')
    names_dmp = db_dir / 'taxonomy/names.dmp'
    name_to_taxid = load_ncbi_name_to_taxid(names_dmp) if names_dmp.is_file() else {}

    combined_fna = out_dir / 'refseq_viral_genomic.fna'
    taxid_map = out_dir / 'nucl_taxid_map.txt'
    seen_ids = set()

    with open(combined_fna, 'w') as fna_out, open(taxid_map, 'w') as map_out:
        for url in urls:
            gz_path = download_file(url, out_dir / Path(url).name)
            with gzip.open(gz_path, 'rt', encoding='utf-8', errors='replace') as gz_in:
                for line in gz_in:
                    if line.startswith('>'):
                        parts = line[1:].strip().split(None, 1)
                        seq_id = parts[0]
                        if seq_id in seen_ids:
                            skip = True
                            continue
                        skip = False
                        seen_ids.add(seq_id)
                        desc = parts[1] if len(parts) > 1 else ''
                        tid = lookup_organism_taxid(desc, name_to_taxid, default_taxid=10239)
                        map_out.write(f'{seq_id} {tid}\n')
                        fna_out.write(line)
                    elif not skip:
                        fna_out.write(line)

    run_cmd([
        'makeblastdb',
        '-in', combined_fna,
        '-dbtype', 'nucl',
        '-parse_seqids',
        '-taxid_map', taxid_map,
        '-out', db_prefix,
    ])
    combined_fna.unlink(missing_ok=True)
    marker.write_text(datetime.now(timezone.utc).isoformat() + '\n')
    return db_prefix


def setup_nt_viruses(db_dir, threads=4, force=False):
    out_dir = db_dir / 'nt_viruses'
    marker = out_dir / '.completed'
    if not force and marker.is_file():
        print('[nt_viruses] Already downloaded; skipping.')
        return out_dir / 'nt_viruses'
    out_dir.mkdir(parents=True, exist_ok=True)
    run_cmd(['update_blastdb.pl', '--decompress', '--num_threads', str(threads), 'nt_viruses'], cwd=out_dir)
    marker.write_text(datetime.now(timezone.utc).isoformat() + '\n')
    return out_dir / 'nt_viruses'


def setup_refseq_viral_protein(db_dir, threads=4, force=False):
    out_dir = db_dir / 'viral_proteins'
    dmnd_path = out_dir / 'refseq_viral_proteins.dmnd'
    refs_faa = out_dir / 'refseq_hallmark_refs.faa'
    if not force and dmnd_path.is_file() and refs_faa.is_file():
        print('[refseq_viral_protein] Already built; skipping.')
        return dmnd_path, refs_faa

    out_dir.mkdir(parents=True, exist_ok=True)
    urls = discover_refseq_viral_urls(r'viral\.\d+\.protein\.faa\.gz')
    tax_dir = db_dir / 'taxonomy'
    names_dmp = tax_dir / 'names.dmp'
    nodes_dmp = tax_dir / 'nodes.dmp'
    name_to_taxid = load_ncbi_name_to_taxid(names_dmp) if names_dmp.is_file() else {}

    combined_faa = out_dir / 'refseq_viral_proteins.faa'
    acc2taxid = out_dir / 'prot.accession2taxid'
    seen_ids = set()
    kept_refs_per_taxon = {}

    with open(combined_faa, 'w') as faa_out, open(acc2taxid, 'w') as map_out, open(refs_faa, 'w') as ref_out:
        map_out.write('accession\taccession.version\ttaxid\tgi\n')
        write_current_ref = False
        skip = False
        for url in urls:
            gz_path = download_file(url, out_dir / Path(url).name)
            with gzip.open(gz_path, 'rt', encoding='utf-8', errors='replace') as gz_in:
                for line in gz_in:
                    if line.startswith('>'):
                        header = line[1:].strip()
                        acc_ver = header.split()[0]
                        if acc_ver in seen_ids:
                            skip = True
                            write_current_ref = False
                            continue
                        skip = False
                        seen_ids.add(acc_ver)
                        acc_base = acc_ver.split('.')[0]
                        org_match = BRACKET_ORG_RE.search(header)
                        org_name = org_match.group(1) if org_match else ''
                        tid = lookup_organism_taxid(org_name, name_to_taxid, default_taxid=10239)
                        map_out.write(f'{acc_base}\t{acc_ver}\t{tid}\t0\n')
                        faa_out.write(line)

                        header_lc = header.lower()
                        if any(k in header_lc for k in HALLMARK_KEYWORDS) and kept_refs_per_taxon.get(tid, 0) < 1 and len(kept_refs_per_taxon) < 500:
                            kept_refs_per_taxon[tid] = kept_refs_per_taxon.get(tid, 0) + 1
                            write_current_ref = True
                            ref_out.write(line)
                        else:
                            write_current_ref = False
                    else:
                        if not skip:
                            faa_out.write(line)
                        if write_current_ref:
                            ref_out.write(line)

    cmd = [
        'diamond', 'makedb',
        '--in', combined_faa,
        '--db', out_dir / 'refseq_viral_proteins',
        '--threads', str(threads),
    ]
    if nodes_dmp.is_file() and names_dmp.is_file():
        cmd.extend(['--taxonmap', acc2taxid, '--taxonnodes', nodes_dmp, '--taxonnames', names_dmp])
    run_cmd(cmd)
    combined_faa.unlink(missing_ok=True)
    return dmnd_path, refs_faa


def merge_vog_taxonomy_tables(annotations_gz, lca_gz, output_tsv):
    """Merge VOGDB functional annotations and LCA taxonomic lineages into one lookup TSV."""
    annotations = {}
    with gzip.open(annotations_gz, 'rt', encoding='utf-8', errors='replace') as handle:
        for line in handle:
            if not line.strip() or line.startswith('#'):
                parts = line.lstrip('#').strip().split('\t')
                continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 5:
                # GroupName, ProteinCount, SpeciesCount, FunctionalCategory, ConsensusFunctionalDescription
                annotations[parts[0].strip()] = (parts[3].strip(), parts[4].strip())

    lcas = {}
    with gzip.open(lca_gz, 'rt', encoding='utf-8', errors='replace') as handle:
        for line in handle:
            if not line.strip() or line.startswith('#'):
                continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 2:
                # GroupName, ..., LastCommonAncestor (last column holds semicolon lineage)
                lcas[parts[0].strip()] = parts[-1].strip()

    all_groups = sorted(set(annotations) | set(lcas))
    with open(output_tsv, 'w', newline='') as out:
        out.write('hmm_name\tfunctional_category\tdescription\tlca_lineage\n')
        for grp in all_groups:
            func_cat, desc = annotations.get(grp, ('', ''))
            lca = lcas.get(grp, '')
            out.write(f'{grp}\t{func_cat}\t{desc}\t{lca}\n')


def setup_vog_hmm(db_dir, force=False):
    out_dir = db_dir / 'viral_hmm'
    hmm_path = out_dir / 'vog_hallmarks.hmm'
    tax_tsv = out_dir / 'vog_hmm_taxonomy.tsv'
    if not force and hmm_path.is_file() and tax_tsv.is_file():
        print('[vog_hmm] Already built; skipping.')
        return hmm_path, tax_tsv

    out_dir.mkdir(parents=True, exist_ok=True)
    last_err = None
    for base_url in VOG_BASE_URLS:
        try:
            hmm_tar = download_file(f'{base_url}/vog.hmm.tar.gz', out_dir / 'vog.hmm.tar.gz')
            ann_gz = download_file(f'{base_url}/vog.annotations.tsv.gz', out_dir / 'vog.annotations.tsv.gz')
            lca_gz = download_file(f'{base_url}/vog.lca.tsv.gz', out_dir / 'vog.lca.tsv.gz')
            break
        except Exception as exc:
            last_err = exc
    else:
        raise RuntimeError(f'Could not download VOGDB files from mirrors: {last_err}')

    print('  [build] Concatenating VOG HMMER3 profiles into vog_hallmarks.hmm...')
    with tarfile.open(hmm_tar, 'r:gz') as tar, open(hmm_path, 'wb') as hmm_out:
        for member in tar:
            if member.isfile() and member.name.endswith('.hmm'):
                extracted = tar.extractfile(member)
                if extracted is not None:
                    shutil.copyfileobj(extracted, hmm_out)

    merge_vog_taxonomy_tables(ann_gz, lca_gz, tax_tsv)
    if shutil.which('hmmpress'):
        run_cmd(['hmmpress', '-f', hmm_path])
    return hmm_path, tax_tsv


def setup_kraken2_viral(db_dir, force=False):
    out_dir = db_dir / 'kraken2_viral'
    if not force and (out_dir / 'hash.k2d').is_file() and (out_dir / 'taxo.k2d').is_file():
        print('[kraken2_viral] Already extracted; skipping.')
        return out_dir

    out_dir.mkdir(parents=True, exist_ok=True)
    url = discover_latest_kraken2_viral_url()
    tar_path = download_file(url, out_dir / Path(url).name)
    with tarfile.open(tar_path, 'r:gz') as tar:
        for member in tar.getmembers():
            if member.isfile():
                member.name = Path(member.name).name
                tar.extract(member, path=out_dir)
    return out_dir


def setup_checkv(db_dir, force=False):
    out_dir = db_dir / 'checkv'
    if not force and any(out_dir.rglob('checkv_reps.dmnd')):
        print('[checkv] Already downloaded; skipping.')
        return next(out_dir.rglob('checkv_reps.dmnd')).parent.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    if shutil.which('checkv'):
        try:
            run_cmd(['checkv', 'download_database', out_dir])
            dmnd = next(out_dir.rglob('checkv_reps.dmnd'), None)
            if dmnd:
                return dmnd.parent.parent
        except Exception as exc:
            print(f'  [warn] checkv CLI download failed ({exc}); falling back to Zenodo HTTPS mirror...')

    tar_path = download_file(CHECKV_ZENODO_URL, out_dir / 'checkv-db-v1.5.tar.gz')
    with tarfile.open(tar_path, 'r:gz') as tar:
        tar.extractall(path=out_dir)
    faa = next(out_dir.rglob('checkv_reps.faa'), None)
    dmnd = next(out_dir.rglob('checkv_reps.dmnd'), None)
    if faa and not dmnd and shutil.which('diamond'):
        run_cmd(['diamond', 'makedb', '--in', faa, '--db', faa.with_suffix('')])
    dmnd = next(out_dir.rglob('checkv_reps.dmnd'), None)
    return dmnd.parent.parent if dmnd else out_dir


def setup_genomad(db_dir, force=False):
    out_dir = db_dir / 'genomad'
    existing = next(out_dir.glob('genomad_db*'), None)
    if not force and existing and existing.is_dir():
        print('[genomad] Already downloaded; skipping.')
        return existing
    out_dir.mkdir(parents=True, exist_ok=True)
    if shutil.which('genomad'):
        try:
            run_cmd(['genomad', 'download-database', out_dir])
            found = next(out_dir.glob('genomad_db*'), None)
            if found and found.is_dir():
                return found
        except Exception as exc:
            print(f'  [warn] genomad CLI download failed ({exc}); falling back to Zenodo HTTPS archive...')

    tar_path = download_file(GENOMAD_ZENODO_URL, out_dir / 'genomad_db_v1.9.tar.gz')
    with tarfile.open(tar_path, 'r:gz') as tar:
        tar.extractall(path=out_dir)
    return next(out_dir.glob('genomad_db*'), out_dir / 'genomad_db')


def detect_installed_paths(db_dir):
    """Inspect db_dir and collect all installed database paths for Nextflow configuration."""
    db_dir = db_dir.resolve()
    params = {}
    if (db_dir / 'taxonomy/taxa.sqlite').is_file():
        params['taxonomy_db'] = str(db_dir / 'taxonomy/taxa.sqlite')
    if (db_dir / 'nt_viruses/.completed').is_file():
        params['blastdb_viruses'] = str(db_dir / 'nt_viruses/nt_viruses')
    elif (db_dir / 'blast_viruses/.completed').is_file():
        params['blastdb_viruses'] = str(db_dir / 'blast_viruses/refseq_viral_genomic')
    if (db_dir / 'kraken2_viral/hash.k2d').is_file():
        params['kraken2_db'] = str(db_dir / 'kraken2_viral')
    if (db_dir / 'viral_proteins/refseq_viral_proteins.dmnd').is_file():
        params['viral_protein_db'] = str(db_dir / 'viral_proteins/refseq_viral_proteins.dmnd')
    if (db_dir / 'viral_proteins/refseq_hallmark_refs.faa').is_file():
        params['phylo_reference_faa'] = str(db_dir / 'viral_proteins/refseq_hallmark_refs.faa')
    if (db_dir / 'viral_hmm/vog_hallmarks.hmm').is_file():
        params['viral_hmm_db'] = str(db_dir / 'viral_hmm/vog_hallmarks.hmm')
    if (db_dir / 'viral_hmm/vog_hmm_taxonomy.tsv').is_file():
        params['viral_hmm_taxonomy'] = str(db_dir / 'viral_hmm/vog_hmm_taxonomy.tsv')
    cv_dmnd = next((db_dir / 'checkv').rglob('checkv_reps.dmnd'), None) if (db_dir / 'checkv').is_dir() else None
    if cv_dmnd:
        params['checkv_db'] = str(cv_dmnd.parent.parent)
    gm_dir = next((db_dir / 'genomad').glob('genomad_db*'), None) if (db_dir / 'genomad').is_dir() else None
    if gm_dir and gm_dir.is_dir():
        params['genomad_db'] = str(gm_dir)
    return params


def write_database_configs(db_dir):
    params = detect_installed_paths(db_dir)
    cfg_path = db_dir / 'databases.config'
    yml_path = db_dir / 'databases_params.yml'
    manifest_path = db_dir / 'database_manifest.json'

    cfg_lines = [
        '// Auto-generated by bin/setup_databases.py',
        '// Pass to Nextflow with: nextflow run main.nf -c ' + str(cfg_path.resolve()),
        'params {',
    ]
    yml_lines = ['# Auto-generated by bin/setup_databases.py']
    for key, val in params.items():
        escaped = val.replace("'", "\\'")
        cfg_lines.append(f"    {key} = '{escaped}'")
        yml_lines.append(f'{key}: "{val}"')
    cfg_lines.append('}')

    cfg_path.write_text('\n'.join(cfg_lines) + '\n')
    yml_path.write_text('\n'.join(yml_lines) + '\n')
    manifest_path.write_text(json.dumps({
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'db_dir': str(db_dir.resolve()),
        'params': params,
    }, indent=2) + '\n')
    return cfg_path, yml_path, params


def main():
    parser = argparse.ArgumentParser(
        description='Download and build minimal reference databases for MetaNextViro.'
    )
    parser.add_argument(
        '-d', '--db-dir', required=True,
        help='Target directory where databases and databases.config will be stored'
    )
    parser.add_argument(
        '--preset', choices=sorted(PRESETS.keys()), default='full_viral',
        help='Database bundle preset: full_viral (~4.0 GB, default), minimal (~1.1 GB), discovery_only (~375 MB), or genbank_complete (~18-20 GB)'
    )
    parser.add_argument(
        '--components',
        help=f'Comma-separated override list of components ({",".join(ALL_COMPONENTS)})'
    )
    parser.add_argument('-t', '--threads', type=int, default=4, help='Threads for database indexing (default: 4)')
    parser.add_argument('--force', action='store_true', help='Rebuild components even if already present')
    parser.add_argument('--dry-run', action='store_true', help='Show planned components and sizes without downloading')
    args = parser.parse_args()

    db_dir = Path(args.db_dir).expanduser().resolve()
    selected = resolve_selected_components(args.preset, args.components)

    print(f'MetaNextViro Database Setup -> {db_dir}')
    print('=' * 68)
    for comp in selected:
        info = COMPONENT_INFO[comp]
        bins = ', '.join(info['required_bins']) or 'python stdlib'
        print(f'  * {comp:<22} ({info["approx_size"]}) - {info["description"]} [requires: {bins}]')
    print('=' * 68)

    if args.dry_run:
        print('Dry run only (--dry-run); no files downloaded.')
        return

    check_required_binaries(selected)
    db_dir.mkdir(parents=True, exist_ok=True)

    for comp in selected:
        print(f'\n>>> Setting up [{comp}]...')
        if comp == 'taxonomy':
            setup_taxonomy(db_dir, force=args.force)
        elif comp == 'refseq_viral_blastn':
            setup_refseq_viral_blastn(db_dir, threads=args.threads, force=args.force)
        elif comp == 'nt_viruses':
            setup_nt_viruses(db_dir, threads=args.threads, force=args.force)
        elif comp == 'refseq_viral_protein':
            setup_refseq_viral_protein(db_dir, threads=args.threads, force=args.force)
        elif comp == 'vog_hmm':
            setup_vog_hmm(db_dir, force=args.force)
        elif comp == 'kraken2_viral':
            setup_kraken2_viral(db_dir, force=args.force)
        elif comp == 'checkv':
            setup_checkv(db_dir, force=args.force)
        elif comp == 'genomad':
            setup_genomad(db_dir, force=args.force)

    cfg_path, yml_path, params = write_database_configs(db_dir)
    print('\nDatabase setup complete!')
    print(f'  Nextflow config: {cfg_path}')
    print(f'  Params YAML:     {yml_path}')
    print('\nExample commands using these databases:')
    print(f'  # Fast known-virus run:')
    print(f'  nextflow run main.nf -c {cfg_path} --input samplesheet.csv')
    print(f'  # VirFinder + Novel Virus Discovery (with automatic Order/Family assignment):')
    print(f'  nextflow run main.nf -c {cfg_path} --input samplesheet.csv --discover_novel_viruses --run_virfinder')


if __name__ == '__main__':
    main()
