// Final comprehensive HTML report - runs after all processes complete
process final_report {
    label 'process_medium'
    publishDir "${params.outdir}/final_report", mode: 'copy', overwrite: true

    input:
        path kraken2_reports
        path fastqc_reports
        path coverage_stats
        path checkv_results
        path virfinder_full
        path virfinder_filtered
        path blast_results
        path assembly_results
        path organized_dirs

    output:
        path "final_report.html", emit: report

    script:
    """
    #!/bin/bash
    set -e
    
    echo '<!DOCTYPE html>' > final_report.html
    echo '<html lang="en">' >> final_report.html
    echo '<head>' >> final_report.html
    echo '    <meta charset="UTF-8">' >> final_report.html
    echo '    <meta name="viewport" content="width=device-width, initial-scale=1.0">' >> final_report.html
    echo '    <title>MetaNextViro Final Report</title>' >> final_report.html
    echo '    <style>' >> final_report.html
    echo '        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }' >> final_report.html
    echo '        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }' >> final_report.html
    echo '        h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 15px; }' >> final_report.html
    echo '        .section { background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 5px; }' >> final_report.html
    echo '        .file-list { list-style-type: none; padding: 0; }' >> final_report.html
    echo '        .file-list li { background: white; margin: 5px 0; padding: 8px; border-radius: 3px; border-left: 3px solid #3498db; }' >> final_report.html
    echo '        .file-list a { color: #2980b9; text-decoration: none; }' >> final_report.html
    echo '        .file-list a:hover { text-decoration: underline; }' >> final_report.html
    echo '        .summary { background: #e8f4fd; padding: 15px; border-radius: 5px; margin: 10px 0; }' >> final_report.html
    echo '        .timestamp { color: #7f8c8d; font-style: italic; }' >> final_report.html
    echo '    </style>' >> final_report.html
    echo '</head>' >> final_report.html
    echo '<body>' >> final_report.html
    
    echo '<h1>🧬 MetaNextViro Analysis Report</h1>' >> final_report.html
    echo '<div class="summary">' >> final_report.html
    echo '    <p><strong>✅ Report generated after all pipeline steps completed successfully.</strong></p>' >> final_report.html
    echo '    <p class="timestamp">Generated on: $(date)</p>' >> final_report.html
    echo '</div>' >> final_report.html

    # FastQC Reports
    echo '<div class="section">' >> final_report.html
    echo '<h2>📊 Quality Control Reports (FastQC)</h2>' >> final_report.html
    if [ -n "${fastqc_reports}" ] && [ -d "${fastqc_reports}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${fastqc_reports}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../fastqc/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No FastQC reports available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # Kraken2 Results
    echo '<div class="section">' >> final_report.html
    echo '<h2>🦠 Taxonomic Classification (Kraken2)</h2>' >> final_report.html
    if [ -n "${kraken2_reports}" ] && [ -d "${kraken2_reports}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${kraken2_reports}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../kraken2_results/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No Kraken2 reports available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # Coverage Stats
    echo '<div class="section">' >> final_report.html
    echo '<h2>📈 Coverage Analysis</h2>' >> final_report.html
    if [ -n "${coverage_stats}" ] && [ -f "${coverage_stats}" ]; then
        echo '<p><strong>Coverage Statistics:</strong></p>' >> final_report.html
        echo '<pre style="background: white; padding: 10px; border-radius: 3px; overflow-x: auto;">' >> final_report.html
        head -20 "${coverage_stats}" >> final_report.html
        if [ \$(wc -l < "${coverage_stats}") -gt 20 ]; then
            echo '... (showing first 20 lines)' >> final_report.html
        fi
        echo '</pre>' >> final_report.html
        echo "<p><a href='../coverage/\$(basename ${coverage_stats})'>📄 View full coverage file</a></p>" >> final_report.html
    else
        echo '<p>No coverage statistics available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # CheckV Results
    echo '<div class="section">' >> final_report.html
    echo '<h2>🔍 Viral Genome Quality (CheckV)</h2>' >> final_report.html
    if [ -n "${checkv_results}" ] && [ -d "${checkv_results}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${checkv_results}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../checkv/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No CheckV results available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # VirFinder Full Results
    echo '<div class="section">' >> final_report.html
    echo '<h2>🦠 VirFinder Analysis - All Results</h2>' >> final_report.html
    if [ -n "${virfinder_full}" ] && [ -d "${virfinder_full}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${virfinder_full}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../virfinder/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No VirFinder full results available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # VirFinder Filtered Results (High Confidence)
    echo '<div class="section">' >> final_report.html
    echo '<h2>🎯 VirFinder Analysis - High Confidence Results</h2>' >> final_report.html
    if [ -n "${virfinder_filtered}" ] && [ -d "${virfinder_filtered}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${virfinder_filtered}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../virfinder/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No VirFinder filtered results available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # BLAST Results
    echo '<div class="section">' >> final_report.html
    echo '<h2>🔬 BLAST Annotation Results</h2>' >> final_report.html
    if [ -n "${blast_results}" ] && [ -d "${blast_results}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${blast_results}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../blast_results/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No BLAST results available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # Assembly Results
    echo '<div class="section">' >> final_report.html
    echo '<h2>🧩 Assembly Results</h2>' >> final_report.html
    if [ -n "${assembly_results}" ] && [ -d "${assembly_results}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${assembly_results}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='../assembly/\${filename}'>📄 \${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No assembly results available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    # Organized Contigs
    echo '<div class="section">' >> final_report.html
    echo '<h2>📁 Organized Contigs by Taxonomy</h2>' >> final_report.html
    if [ -n "${organized_dirs}" ] && [ -d "${organized_dirs}" ]; then
        echo '<ul class="file-list">' >> final_report.html
        for f in ${organized_dirs}/*; do
            if [ -d "\$f" ]; then
                dirname=\$(basename "\$f")
                echo "<li><strong>📂 \${dirname}</strong> - <a href='../organized_contigs/\${dirname}/'>View organized contigs</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<p>No organized contigs available.</p>' >> final_report.html
    fi
    echo '</div>' >> final_report.html

    echo '<hr style="margin: 30px 0;">' >> final_report.html
    echo '<div class="summary">' >> final_report.html
    echo '<p><em>📋 Report generated by MetaNextViro pipeline</em></p>' >> final_report.html
    echo '<p><em>🔗 For more information, visit: <a href="https://github.com/navduhan/metanextviro">https://github.com/navduhan/metanextviro</a></em></p>' >> final_report.html
    echo '</div>' >> final_report.html
    echo '</body></html>' >> final_report.html
    """
} 