// Author: Naveen Duhan

include { fastqc } from '../modules/fastqc'


workflow quality {

    take:
        raw_reads1
        raw_reads2

    main:

    fastqc(raw_reads1.join(raw_reads2))

    emit:

    fastqc_results = fastqc.out.fastqc_report

}