// Viral analysis subworkflow
include { checkv } from '../modules/checkv.nf'
include { viga } from '../modules/viga.nf'
include { virfinder } from '../modules/virfinder.nf'

workflow VIRAL_ANALYSIS {
    take:
        contigs_ch // tuple(val(id), path(contigs))
    main:
        checkv(contigs_ch)
        viga(contigs_ch)
        virfinder(contigs_ch)
    emit:
        checkv_report = checkv.out.report
        viga_annotation = viga.out.annotation
        virfinder_results = virfinder.out.results
} 