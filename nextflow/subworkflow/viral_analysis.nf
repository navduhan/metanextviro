// Viral analysis subworkflow (CheckV, enhanced VirFinder, optional geNomad)
include { checkv } from '../modules/checkv.nf'
include { virfinder } from '../modules/virfinder.nf'
include { genomad } from '../modules/genomad.nf'

workflow VIRAL_ANALYSIS {
    take:
        contigs_ch

    main:
        ch_checkv_report = Channel.empty()
        ch_checkv_summary = Channel.empty()
        ch_virfinder_full = Channel.empty()
        ch_virfinder_filtered = Channel.empty()
        ch_virfinder_table = Channel.empty()
        ch_genomad_report = Channel.empty()
        ch_genomad_virus = Channel.empty()
        ch_genomad_plasmid = Channel.empty()

        if (params.run_checkv) {
            checkv(contigs_ch)
            ch_checkv_report = checkv.out.report
            ch_checkv_summary = checkv.out.quality_summary
        }
        if (params.run_virfinder) {
            virfinder(contigs_ch)
            ch_virfinder_full = virfinder.out.results.map { id, full, filtered -> full }
            ch_virfinder_filtered = virfinder.out.results.map { id, full, filtered -> filtered }
            ch_virfinder_table = virfinder.out.full_table
        }
        if (params.run_genomad) {
            genomad(contigs_ch)
            ch_genomad_report = genomad.out.report_dir
            ch_genomad_virus = genomad.out.virus_summary
            ch_genomad_plasmid = genomad.out.plasmid_summary
        }

    emit:
        checkv_report = ch_checkv_report
        checkv_summary = ch_checkv_summary
        virfinder_full = ch_virfinder_full
        virfinder_filtered = ch_virfinder_filtered
        virfinder_table = ch_virfinder_table
        genomad_report = ch_genomad_report
        genomad_virus = ch_genomad_virus
        genomad_plasmid = ch_genomad_plasmid
}
