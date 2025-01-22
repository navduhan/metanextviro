// Author: Naveen Duhan


include { metanextviro } from './nextflow/workflow/metanextviro.nf'
// Validate parameters before running workflows
workflow {

    // Display help message if requested
    if (params.help) {
        helpMSG()
        exit 0
    }

    // Validate mandatory input parameters
    if (!params.input) {
        error 'Error: Input samplesheet not specified! Use --input <samplesheet> to provide input.'
    }

        // Check if input files exist
    def checkPathParamList = [ params.input, params.adapters ]
    checkPathParamList.each { param -> 
        if (param) { 
            file(param, checkIfExists: true) 
        } 
    }

    // Check mandatory parameters
    if (params.input) { 
        ch_input = file(params.input) 
    } else { 
        exit 1, 'Input samplesheet not specified!' 
    }

    // Run the Nextreo sub-workflow
    metanextviro(ch_input)
}


// Helper functions
def helpMSG() {
    println """
    ____________________________________________________________________________________________

                                nextreo: Avian Orthoreovirus Analysis Pipeline

                                Author : Naveen Duhan (naveen.duhan@outlook.com)
    ____________________________________________________________________________________________

    Usage example:

    nextflow run metanextviro/main.nf [options] --input <sample file /samplesheet> --outdir <output_directory>

    Options:
    --input      Path to the input samplesheet (mandatory)
    --adapters   Path to the adapters file (optional)
    --outdir     Directory for output files (default: './results')
    --help       Show this help message and exit
    """.stripIndent()
}
