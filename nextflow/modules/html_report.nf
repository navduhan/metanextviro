// Comprehensive interactive HTML report
process html_report {
    label 'process_medium'
    publishDir "${params.outdir}/final_report", mode: 'copy', overwrite: true

    input:
        path kraken2_reports
        path multiqc_report
        path coverage_plots
        path heatmap
        path checkv_results optional true
        path virfinder_results optional true

    output:
        path "final_report.html", emit: report

    shell:
    """
    #!/bin/bash
    echo '<html><head><title>MetaNextViro Report</title></head><body>' > final_report.html
    echo '<h1>MetaNextViro Analysis Report</h1>' >> final_report.html

    # MultiQC Report
    if [ -f "${multiqc_report}" ]; then
        echo '<h2>MultiQC Report</h2>' >> final_report.html
        echo '<iframe src="multiqc_report.html" width="100%" height="800px"></iframe>' >> final_report.html
    fi

    # Kraken2 Results
    if [ -d "${kraken2_reports}" ]; then
        echo '<h2>Kraken2 Classification</h2><ul>' >> final_report.html
        for f in ${kraken2_reports}/*; do
            echo "<li><a href='$f'>$(basename $f)</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    # Coverage Plots
    if [ -d "${coverage_plots}" ]; then
        echo '<h2>Coverage Analysis</h2><ul>' >> final_report.html
        for f in ${coverage_plots}/*; do
            echo "<li><a href='$f'>$(basename $f)</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    # Heatmap
    if [ -f "${heatmap}" ]; then
        echo '<h2>Comparative Analysis</h2>' >> final_report.html
        echo "<img src='$(basename ${heatmap})' alt='Heatmap' style='max-width:100%;'>" >> final_report.html
    fi

    # Optional: CheckV and VirFinder
    if [ -d "${checkv_results}" ]; then
        echo '<h2>CheckV Results</h2><ul>' >> final_report.html
        for f in ${checkv_results}/*; do
            echo "<li><a href='$f'>$(basename $f)</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    if [ -d "${virfinder_results}" ]; then
        echo '<h2>VirFinder Results</h2><ul>' >> final_report.html
        for f in ${virfinder_results}/*; do
            echo "<li><a href='$f'>$(basename $f)</a></li>" >> final_report.html
        done
        echo '</ul>' >> final_report.html
    fi

    echo '</body></html>' >> final_report.html
    """
} 