// Viral analysis subworkflow
include { checkv } from '../modules/checkv.nf'
include { virfinder } from '../modules/virfinder.nf'

workflow VIRAL_ANALYSIS {
    take:
        contigs_ch

    main:
        checkv(contigs_ch)
        virfinder(contigs_ch)

    emit:
        checkv_report = checkv.out.report
        virfinder_full = virfinder.out.results.map { id, full, filtered -> full }
        virfinder_filtered = virfinder.out.results.map { id, full, filtered -> filtered }
} 