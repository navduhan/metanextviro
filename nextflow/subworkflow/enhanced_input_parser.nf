/**
 * Enhanced Input Parser with Comprehensive Validation
 * 
 * This workflow provides robust input validation and parsing for the MetaNextViro pipeline
 * Includes validation for file formats, samplesheet structure, file accessibility, and databases
 */

include { InputValidator; ValidationResult } from '../lib/InputValidator.groovy'

workflow ENHANCED_INPUT_PARSER {
    take:
    samplesheet_path
    
    main:
    
    // Perform comprehensive input validation
    log.info "Starting comprehensive input validation..."
    
    // Create validation channel
    validation_ch = Channel.of(samplesheet_path)
        .map { path ->
            try {
                // Validate samplesheet format and content
                def samplesheetResult = InputValidator.validateSamplesheet(path)
                
                // Validate databases
                def databaseResult = InputValidator.validateDatabases(params)
                
                // Validate adapter file if specified
                def adapterResult = new ValidationResult()
                if (params.adapters) {
                    adapterResult = InputValidator.validateAdapterFile(params.adapters)
                }
                
                // Combine all validation results
                def overallResult = new ValidationResult()
                overallResult.merge(samplesheetResult)
                overallResult.merge(databaseResult)
                overallResult.merge(adapterResult)
                
                // Log validation results
                log.info "Validation Results:\n${overallResult.toString()}"
                
                if (!overallResult.isValid()) {
                    error "Input validation failed. Please fix the errors above and try again."
                }
                
                return [path, overallResult]
                
            } catch (Exception e) {
                error "Validation error: ${e.message}"
            }
        }
    
    // Parse the validated samplesheet
    parsed_samples = validation_ch
        .map { path, validationResult ->
            return parseSamplesheet(path)
        }
        .flatten()
        .map { sample ->
            def (id, reads1, reads2) = sample
            return [id, file(reads1), file(reads2)]
        }
    
    // Split into separate channels
    reads1_ch = parsed_samples.map { id, reads1, reads2 -> [id, reads1] }
    reads2_ch = parsed_samples.map { id, reads1, reads2 -> [id, reads2] }
    
    emit:
    reads1 = reads1_ch
    reads2 = reads2_ch
    validation_report = validation_ch.map { path, result -> result }
}

/**
 * Parse samplesheet based on file format
 */
def parseSamplesheet(samplesheetPath) {
    def extension = getFileExtension(samplesheetPath)
    def samples = []
    
    switch (extension.toLowerCase()) {
        case 'csv':
            samples = parseCsvSamplesheet(samplesheetPath)
            break
        case 'tsv':
            samples = parseTsvSamplesheet(samplesheetPath)
            break
        case ['xls', 'xlsx']:
            error "Excel format detected. Please convert to CSV format for processing."
            break
        default:
            error "Unsupported file format: ${extension}"
    }
    
    return samples
}

/**
 * Parse CSV samplesheet
 */
def parseCsvSamplesheet(samplesheetPath) {
    def samples = []
    def headers = []
    
    file(samplesheetPath).eachLine { line, lineNum ->
        if (lineNum == 1) {
            headers = parseCSVLine(line)
            validateHeaders(headers)
            return
        }
        
        def values = parseCSVLine(line)
        if (values.size() != headers.size()) {
            error "Row ${lineNum}: Expected ${headers.size()} columns, found ${values.size()}"
        }
        
        def sample = [:]
        headers.eachWithIndex { header, index ->
            sample[header] = values[index]?.trim()
        }
        
        // Validate required fields
        if (!sample.sample) {
            error "Row ${lineNum}: Sample name cannot be empty"
        }
        if (!sample.fastq_1) {
            error "Row ${lineNum}: fastq_1 path cannot be empty"
        }
        if (!sample.fastq_2) {
            error "Row ${lineNum}: fastq_2 path cannot be empty"
        }
        
        samples.add([sample.sample, sample.fastq_1, sample.fastq_2])
    }
    
    return samples
}

