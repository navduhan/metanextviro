// Author: Naveen Duhan
// Generate Cohort and Sample-Wise PDF + Standalone Interactive HTML reports

process final_report {
    tag "cohort_and_samples"
    label 'low'

    publishDir "${params.outdir}/final_report", mode: params.publish_mode, overwrite: true, failOnError: true

    input:
        val sample_ids
        path staged_files, stageAs: 'inputs/?/*'
        path logo_file
        val run_meta_b64

    output:
        path "MetaNextViro_Summary_Report.pdf", emit: cohort_pdf
        path "MetaNextViro_Summary_Report.html", emit: cohort_html
        path "per_sample/*_Viral_Report.pdf", emit: sample_pdfs
        path "per_sample/*_Viral_Report.html", emit: sample_htmls

    script:
    def sampleArgs = sample_ids.collect { sid -> "'" + sid.toString().replace("'", "'\"'\"'") + "'" }.join(' ')
    """
    set -euo pipefail

    python3 -c "import base64, pathlib; pathlib.Path('run_meta.json').write_bytes(base64.b64decode('${run_meta_b64}'))"

    python3 ${workflow.projectDir}/nextflow/bin/generate_reports.py \
        --samples ${sampleArgs} \
        --input-dir inputs \
        --output-dir . \
        --logo "${logo_file}" \
        --run-meta run_meta.json
    """
}
