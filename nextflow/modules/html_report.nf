// Comprehensive interactive HTML report
process html_report {
    label 'process_medium'
    publishDir "${params.outdir}/final_report", mode: 'copy', overwrite: true

    input:
        path krona_html
        path multiqc_report
        path coverage_plots
        path heatmap
        path checkv_report optional true
        path viga_annotation optional true
        path virfinder_results optional true

    output:
        path "final_report.html", emit: html

    script:
    """
    echo '<html><head><title>MetaNextViro Report</title></head><body>' > final_report.html
    echo '<h1>MetaNextViro Summary Report</h1>' >> final_report.html

    # Krona
    echo '<h2>Krona Plot</h2><iframe src="'${krona_html}'" width="800" height="600"></iframe>' >> final_report.html

    # MultiQC
    echo '<h2>MultiQC Report</h2><iframe src="'${multiqc_report}'" width="800" height="600"></iframe>' >> final_report.html

    # Coverage Plots
    echo '<h2>Coverage Plots</h2>' >> final_report.html
    for img in ${coverage_plots}/*.png; do
      echo "<img src=\"$img\" width=\"800\">" >> final_report.html
    done

    # Heatmap
    echo '<h2>Comparative Heatmap</h2><img src="'${heatmap}'" width="800">' >> final_report.html

    # Optional: CheckV, VIGA, VirFinder
    if [ -d "${checkv_report}" ]; then
      echo '<h2>CheckV Report</h2><ul>' >> final_report.html
      for f in ${checkv_report}/*; do
        echo "<li><a href=\"$f\">$(basename $f)</a></li>" >> final_report.html
      done
      echo '</ul>' >> final_report.html
    fi

    if [ -d "${viga_annotation}" ]; then
      echo '<h2>VIGA Annotation</h2><ul>' >> final_report.html
      for f in ${viga_annotation}/*; do
        echo "<li><a href=\"$f\">$(basename $f)</a></li>" >> final_report.html
      done
      echo '</ul>' >> final_report.html
    fi

    if [ -f "${virfinder_results}" ]; then
      echo '<h2>VirFinder Results</h2>' >> final_report.html
      echo '<a href="'${virfinder_results}'">Download VirFinder Results</a>' >> final_report.html
    fi

    echo '</body></html>' >> final_report.html
    """
} 