/**
 * Parse TSV samplesheet
 */
def parseTsvSamplesheet(samplesheetPath) {
    def samples = []
    def headers = []
    
    file(samplesheetPath).eachLine { line, lineNum ->
        if (lineNum == 1) {
            headers = line.split('\t')
            validateHeaders(headers)
            return
        }
        
        def values = line.split('\t')
        if (values.size() != headers.size()) {
            error "Row ${lineNum}: Expected ${headers.size()} columns, found ${values.size()}"
        }
        
        def sample = [:]
        headers.eachWithIndex { header, index ->
            sample[header] = values[index]?.trim()
        }
        
        // Validate required fields
        if (!sample.sample) {
            error "Row ${lineNum}: Sample name cannot be empty"
        }
        if (!sample.fastq_1) {
            error "Row ${lineNum}: fastq_1 path cannot be empty"
        }
        if (!sample.fastq_2) {
            error "Row ${lineNum}: fastq_2 path cannot be empty"
        }
        
        samples.add([sample.sample, sample.fastq_1, sample.fastq_2])
    }
    
    return samples
}

/**
 * Validate samplesheet headers
 */
def validateHeaders(headers) {
    def requiredColumns = ['sample', 'fastq_1', 'fastq_2']
    def missingColumns = requiredColumns.findAll { !headers.contains(it) }
    
    if (missingColumns) {
        error "Missing required columns: ${missingColumns.join(', ')}. Required columns: ${requiredColumns.join(', ')}"
    }
}

/**
 * Parse CSV line handling quotes and escaped commas
 */
def parseCSVLine(String line) {
    def values = []
    def current = new StringBuilder()
    def inQuotes = false
    def chars = line.toCharArray()
    
    for (int i = 0; i < chars.length; i++) {
        char c = chars[i]
        
        if (c == '"') {
            if (inQuotes && i + 1 < chars.length && chars[i + 1] == '"') {
                current.append('"')
                i++
            } else {
                inQuotes = !inQuotes
            }
        } else if (c == ',' && !inQuotes) {
            values.add(current.toString())
            current = new StringBuilder()
        } else {
            current.append(c)
        }
    }
    
    values.add(current.toString())
    return values
}

/**
 * Get file extension
 */
def getFileExtension(String filePath) {
    def lastDot = filePath.lastIndexOf('.')
    return lastDot > 0 ? filePath.substring(lastDot + 1) : ''
}

/**
 * Validation process for databases and configuration
 */
process VALIDATE_DATABASES {
    tag "database_validation"
    label 'process_low'
    
    output:
    path "validation_report.txt", emit: report
    
    script:
    """
    echo "Database Validation Report" > validation_report.txt
    echo "=========================" >> validation_report.txt
    echo "" >> validation_report.txt
    
    # Check Kraken2 database
    if [ -d "${params.kraken2_db}" ]; then
        echo "✓ Kraken2 database found: ${params.kraken2_db}" >> validation_report.txt
        
        # Check for required files
        if [ -f "${params.kraken2_db}/hash.k2d" ] && [ -f "${params.kraken2_db}/opts.k2d" ] && [ -f "${params.kraken2_db}/taxo.k2d" ]; then
            echo "  ✓ Required Kraken2 files present" >> validation_report.txt
        else
            echo "  ✗ Missing required Kraken2 database files" >> validation_report.txt
            exit 1
        fi
    else
        echo "✗ Kraken2 database not found: ${params.kraken2_db}" >> validation_report.txt
        exit 1
    fi
    
    # Check CheckV database
    if [ -d "${params.checkv_db}" ]; then
        echo "✓ CheckV database found: ${params.checkv_db}" >> validation_report.txt
    else
        echo "✗ CheckV database not found: ${params.checkv_db}" >> validation_report.txt
        exit 1
    fi
    
    # Check BLAST databases if configured
    if [ "${params.blast_options}" != "none" ]; then
        if [ -n "${params.blastdb_viruses}" ]; then
            if ls ${params.blastdb_viruses}.* 1> /dev/null 2>&1; then
                echo "✓ BLAST viruses database found: ${params.blastdb_viruses}" >> validation_report.txt
            else
                echo "✗ BLAST viruses database files not found: ${params.blastdb_viruses}" >> validation_report.txt
                exit 1
            fi
        fi
        
        if [ -n "${params.blastdb_nt}" ]; then
            if ls ${params.blastdb_nt}.* 1> /dev/null 2>&1; then
                echo "✓ BLAST NT database found: ${params.blastdb_nt}" >> validation_report.txt
            else
                echo "✗ BLAST NT database files not found: ${params.blastdb_nt}" >> validation_report.txt
                exit 1
            fi
        fi
        
        if [ -n "${params.diamonddb}" ] && [ "${params.blastx_tool}" == "diamond" ]; then
            if [ -f "${params.diamonddb}" ]; then
                echo "✓ DIAMOND database found: ${params.diamonddb}" >> validation_report.txt
            else
                echo "✗ DIAMOND database not found: ${params.diamonddb}" >> validation_report.txt
                exit 1
            fi
        fi
    fi
    
    echo "" >> validation_report.txt
    echo "All database validations passed!" >> validation_report.txt
    """
}

