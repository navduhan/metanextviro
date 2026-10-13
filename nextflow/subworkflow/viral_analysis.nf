// Viral analysis subworkflow
include { checkv } from '../modules/checkv.nf'
include { virfinder } from '../modules/virfinder.nf'

workflow VIRAL_ANALYSIS {
    take:
        contigs_ch

    main:
        ch_checkv_report = Channel.empty()
        ch_virfinder_full = Channel.empty()
        ch_virfinder_filtered = Channel.empty()

        if (params.run_checkv) {
            checkv(contigs_ch)
            ch_checkv_report = checkv.out.report
        }
        if (params.run_virfinder) {
            virfinder(contigs_ch)
            ch_virfinder_full = virfinder.out.results.map { id, full, filtered -> full }
            ch_virfinder_filtered = virfinder.out.results.map { id, full, filtered -> filtered }
        }

    emit:
        checkv_report = ch_checkv_report
        virfinder_full = ch_virfinder_full
        virfinder_filtered = ch_virfinder_filtered
}
