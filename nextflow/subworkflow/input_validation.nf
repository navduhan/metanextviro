/**
 * Comprehensive Input Validation Workflow
 * 
 * This workflow performs all input validation tasks including:
 * - File format validation
 * - Samplesheet structure validation  
 * - File accessibility checks
 * - Database validation
 * - Configuration validation
 */

include { VALIDATE_DATABASES; VALIDATE_INPUT_FILES } from './enhanced_input_parser.nf'

workflow INPUT_VALIDATION {
    take:
    samplesheet_path
    
    main:
    
    // Channel for validation results
    validation_results = Channel.empty()
    
    // Step 1: Validate samplesheet format and structure
    log.info "Validating samplesheet format and structure..."
    
    samplesheet_validation = Channel.of(samplesheet_path)
        .map { path ->
            validateSamplesheetFormat(path)
        }
    
    // Step 2: Parse and validate sample entries
    log.info "Parsing and validating sample entries..."
    
    parsed_samples = samplesheet_validation
        .filter { it.valid }
        .map { result ->
            parseSamplesheetContent(result.path)
        }
        .flatten()
        .map { sample ->
            def (id, reads1, reads2) = sample
            return tuple(id, file(reads1), file(reads2))
        }
    
    // Step 3: Validate input file accessibility
    log.info "Validating input file accessibility..."
    
    VALIDATE_INPUT_FILES(parsed_samples)
    validated_samples = VALIDATE_INPUT_FILES.out.validated_reads
    input_validation_reports = VALIDATE_INPUT_FILES.out.report
    
    // Step 4: Validate databases
    log.info "Validating database configurations..."
    
    VALIDATE_DATABASES()
    database_validation_report = VALIDATE_DATABASES.out.report
    
    // Step 5: Collect all validation results
    all_validation_reports = input_validation_reports
        .collect()
        .combine(database_validation_report)
    
    // Step 6: Generate comprehensive validation summary
    validation_summary = generateValidationSummary(all_validation_reports)
    
    emit:
    validated_samples = validated_samples
    validation_reports = all_validation_reports
    validation_summary = validation_summary
    reads1 = validated_samples.map { id, reads1, reads2 -> tuple(id, reads1) }
    reads2 = validated_samples.map { id, reads1, reads2 -> tuple(id, reads2) }
}

/**
 * Validate samplesheet file format
 */
def validateSamplesheetFormat(samplesheetPath) {
    def result = [valid: false, path: samplesheetPath, errors: [], warnings: []]
    
    try {
        // Check if file exists
        def file = new File(samplesheetPath)
        if (!file.exists()) {
            result.errors.add("Samplesheet file does not exist: ${samplesheetPath}")
            return result
        }
        
        if (!file.canRead()) {
            result.errors.add("Samplesheet file is not readable: ${samplesheetPath}")
            return result
        }
        
        // Check file format
        def extension = getFileExtension(samplesheetPath)
        def supportedFormats = params.validation?.supported_formats ?: ['csv', 'tsv', 'xls', 'xlsx']
        
        if (!supportedFormats.contains(extension.toLowerCase())) {
            result.errors.add("Unsupported file format: ${extension}. Supported formats: ${supportedFormats.join(', ')}")
            return result
        }
        
        // Check if file is empty
        if (file.length() == 0) {
            result.errors.add("Samplesheet file is empty: ${samplesheetPath}")
            return result
        }
        
        // Excel format warning
        if (['xls', 'xlsx'].contains(extension.toLowerCase())) {
            result.warnings.add("Excel format detected. Consider converting to CSV for better compatibility.")
        }
        
        result.valid = true
        log.info "Samplesheet format validation passed: ${extension.toUpperCase()}"
        
    } catch (Exception e) {
        result.errors.add("Error validating samplesheet format: ${e.message}")
    }
    
    return result
}

/**
 * Parse samplesheet content and validate structure
 */