/**
 * Process to validate input files accessibility
 */
process VALIDATE_INPUT_FILES {
    tag "${sample_id}"
    label 'process_low'
    
    input:
    tuple val(sample_id), path(reads1), path(reads2)
    
    output:
    tuple val(sample_id), path(reads1), path(reads2), emit: validated_reads
    path "${sample_id}_validation.txt", emit: report
    
    script:
    """
    echo "Input File Validation for ${sample_id}" > ${sample_id}_validation.txt
    echo "=====================================" >> ${sample_id}_validation.txt
    echo "" >> ${sample_id}_validation.txt
    
    # Check reads1
    if [ -f "${reads1}" ]; then
        echo "✓ reads1 file exists: ${reads1}" >> ${sample_id}_validation.txt
        
        # Check if file is readable
        if [ -r "${reads1}" ]; then
            echo "  ✓ reads1 is readable" >> ${sample_id}_validation.txt
        else
            echo "  ✗ reads1 is not readable" >> ${sample_id}_validation.txt
            exit 1
        fi
        
        # Check file size
        size1=\$(stat -f%z "${reads1}" 2>/dev/null || stat -c%s "${reads1}" 2>/dev/null || echo "0")
        if [ "\$size1" -gt 0 ]; then
            echo "  ✓ reads1 file size: \$size1 bytes" >> ${sample_id}_validation.txt
        else
            echo "  ✗ reads1 file is empty" >> ${sample_id}_validation.txt
            exit 1
        fi
    else
        echo "✗ reads1 file not found: ${reads1}" >> ${sample_id}_validation.txt
        exit 1
    fi
    
    # Check reads2
    if [ -f "${reads2}" ]; then
        echo "✓ reads2 file exists: ${reads2}" >> ${sample_id}_validation.txt
        
        # Check if file is readable
        if [ -r "${reads2}" ]; then
            echo "  ✓ reads2 is readable" >> ${sample_id}_validation.txt
        else
            echo "  ✗ reads2 is not readable" >> ${sample_id}_validation.txt
            exit 1
        fi
        
        # Check file size
        size2=\$(stat -f%z "${reads2}" 2>/dev/null || stat -c%s "${reads2}" 2>/dev/null || echo "0")
        if [ "\$size2" -gt 0 ]; then
            echo "  ✓ reads2 file size: \$size2 bytes" >> ${sample_id}_validation.txt
        else
            echo "  ✗ reads2 file is empty" >> ${sample_id}_validation.txt
            exit 1
        fi
    else
        echo "✗ reads2 file not found: ${reads2}" >> ${sample_id}_validation.txt
        exit 1
    fi
    
    echo "" >> ${sample_id}_validation.txt
    echo "All input file validations passed for ${sample_id}!" >> ${sample_id}_validation.txt
    """
}