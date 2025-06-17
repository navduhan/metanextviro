// Author: Naveen Duhan

include { megahit } from '../modules/megahit.nf'
include { metaspades } from '../modules/metaspades.nf'
include { hybrid } from '../modules/hybrid.nf'
include { quast } from '../modules/quast.nf'

workflow ASSEMBLY {
    take:
        reads1_ch
        reads2_ch

    main:
        // Run the appropriate assembler or hybrid workflow based on params
        if (params.assembler == "megahit") {
            // Run MEGAHIT assembler
            megahit(reads1_ch.combine(reads2_ch))
            
            // Prepare input for QUAST with metadata
            quast_ch = megahit.out.contigs.map { id, contigs ->
                [ [ id: id ], contigs ]
            }
            quast(quast_ch)
            
            contigs = megahit.out.contigs
            stats = quast.out.report

        } else if (params.assembler == "metaspades") {
            // Run metaSPAdes assembler
            metaspades(reads1_ch.combine(reads2_ch))
            
            // Prepare input for QUAST with metadata
            quast_ch = metaspades.out.contigs.map { id, contigs ->
                [ [ id: id ], contigs ]
            }
            quast(quast_ch)
            
            contigs = metaspades.out.contigs
            stats = quast.out.report

        } else if (params.assembler == "hybrid") {
            // Run both MEGAHIT and metaSPAdes, then merge using the hybrid process
            megahit(reads1_ch.combine(reads2_ch))
            metaspades(reads1_ch.combine(reads2_ch))
            
            // Merge assemblies using hybrid process
            hybrid(
                megahit.out.contigs
                    .combine(metaspades.out.contigs)
            )
            
            // Prepare input for QUAST with metadata
            quast_ch = hybrid.out.contigs.map { id, contigs ->
                [ [ id: id ], contigs ]
            }
            quast(quast_ch)
            
            contigs = hybrid.out.contigs
            stats = quast.out.report

        } else {
            error "Invalid assembler specified in params.assembler: '${params.assembler}'. Please use 'megahit', 'metaspades', or 'hybrid'."
        }

    emit:
        contigs    // Will contain the appropriate contigs based on selected assembler
        assembly_stats = stats
}
