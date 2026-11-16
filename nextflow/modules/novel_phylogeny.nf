// Optional phylogenetic placement of novel candidate ORFs with MAFFT + FastTree / IQ-TREE
process novel_phylogeny {
    tag "$id"
    label 'medium'

    publishDir "${params.outdir}/novel_virus_detection/phylogeny", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        tuple val(id), path(novel_orfs_faa)

    output:
        tuple val(id), path("${id}_phylogeny*"), emit: phylo_outputs

    script:
    def refFaa = file(params.phylo_reference_faa).toAbsolutePath().toString()
    """
    set -euo pipefail

    if [ ! -s "${novel_orfs_faa}" ] || ! grep -q '^>' "${novel_orfs_faa}"; then
        echo "No promoted novel candidate ORFs for sample ${id}; phylogenetic inference skipped." > ${id}_phylogeny_skipped.txt
        exit 0
    fi

    python3 - "${novel_orfs_faa}" "${refFaa}" "${id}_phylogeny_combined.faa" << 'PYEOF'
import re
import sys
from Bio import SeqIO

cand_path, ref_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
seen = set()
records = []

for prefix_tag, path in [("CAND", cand_path), ("REF", ref_path)]:
    for rec in SeqIO.parse(path, "fasta"):
        seq_clean = str(rec.seq).replace("*", "").strip()
        if not seq_clean:
            continue
        safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{prefix_tag}_{rec.id}")
        base_id = safe_id
        idx = 2
        while safe_id in seen:
            safe_id = f"{base_id}_{idx}"
            idx += 1
        seen.add(safe_id)
        rec.id = safe_id
        rec.description = ""
        rec.seq = rec.seq.__class__(seq_clean)
        records.append(rec)

if len(records) < 4:
    sys.exit(2)

with open(out_path, "w") as handle:
    SeqIO.write(records, handle, "fasta")
PYEOF

    STATUS=\$?
    if [ "\$STATUS" -eq 2 ]; then
        echo "Fewer than 4 total protein sequences available for sample ${id}; phylogenetic tree requires >= 4 sequences." > ${id}_phylogeny_skipped.txt
        exit 0
    fi

    mafft --auto --thread ${task.cpus} --inputorder ${id}_phylogeny_combined.faa > ${id}_phylogeny_aligned.faa

    if [ "${params.phylo_tool}" = "iqtree" ]; then
        IQTREE_BIN=\$(command -v iqtree3 || command -v iqtree2 || command -v iqtree)
        "\$IQTREE_BIN" \
            -s ${id}_phylogeny_aligned.faa \
            -st AA \
            -m MFP \
            -B 1000 \
            --alrt 1000 \
            --seed 42 \
            -T ${task.cpus} \
            --prefix ${id}_phylogeny
    else
        FASTTREE_BIN=\$(command -v FastTree || command -v fasttree)
        "\$FASTTREE_BIN" -lg -gamma ${id}_phylogeny_aligned.faa > ${id}_phylogeny.tree
    fi
    """
}
