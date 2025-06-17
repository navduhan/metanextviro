// Author: Naveen Duhan
// Taxonomic profiling subworkflow (Kraken2 + Krona)

include { kraken2 } from '../modules/kraken2.nf'
include { krona } from '../modules/krona.nf'

workflow TAXONOMIC_PROFILING {
    take:
        reads_ch // tuple(val(id), path(reads1), path(reads2))

    main:
        // Run Kraken2
        kraken2(reads_ch)

        // Run Krona visualization on Kraken2 report
        krona(kraken2.out.report)

    emit:
        kraken2_reports = kraken2.out.report
        kraken2_outputs = kraken2.out.classified_reads
        krona_html = krona.out.krona_html
} 