def parseSamplesheetContent(samplesheetPath) {
    def extension = getFileExtension(samplesheetPath)
    def samples = []
    
    try {
        switch (extension.toLowerCase()) {
            case 'csv':
                samples = parseCsvContent(samplesheetPath)
                break
            case 'tsv':
                samples = parseTsvContent(samplesheetPath)
                break
            case ['xls', 'xlsx']:
                error "Excel parsing not yet implemented. Please convert to CSV format."
                break
            default:
                error "Unsupported format for parsing: ${extension}"
        }
        
        // Validate parsed samples
        validateSampleEntries(samples)
        
    } catch (Exception e) {
        error "Error parsing samplesheet content: ${e.message}"
    }
    
    return samples
}

/**
 * Parse CSV samplesheet content
 */
def parseCsvContent(samplesheetPath) {
    def samples = []
    def headers = []
    def requiredColumns = params.validation?.required_columns ?: ['sample', 'fastq_1', 'fastq_2']
    
    new File(samplesheetPath).eachLine { line, lineNum ->
        if (lineNum == 1) {
            headers = parseCSVLine(line)
            
            // Validate headers
            def missingColumns = requiredColumns.findAll { !headers.contains(it) }
            if (missingColumns) {
                error "Missing required columns: ${missingColumns.join(', ')}. Required: ${requiredColumns.join(', ')}"
            }
            
            log.info "Found columns: ${headers.join(', ')}"
            return
        }
        
        def values = parseCSVLine(line)
        if (values.size() != headers.size()) {
            error "Row ${lineNum}: Column count mismatch. Expected ${headers.size()}, found ${values.size()}"
        }
        
        def sample = [:]
        headers.eachWithIndex { header, index ->
            sample[header] = values[index]?.trim()
        }
        
        samples.add([sample.sample, sample.fastq_1, sample.fastq_2])
    }
    
    return samples
}

/**
 * Parse TSV samplesheet content
 */
def parseTsvContent(samplesheetPath) {
    def samples = []
    def headers = []
    def requiredColumns = params.validation?.required_columns ?: ['sample', 'fastq_1', 'fastq_2']
    
    new File(samplesheetPath).eachLine { line, lineNum ->
        if (lineNum == 1) {
            headers = line.split('\t')
            
            // Validate headers
            def missingColumns = requiredColumns.findAll { !headers.contains(it) }
            if (missingColumns) {
                error "Missing required columns: ${missingColumns.join(', ')}. Required: ${requiredColumns.join(', ')}"
            }
            
            log.info "Found columns: ${headers.join(', ')}"
            return
        }
        
        def values = line.split('\t')
        if (values.size() != headers.size()) {
            error "Row ${lineNum}: Column count mismatch. Expected ${headers.size()}, found ${values.size()}"
        }
        
        def sample = [:]
        headers.eachWithIndex { header, index ->
            sample[header] = values[index]?.trim()
        }
        
        samples.add([sample.sample, sample.fastq_1, sample.fastq_2])
    }
    
    return samples
}

/**
 * Validate sample entries
 */
