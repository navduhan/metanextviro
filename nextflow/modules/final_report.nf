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

    shell:
    """
    #!/bin/bash
    set -e
    
    echo '<html><head><title>MetaNextViro Final Report</title></head><body>' > final_report.html
    echo '<h1>MetaNextViro Analysis Report</h1>' >> final_report.html
    echo '<p><strong>Report generated after all pipeline steps completed successfully.</strong></p>' >> final_report.html

    # FastQC Reports
    if [ -n "${fastqc_reports}" ] && [ -d "${fastqc_reports}" ]; then
        echo '<h2>FastQC Reports</h2><ul>' >> final_report.html
        for f in ${fastqc_reports}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>FastQC Reports</h2><p>No FastQC reports available.</p>' >> final_report.html
    fi

    # Kraken2 Results
    if [ -n "${kraken2_reports}" ] && [ -d "${kraken2_reports}" ]; then
        echo '<h2>Kraken2 Classification</h2><ul>' >> final_report.html
        for f in ${kraken2_reports}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>Kraken2 Classification</h2><p>No Kraken2 reports available.</p>' >> final_report.html
    fi

    # Coverage Stats
    if [ -n "${coverage_stats}" ] && [ -f "${coverage_stats}" ]; then
        echo '<h2>Coverage Analysis</h2>' >> final_report.html
        echo '<pre>' >> final_report.html
        cat "${coverage_stats}" >> final_report.html
        echo '</pre>' >> final_report.html
    else
        echo '<h2>Coverage Analysis</h2><p>No coverage statistics available.</p>' >> final_report.html
    fi

    # CheckV Results
    if [ -n "${checkv_results}" ] && [ -d "${checkv_results}" ]; then
        echo '<h2>CheckV Results</h2><ul>' >> final_report.html
        for f in ${checkv_results}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>CheckV Results</h2><p>No CheckV results available.</p>' >> final_report.html
    fi

    # VirFinder Full Results
    if [ -n "${virfinder_full}" ] && [ -d "${virfinder_full}" ]; then
        echo '<h2>VirFinder Full Results</h2><ul>' >> final_report.html
        for f in ${virfinder_full}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>VirFinder Full Results</h2><p>No VirFinder full results available.</p>' >> final_report.html
    fi

    # VirFinder Filtered Results (High Confidence)
    if [ -n "${virfinder_filtered}" ] && [ -d "${virfinder_filtered}" ]; then
        echo '<h2>VirFinder High-Confidence Results</h2><ul>' >> final_report.html
        for f in ${virfinder_filtered}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>VirFinder High-Confidence Results</h2><p>No VirFinder filtered results available.</p>' >> final_report.html
    fi

    # BLAST Results
    if [ -n "${blast_results}" ] && [ -d "${blast_results}" ]; then
        echo '<h2>BLAST Annotation Results</h2><ul>' >> final_report.html
        for f in ${blast_results}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>BLAST Annotation Results</h2><p>No BLAST results available.</p>' >> final_report.html
    fi

    # Assembly Results
    if [ -n "${assembly_results}" ] && [ -d "${assembly_results}" ]; then
        echo '<h2>Assembly Results</h2><ul>' >> final_report.html
        for f in ${assembly_results}/*; do
            if [ -f "\$f" ]; then
                filename=\$(basename "\$f")
                echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>Assembly Results</h2><p>No assembly results available.</p>' >> final_report.html
    fi

    # Organized Contigs
    if [ -n "${organized_dirs}" ] && [ -d "${organized_dirs}" ]; then
        echo '<h2>Organized Contigs by Taxonomy</h2><ul>' >> final_report.html
        for f in ${organized_dirs}/*; do
            if [ -d "\$f" ]; then
                dirname=\$(basename "\$f")
                echo "<li><strong>\${dirname}</strong> - <a href='\${dirname}/'>View directory</a></li>" >> final_report.html
            fi
        done
        echo '</ul>' >> final_report.html
    else
        echo '<h2>Organized Contigs by Taxonomy</h2><p>No organized contigs available.</p>' >> final_report.html
    fi

    echo '<hr>' >> final_report.html
    echo '<p><em>Report generated by MetaNextViro pipeline</em></p>' >> final_report.html
    echo '</body></html>' >> final_report.html
    """
} 