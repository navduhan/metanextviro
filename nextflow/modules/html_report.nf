// Comprehensive interactive HTML report
process html_report {
    label 'process_medium'
    publishDir "${params.outdir}/final_report", mode: 'copy', overwrite: true

    input:
        path kraken2_reports
        path fastqc_reports
        path coverage_stats
        path checkv_results
        path virfinder_full
        path virfinder_filtered

    output:
        path "final_report.html", emit: report

    shell:
    """
    #!/bin/bash
    echo '<html><head><title>MetaNextViro Report</title></head><body>' > final_report.html
    echo '<h1>MetaNextViro Analysis Report</h1>' >> final_report.html

    # FastQC Reports
    if [ -d "${fastqc_reports}" ]; then
        echo '<h2>FastQC Reports</h2><ul>' >> final_report.html
        for f in ${fastqc_reports}/*; do
            filename=\$(basename "\$f")
            echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    # Kraken2 Results
    if [ -d "${kraken2_reports}" ]; then
        echo '<h2>Kraken2 Classification</h2><ul>' >> final_report.html
        for f in ${kraken2_reports}/*; do
            filename=\$(basename "\$f")
            echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    # Coverage Stats
    if [ -f "${coverage_stats}" ]; then
        echo '<h2>Coverage Analysis</h2>' >> final_report.html
        echo '<pre>' >> final_report.html
        cat "${coverage_stats}" >> final_report.html
        echo '</pre>' >> final_report.html
    fi

    # CheckV Results
    if [ -d "${checkv_results}" ]; then
        echo '<h2>CheckV Results</h2><ul>' >> final_report.html
        for f in ${checkv_results}/*; do
            filename=\$(basename "\$f")
            echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    # VirFinder Full Results
    if [ -d "${virfinder_full}" ]; then
        echo '<h2>VirFinder Full Results</h2><ul>' >> final_report.html
        for f in ${virfinder_full}/*; do
            filename=\$(basename "\$f")
            echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    # VirFinder Filtered Results (High Confidence)
    if [ -d "${virfinder_filtered}" ]; then
        echo '<h2>VirFinder High-Confidence Results</h2><ul>' >> final_report.html
        for f in ${virfinder_filtered}/*; do
            filename=\$(basename "\$f")
            echo "<li><a href='\${filename}'>\${filename}</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    echo '</body></html>' >> final_report.html
    """
} 