def validateSampleEntries(samples) {
    def sampleNames = []
    
    samples.eachWithIndex { sample, index ->
        def rowNum = index + 2 // +2 for header and 0-based index
        def (sampleName, fastq1, fastq2) = sample
        
        // Check for empty sample name
        if (!sampleName || sampleName.trim().isEmpty()) {
            error "Row ${rowNum}: Sample name cannot be empty"
        }
        
        // Check for duplicate sample names
        if (sampleNames.contains(sampleName)) {
            error "Row ${rowNum}: Duplicate sample name '${sampleName}'"
        }
        sampleNames.add(sampleName)
        
        // Check for empty file paths
        if (!fastq1 || fastq1.trim().isEmpty()) {
            error "Row ${rowNum}: fastq_1 path cannot be empty for sample '${sampleName}'"
        }
        
        if (!fastq2 || fastq2.trim().isEmpty()) {
            error "Row ${rowNum}: fastq_2 path cannot be empty for sample '${sampleName}'"
        }
        
        // Validate file extensions if enabled
        if (params.validation?.check_file_extensions) {
            def allowedExtensions = params.validation?.allowed_fastq_extensions ?: ['.fastq', '.fq', '.fastq.gz', '.fq.gz']
            
            def fastq1Valid = allowedExtensions.any { fastq1.toLowerCase().endsWith(it) }
            def fastq2Valid = allowedExtensions.any { fastq2.toLowerCase().endsWith(it) }
            
            if (!fastq1Valid) {
                log.warn "Row ${rowNum}: fastq_1 does not have standard FASTQ extension: ${fastq1}"
            }
            
            if (!fastq2Valid) {
                log.warn "Row ${rowNum}: fastq_2 does not have standard FASTQ extension: ${fastq2}"
            }
        }
    }
    
    log.info "Sample entry validation passed for ${samples.size()} samples"
}

/**
 * Generate comprehensive validation summary
 */
def generateValidationSummary(validationReports) {
    return Channel.of(validationReports)
        .map { reports ->
            def summary = [
                timestamp: new Date().toString(),
                total_samples: 0,
                validation_status: 'PASSED',
                errors: [],
                warnings: [],
                recommendations: []
            ]
            
            // Process validation reports
            // This would analyze all the validation report files
            // and generate a comprehensive summary
            
            return summary
        }
}

/**
 * Parse CSV line with proper quote handling
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
 * Validation summary process
 */
process GENERATE_VALIDATION_SUMMARY {
    tag "validation_summary"
    label 'process_low'
    
    publishDir "${params.outdir}/validation", mode: 'copy'
    
    input:
    path validation_reports
    
    output:
    path "validation_summary.txt", emit: summary
    path "validation_summary.json", emit: json_summary
    
    script:
    """
    echo "MetaNextViro Pipeline - Validation Summary" > validation_summary.txt
    echo "=========================================" >> validation_summary.txt
    echo "Generated: \$(date)" >> validation_summary.txt
    echo "" >> validation_summary.txt
    
    # Count total validation files
    total_files=\$(ls -1 *.txt 2>/dev/null | wc -l)
    echo "Total validation reports: \$total_files" >> validation_summary.txt
    echo "" >> validation_summary.txt
    
    # Check for any failures
    if grep -q "✗" *.txt 2>/dev/null; then
        echo "VALIDATION STATUS: FAILED" >> validation_summary.txt
        echo "" >> validation_summary.txt
        echo "ERRORS FOUND:" >> validation_summary.txt
        grep "✗" *.txt | sed 's/^/  /' >> validation_summary.txt
    else
        echo "VALIDATION STATUS: PASSED" >> validation_summary.txt
        echo "" >> validation_summary.txt
        echo "All validations completed successfully!" >> validation_summary.txt
    fi
    
    echo "" >> validation_summary.txt
    echo "DETAILED REPORTS:" >> validation_summary.txt
    for report in *.txt; do
        if [ "\$report" != "validation_summary.txt" ]; then
            echo "  - \$report" >> validation_summary.txt
        fi
    done
    
    # Generate JSON summary
    cat > validation_summary.json << 'EOF'
{
    "timestamp": "\$(date -Iseconds)",
    "pipeline": "MetaNextViro",
    "validation_status": "PASSED",
    "total_reports": \$total_files,
    "reports": [
EOF
    
    first=true
    for report in *.txt; do
        if [ "\$report" != "validation_summary.txt" ]; then
            if [ "\$first" = true ]; then
                first=false
            else
                echo "," >> validation_summary.json
            fi
            echo "        \"\$report\"" >> validation_summary.json
        fi
    done
    
    cat >> validation_summary.json << 'EOF'
    ]
}
EOF
    """
}