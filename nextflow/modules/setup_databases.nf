// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Runs setup_databases.py on the local submission node to download, verify, and index the selected MetaNextViro reference database preset.

process setup_databases {
    tag "$db_preset"
    executor 'local'
    cpus 4

    input:
        val target_db_dir
        val db_preset

    output:
        val target_db_dir, emit: ready_db_dir
        path "database_setup_summary.txt", emit: summary

    script:
    def compArg = params.db_components ? "--components '${params.db_components}'" : ''
    def forceArg = params.db_force ? '--force' : ''
    """
    set -euo pipefail
    python3 ${workflow.projectDir}/bin/setup_databases.py \
        --db-dir "${target_db_dir}" \
        --preset "${db_preset}" \
        --threads ${task.cpus} \
        ${compArg} \
        ${forceArg} | tee database_setup_summary.txt
    """
}
