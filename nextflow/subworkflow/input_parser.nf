// Author: Naveen Duhan
// License: MIT (see LICENSE)
// Description: Reads CSV, TSV, or Excel samplesheets, verifies that input FASTQ files exist, and emits paired sample ID and read channels.

// Utility function to check if a file has a specific extension
def hasExtension(file, extensions) {
    extensions.any { ext -> file.toString().toLowerCase().endsWith(ext.toLowerCase()) }
}

// Utility function to validate files and return a valid file object
def validateFile(path, fileType) {
    if (!path) {
        exit 1, "Invalid input samplesheet: ${fileType} cannot be empty."
    }
    return file(path, checkIfExists: true)
}

workflow INPUT_PARSER {
    take:
    samplesheet

    main:
    def file_extensions = ["csv", "tsv", "xls", "xlsx"]
    def sheetRef = params.input ?: (params.samplesheet ?: "samplesheet.csv")

    if (!hasExtension(sheetRef, file_extensions)) {
        exit 1, "Unsupported input format: ${sheetRef}. Supported formats are CSV, TSV, XLS, XLSX."
    }

    ch_input_rows = (samplesheet instanceof java.nio.file.Path || samplesheet instanceof File || samplesheet instanceof CharSequence)
        ? Channel.of(file(samplesheet))
        : samplesheet

    // Process file based on its type
    if (hasExtension(sheetRef, "csv")) {
        ch_input_rows = ch_input_rows.splitCsv(header: true)
    } else if (hasExtension(sheetRef, "tsv")) {
        ch_input_rows = ch_input_rows.splitCsv(header: true, sep: '\t')
    } else if (hasExtension(sheetRef, ["xls", "xlsx"])) {
        ch_input_rows = ch_input_rows
            .exec {
                """
                # Use Python or a custom script to convert Excel to CSV
                python3 - <<EOF
                import pandas as pd
                df = pd.read_excel("$samplesheet")
                df.to_csv("temp.csv", index=False)
                EOF
                """
            }
            .splitCsv(header: true)
    }

    // Validate and map input rows (accept both id,reads1,reads2 and sample,fastq_1,fastq_2)
    ch_input_rows = ch_input_rows.map { row ->
        def id = (row.id ?: row.sample) ?: exit(1, "Invalid input samplesheet: 'id' (or 'sample') column is missing.")
        def reads1 = validateFile(row.reads1 ?: row.fastq_1, "reads1")
        def reads2 = validateFile(row.reads2 ?: row.fastq_2, "reads2")
        
        // Return the parsed values
        [id, reads1, reads2]
    }


   // Split the main channel into separate channels for reads1, reads2
    reads1 = ch_input_rows.map { id, reads1, _reads2_unused -> [id, reads1] }
    reads2 = ch_input_rows.map { id, _reads1_unused, reads2 -> [id, reads2] }



    emit:
    reads1
    reads2
    
}
