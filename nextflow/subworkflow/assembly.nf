// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Selects MEGAHIT, metaSPAdes, or hybrid assembly based on params.assembler and evaluates reconstructed contigs with QUAST.

include { megahit } from "../modules/megahit"
include { metaspades } from "../modules/metaspades"
include { hybrid } from "../modules/hybrid"
include { quast } from '../modules/quast.nf'

workflow ASSEMBLY {
    // Define input channels for raw reads
    take:
        raw_reads1
        raw_reads2

    main:
        // Run the appropriate assembler or hybrid workflow
        if (params.assembler == "megahit") {
            // Run MEGAHIT assembler
            megahit(raw_reads1.join(raw_reads2))
            
            // Prepare input for QUAST with metadata
            quast_ch = megahit.out.contigs.map { id, fasta ->
                [ [ id: id ], fasta ]
            }
            quast(quast_ch)
            
            ch_contigs = megahit.out.contigs
            stats = quast.out.report

        } else if (params.assembler == "metaspades") {
            // Run metaSPAdes assembler
            metaspades(raw_reads1.join(raw_reads2))
            
            // Prepare input for QUAST with metadata
            quast_ch = metaspades.out.contigs.map { id, fasta ->
                [ [ id: id ], fasta ]
            }
            quast(quast_ch)
            
            ch_contigs = metaspades.out.contigs
            stats = quast.out.report

        } else if (params.assembler == "hybrid") {
            // Run both MEGAHIT and metaSPAdes, then merge using the hybrid process
            megahit(raw_reads1.join(raw_reads2))
            metaspades(raw_reads1.join(raw_reads2))
            hybrid(megahit.out.contigs.join(metaspades.out.contigs))
            
            // Prepare input for QUAST with metadata
            quast_ch = hybrid.out.contigs.map { id, fasta ->
                [ [ id: id ], fasta ]
            }
            quast(quast_ch)
            
            ch_contigs = hybrid.out.contigs
            stats = quast.out.report

        } else {
            // Handle invalid assembler parameter
            error "Invalid assembler specified in params.assembler: '${params.assembler}'. Please use 'megahit', 'metaspades', or 'hybrid'."
        }

    emit:
        contigs = ch_contigs
        assembly_stats = stats
        megahit_logs = params.assembler == "megahit" || params.assembler == "hybrid" ? megahit.out.log : null
        megahit_params = params.assembler == "megahit" || params.assembler == "hybrid" ? megahit.out.params : null
        megahit_raw_contigs = params.assembler == "megahit" || params.assembler == "hybrid" ? megahit.out.raw_contigs : null
        metaspades_logs = params.assembler == "metaspades" || params.assembler == "hybrid" ? metaspades.out.log : null
        metaspades_params = params.assembler == "metaspades" || params.assembler == "hybrid" ? metaspades.out.params : null
        metaspades_raw_scaffolds = params.assembler == "metaspades" || params.assembler == "hybrid" ? metaspades.out.raw_scaffolds : null
        hybrid_merged = params.assembler == "hybrid" ? hybrid.out.merged : null
        hybrid_cdhit = params.assembler == "hybrid" ? hybrid.out.cdhit : null
        hybrid_cdhit_clstr = params.assembler == "hybrid" ? hybrid.out.cdhit_clstr : null
}
