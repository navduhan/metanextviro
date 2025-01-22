// Author: Naveen Duhan

include { megahit } from "../modules/megahit"
include { metaspades } from "../modules/metaspades"
include { hybrid } from "../modules/hybrid"

workflow assembly {

    // Define input channels for raw reads
    take:
        raw_reads1
        raw_reads2

    main:
        // Run the appropriate assembler or hybrid workflow
        if (params.assembler == "megahit") {
            // Run MEGAHIT assembler
            megahit(raw_reads1.join(raw_reads2))
        } else if (params.assembler == "metaspades") {
            // Run metaSPAdes assembler
            metaspades(raw_reads1.join(raw_reads2))
        } else if (params.assembler == "hybrid") {
            // Run both MEGAHIT and metaSPAdes, then merge using the hybrid process
            megahit(raw_reads1.join(raw_reads2))
            metaspades(raw_reads1.join(raw_reads2))
            hybrid(megahit.out.contigs.join(metaspades.out.contigs))
        } else {
            // Handle invalid assembler parameter
            error "Invalid assembler specified in params.assembler: '${params.assembler}'. Please use 'megahit', 'metaspades', or 'hybrid'."
        }

    emit:
        // Emit the appropriate contigs based on the selected assembler
        contigs = 
            params.assembler == "megahit"   ? megahit.out.contigs :
            params.assembler == "metaspades" ? metaspades.out.contigs :
            params.assembler == "hybrid"    ? hybrid.out.contigs :
            null  // Should not be reached due to earlier validation
}
