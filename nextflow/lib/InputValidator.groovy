/**
 * InputValidator.groovy
 * 
 * Comprehensive input validation module for MetaNextViro pipeline
 * Provides validation for input files, samplesheets, and database configurations
 * 
 * Author: MetaNextViro Development Team
 */

// Import enhanced error handling classes
@Grab('groovy.transform.CompileStatic')

class InputValidator {
    
    // Supported file formats
    static final List<String> SUPPORTED_FORMATS = ['csv', 'tsv', 'xls', 'xlsx']
    static final List<String> REQUIRED_COLUMNS = ['sample', 'fastq_1', 'fastq_2']
    static final List<String> OPTIONAL_COLUMNS = ['single_end']
    
    /**
     * Validate input file format
     * @param filePath Path to the input file
     * @return ValidationResult object
     */
    static ValidationResult validateFileFormat(String filePath) {
        def result = new ValidationResult()
        
        if (!filePath) {
            result.addInputError("Input file path cannot be null or empty", "NULL_PATH")
            return result
        }
        
        def file = new File(filePath)
        if (!file.exists()) {
            result.addInputError("Input file does not exist: ${filePath}", "FILE_NOT_FOUND", [filePath: filePath])
                .withSuggestion("Check the file path and ensure the file exists")
            return result
        }
        
        if (!file.canRead()) {
            result.addInputError("Input file is not readable: ${filePath}", "FILE_NOT_READABLE", [filePath: filePath])
                .withSuggestion("Check file permissions")
            return result
        }
        
        def extension = getFileExtension(filePath)
        if (!SUPPORTED_FORMATS.contains(extension.toLowerCase())) {
            result.addInputError("Unsupported file format: ${extension}. Supported formats: ${SUPPORTED_FORMATS.join(', ')}", "UNSUPPORTED_FORMAT", [
                extension: extension,
                supportedFormats: SUPPORTED_FORMATS
            ]).withSuggestion("Please convert your file to one of the supported formats (CSV, TSV, XLS, XLSX)")
            return result
        }
        
        result.setValid(true)
        result.addInfo("File format validation passed: ${extension.toUpperCase()}")
        return result
    }
    
    /**
     * Validate samplesheet columns and content
     * @param filePath Path to the samplesheet
     * @return ValidationResult object
     */
    static ValidationResult validateSamplesheet(String filePath) {
        def result = new ValidationResult()
        
        // First validate file format
        def formatResult = validateFileFormat(filePath)
        if (!formatResult.isValid()) {
            return formatResult
        }
        
        try {
            def extension = getFileExtension(filePath)
            def rows = []
            
            // Parse file based on format
            switch (extension.toLowerCase()) {
                case 'csv':
                    rows = parseCsvFile(filePath)
                    break
                case 'tsv':
                    rows = parseTsvFile(filePath)
                    break
                case ['xls', 'xlsx']:
                    rows = parseExcelFile(filePath)
                    break
                default:
                    result.addError("Unexpected file format during parsing: ${extension}")
                    return result
            }
            
            if (rows.isEmpty()) {
                result.addError("Samplesheet is empty or contains no data rows")
                result.addSuggestion("Ensure your samplesheet contains at least one sample with the required columns")
                return result
            }
            
            // Validate column headers
            def columnResult = validateColumns(rows[0].keySet() as List)
            if (!columnResult.isValid()) {
                result.merge(columnResult)
                return result
            }
            
            // Validate each row
            def rowValidationResult = validateSampleRows(rows)
            result.merge(rowValidationResult)
            
            if (result.isValid()) {
                result.addInfo("Samplesheet validation passed: ${rows.size()} samples found")
            }
            
        } catch (Exception e) {
            result.addError("Error parsing samplesheet: ${e.message}")
            result.addSuggestion("Check file format and ensure it's not corrupted")
        }
        
        return result
    }
    
    /**
     * Validate required and optional columns
     * @param columns List of column names from the samplesheet
     * @return ValidationResult object
     */
    static ValidationResult validateColumns(List<String> columns) {
        def result = new ValidationResult()
        
        if (!columns) {
            result.addError("No columns found in samplesheet")
            return result
        }
        
        // Check for required columns
        def missingRequired = REQUIRED_COLUMNS.findAll { !columns.contains(it) }
        if (missingRequired) {
            result.addError("Missing required columns: ${missingRequired.join(', ')}")
            result.addSuggestion("Required columns are: ${REQUIRED_COLUMNS.join(', ')}")
            result.addSuggestion("Example header: ${REQUIRED_COLUMNS.join(',')}")
            return result
        }
        
        // Check for unknown columns
        def allValidColumns = REQUIRED_COLUMNS + OPTIONAL_COLUMNS
        def unknownColumns = columns.findAll { !allValidColumns.contains(it) }
        if (unknownColumns) {
            result.addWarning("Unknown columns found (will be ignored): ${unknownColumns.join(', ')}")
            result.addSuggestion("Valid columns are: ${allValidColumns.join(', ')}")
        }
        
        result.setValid(true)
        result.addInfo("Column validation passed")
        return result
    }
    
    /**
     * Validate individual sample rows
     * @param rows List of sample rows from samplesheet
     * @return ValidationResult object
     */
    static ValidationResult validateSampleRows(List<Map> rows) {
        def result = new ValidationResult()
        def sampleNames = []
        
        for (int i = 0; i < rows.size(); i++) {
            def row = rows[i]
            def rowNum = i + 2 // +2 because index starts at 0 and we skip header
            
            // Validate sample name
            if (!row.sample || row.sample.toString().trim().isEmpty()) {
                result.addError("Row ${rowNum}: Sample name cannot be empty")
            } else {
                def sampleName = row.sample.toString().trim()
                if (sampleNames.contains(sampleName)) {
                    result.addError("Row ${rowNum}: Duplicate sample name '${sampleName}'")
                } else {
                    sampleNames.add(sampleName)
                }
            }
            
            // Validate FASTQ files
            def fastq1ValidationResult = validateInputFile(row.fastq_1, "fastq_1", rowNum)
            result.merge(fastq1ValidationResult)
            
            def fastq2ValidationResult = validateInputFile(row.fastq_2, "fastq_2", rowNum)
            result.merge(fastq2ValidationResult)
            
            // Validate single_end flag if present
            if (row.containsKey('single_end')) {
                def singleEnd = row.single_end
                if (singleEnd && !['true', 'false', '1', '0', 'yes', 'no'].contains(singleEnd.toString().toLowerCase())) {
                    result.addWarning("Row ${rowNum}: Invalid single_end value '${singleEnd}'. Expected: true/false, 1/0, yes/no")
                }
            }
        }
        
        if (result.errors.isEmpty()) {
            result.setValid(true)
        }
        
        return result
    }
    
    /**
     * Validate individual input files (FASTQ files)
     * @param filePath Path to the input file
     * @param columnName Name of the column (for error reporting)
     * @param rowNum Row number (for error reporting)
     * @return ValidationResult object
     */
    static ValidationResult validateInputFile(Object filePath, String columnName, int rowNum) {
        def result = new ValidationResult()
        
        if (!filePath || filePath.toString().trim().isEmpty()) {
            result.addError("Row ${rowNum}: ${columnName} cannot be empty")
            return result
        }
        
        def pathStr = filePath.toString().trim()
        def file = new File(pathStr)
        
        if (!file.exists()) {
            result.addError("Row ${rowNum}: ${columnName} file does not exist: ${pathStr}")
            result.addSuggestion("Check the file path and ensure the file is accessible")
            return result
        }
        
        if (!file.canRead()) {
            result.addError("Row ${rowNum}: ${columnName} file is not readable: ${pathStr}")
            result.addSuggestion("Check file permissions")
            return result
        }
        
        // Validate FASTQ file extensions
        def validExtensions = ['.fastq', '.fq', '.fastq.gz', '.fq.gz']
        def hasValidExtension = validExtensions.any { pathStr.toLowerCase().endsWith(it) }
        
        if (!hasValidExtension) {
            result.addWarning("Row ${rowNum}: ${columnName} does not have a standard FASTQ extension: ${pathStr}")
            result.addSuggestion("Expected extensions: ${validExtensions.join(', ')}")
        }
        
        result.setValid(true)
        return result
    }
    
    /**
     * Validate database configurations
     * @param params Pipeline parameters containing database paths
     * @return ValidationResult object
     */
    static ValidationResult validateDatabases(Map params) {
        def result = new ValidationResult()
        
        // Required databases
        def requiredDatabases = [
            'kraken2_db': 'Kraken2 database',
            'checkv_db': 'CheckV database'
        ]
        
        // Optional databases (based on blast_options)
        def optionalDatabases = [:]
        if (params.blast_options?.contains('all') || params.blast_options?.contains('viruses')) {
            optionalDatabases['blastdb_viruses'] = 'BLAST viruses database'
        }
        if (params.blast_options?.contains('all') || params.blast_options?.contains('nt')) {
            optionalDatabases['blastdb_nt'] = 'BLAST NT database'
        }
        if (params.blast_options?.contains('all') || params.blast_options?.contains('nr')) {
            optionalDatabases['blastdb_nr'] = 'BLAST NR database'
        }
        if (params.blastx_tool == 'diamond') {
            optionalDatabases['diamonddb'] = 'DIAMOND database'
        }
        
        // Validate required databases
        requiredDatabases.each { paramName, description ->
            def dbResult = validateDatabase(params[paramName], description, true)
            result.merge(dbResult)
        }
        
        // Validate optional databases
        optionalDatabases.each { paramName, description ->
            if (params[paramName]) {
                def dbResult = validateDatabase(params[paramName], description, false)
                result.merge(dbResult)
            } else {
                result.addWarning("Optional database not configured: ${description}")
            }
        }
        
        if (result.errors.isEmpty()) {
            result.setValid(true)
        }
        
        return result
    }
    
    /**
     * Validate individual database
     * @param dbPath Path to the database
     * @param description Human-readable description
     * @param required Whether the database is required
     * @return ValidationResult object
     */
    static ValidationResult validateDatabase(Object dbPath, String description, boolean required) {
        def result = new ValidationResult()
        
        if (!dbPath || dbPath.toString().trim().isEmpty()) {
            if (required) {
                result.addDatabaseError("${description} path is required but not specified", "", description, [
                    required: true,
                    description: description
                ]).withSuggestion("Set the appropriate database parameter in your configuration")
            }
            return result
        }
        
        def pathStr = dbPath.toString().trim()
        
        // For Kraken2 and CheckV databases, check if directory exists
        if (description.toLowerCase().contains('kraken2') || description.toLowerCase().contains('checkv')) {
            def dbDir = new File(pathStr)
            if (!dbDir.exists()) {
                result.addError("${description} directory does not exist: ${pathStr}")
                result.addSuggestion("Download and install the ${description.toLowerCase()}")
                return result
            }
            if (!dbDir.isDirectory()) {
                result.addError("${description} path is not a directory: ${pathStr}")
                return result
            }
            if (!dbDir.canRead()) {
                result.addError("${description} directory is not readable: ${pathStr}")
                result.addSuggestion("Check directory permissions")
                return result
            }
        } else {
            // For BLAST and DIAMOND databases, check if files exist
            def dbFile = new File(pathStr)
            if (!dbFile.exists()) {
                // For BLAST databases, check for common extensions
                def blastExtensions = ['.nal', '.nhr', '.nin', '.nsq']
                def foundExtension = blastExtensions.find { ext ->
                    new File(pathStr + ext).exists()
                }
                
                if (!foundExtension && !pathStr.endsWith('.dmnd')) {
                    result.addError("${description} files not found: ${pathStr}")
                    result.addSuggestion("Ensure the database is properly installed and indexed")
                    return result
                }
            }
        }
        
        result.setValid(true)
        result.addInfo("${description} validation passed")
        return result
    }
    
    /**
     * Comprehensive validation of all inputs
     * @param samplesheetPath Path to samplesheet
     * @param params Pipeline parameters
     * @return ValidationResult object
     */
    static ValidationResult validateAllInputs(String samplesheetPath, Map params) {
        def result = new ValidationResult()
        
        // Validate samplesheet
        def samplesheetResult = validateSamplesheet(samplesheetPath)
        result.merge(samplesheetResult)
        
        // Validate databases
        def databaseResult = validateDatabases(params)
        result.merge(databaseResult)
        
        // Validate adapter file if specified
        if (params.adapters) {
            def adapterResult = validateAdapterFile(params.adapters)
            result.merge(adapterResult)
        }
        
        return result
    }
    
    /**
     * Validate adapter file
     * @param adapterPath Path to adapter file
     * @return ValidationResult object
     */
    static ValidationResult validateAdapterFile(Object adapterPath) {
        def result = new ValidationResult()
        
        if (!adapterPath) {
            result.setValid(true)
            return result
        }
        
        def pathStr = adapterPath.toString().trim()
        def file = new File(pathStr)
        
        if (!file.exists()) {
            result.addError("Adapter file does not exist: ${pathStr}")
            return result
        }
        
        if (!file.canRead()) {
            result.addError("Adapter file is not readable: ${pathStr}")
            return result
        }
        
        // Check if it's a FASTA file
        def validExtensions = ['.fa', '.fasta', '.fas']
        def hasValidExtension = validExtensions.any { pathStr.toLowerCase().endsWith(it) }
        
        if (!hasValidExtension) {
            result.addWarning("Adapter file does not have a standard FASTA extension: ${pathStr}")
            result.addSuggestion("Expected extensions: ${validExtensions.join(', ')}")
        }
        
        result.setValid(true)
        result.addInfo("Adapter file validation passed")
        return result
    }
    
    // Helper methods
    
    /**
     * Get file extension from path
     */
    private static String getFileExtension(String filePath) {
        def lastDot = filePath.lastIndexOf('.')
        return lastDot > 0 ? filePath.substring(lastDot + 1) : ''
    }
    
    /**
     * Parse CSV file
     */
    private static List<Map> parseCsvFile(String filePath) {
        def rows = []
        def headers = []
        
        new File(filePath).eachLine { line, lineNum ->
            if (lineNum == 1) {
                headers = parseCSVLine(line)
                return
            }
            
            def values = parseCSVLine(line)
            if (values.size() != headers.size()) {
                throw new IllegalArgumentException("Row ${lineNum}: Expected ${headers.size()} columns, found ${values.size()}")
            }
            
            def rowMap = [:]
            headers.eachWithIndex { header, index ->
                rowMap[header] = values[index]
            }
            rows.add(rowMap)
        }
        
        return rows
    }
    
    /**
     * Parse TSV file
     */
    private static List<Map> parseTsvFile(String filePath) {
        def rows = []
        def headers = []
        
        new File(filePath).eachLine { line, lineNum ->
            if (lineNum == 1) {
                headers = line.split('\t')
                return
            }
            
            def values = line.split('\t')
            if (values.size() != headers.size()) {
                throw new IllegalArgumentException("Row ${lineNum}: Expected ${headers.size()} columns, found ${values.size()}")
            }
            
            def rowMap = [:]
            headers.eachWithIndex { header, index ->
                rowMap[header] = values[index]
            }
            rows.add(rowMap)
        }
        
        return rows
    }
    
    /**
     * Parse Excel file (basic implementation)
     * Note: This is a simplified implementation. For production use,
     * consider using Apache POI or similar library for robust Excel parsing
     */
    private static List<Map> parseExcelFile(String filePath) {
        // For now, suggest converting Excel to CSV
        throw new UnsupportedOperationException(
            "Excel file parsing requires additional dependencies. " +
            "Please convert your Excel file to CSV format for now. " +
            "Future versions will include native Excel support."
        )
    }
    
    /**
     * Parse a CSV line handling quoted values and escaped commas
     */
    private static List<String> parseCSVLine(String line) {
        def values = []
        def current = new StringBuilder()
        def inQuotes = false
        def chars = line.toCharArray()
        
        for (int i = 0; i < chars.length; i++) {
            char c = chars[i]
            
            if (c == '"') {
                if (inQuotes && i + 1 < chars.length && chars[i + 1] == '"') {
                    // Escaped quote
                    current.append('"')
                    i++ // Skip next quote
                } else {
                    // Toggle quote state
                    inQuotes = !inQuotes
                }
            } else if (c == ',' && !inQuotes) {
                // End of field
                values.add(current.toString().trim())
                current = new StringBuilder()
            } else {
                current.append(c)
            }
        }
        
        // Add the last field
        values.add(current.toString().trim())
        
        return values
    }
}

/**
 * Validation result class to hold validation outcomes
 */
class ValidationResult {
    private boolean valid = false
    private List<String> errors = []
    private List<String> warnings = []
    private List<String> info = []
    private List<String> suggestions = []
    private List<PipelineError> structuredErrors = []
    
    boolean isValid() { return valid && errors.isEmpty() && !hasStructuredErrors() }
    void setValid(boolean valid) { this.valid = valid }
    
    List<String> getErrors() { return errors }
    List<String> getWarnings() { return warnings }
    List<String> getInfo() { return info }
    List<String> getSuggestions() { return suggestions }
    List<PipelineError> getStructuredErrors() { return structuredErrors }
    
    void addError(String error) { errors.add(error) }
    void addWarning(String warning) { warnings.add(warning) }
    void addInfo(String info) { this.info.add(info) }
    void addSuggestion(String suggestion) { suggestions.add(suggestion) }
    
    /**
     * Add structured error with enhanced information
     */
    void addStructuredError(PipelineError error) {
        structuredErrors.add(error)
        // Also add to legacy error list for backward compatibility
        errors.add(error.message)
        if (error.suggestion) {
            suggestions.add(error.suggestion)
        }
    }
    
    /**
     * Create and add input validation error
     */
    void addInputError(String message, String errorCode = "INPUT_VALIDATION", Map context = [:]) {
        def error = new InputValidationError(message, errorCode)
        if (context) {
            error.withContext(context)
        }
        addStructuredError(error)
    }
    
    /**
     * Create and add configuration error
     */
    void addConfigError(String message, String errorCode = "CONFIG_ERROR", Map context = [:]) {
        def error = new ConfigurationError(message, errorCode)
        if (context) {
            error.withContext(context)
        }
        addStructuredError(error)
    }
    
    /**
     * Create and add database error
     */
    void addDatabaseError(String message, String databasePath, String databaseType, Map context = [:]) {
        def error = new DatabaseError(message, databasePath, databaseType)
        if (context) {
            error.withContext(context)
        }
        addStructuredError(error)
    }
    
    boolean hasStructuredErrors() {
        return structuredErrors.any { it.severity in [ErrorSeverity.ERROR, ErrorSeverity.CRITICAL] }
    }
    
    boolean hasCriticalErrors() {
        return structuredErrors.any { it.severity == ErrorSeverity.CRITICAL }
    }
    
    void merge(ValidationResult other) {
        this.errors.addAll(other.errors)
        this.warnings.addAll(other.warnings)
        this.info.addAll(other.info)
        this.suggestions.addAll(other.suggestions)
        this.structuredErrors.addAll(other.structuredErrors)
        if (!other.isValid()) {
            this.valid = false
        }
    }
    
    /**
     * Generate actionable error report
     */
    Map generateErrorReport() {
        def report = [
            valid: isValid(),
            summary: [
                totalErrors: errors.size(),
                totalWarnings: warnings.size(),
                criticalErrors: structuredErrors.count { it.severity == ErrorSeverity.CRITICAL },
                recoverableErrors: structuredErrors.count { it.recoverable }
            ],
            errors: [],
            warnings: warnings,
            suggestions: suggestions,
            info: info
        ]
        
        // Add structured error information
        structuredErrors.each { error ->
            report.errors << [
                component: error.component,
                errorCode: error.errorCode,
                message: error.message,
                severity: error.severity.label,
                suggestion: error.suggestion,
                context: error.context,
                recoverable: error.recoverable,
                formattedMessage: error.getFormattedMessage()
            ]
        }
        
        // Add legacy errors that aren't structured
        def legacyErrors = errors.findAll { errorMsg ->
            !structuredErrors.any { it.message == errorMsg }
        }
        legacyErrors.each { errorMsg ->
            report.errors << [
                component: "UNKNOWN",
                errorCode: "LEGACY_ERROR",
                message: errorMsg,
                severity: "ERROR",
                suggestion: null,
                context: [:],
                recoverable: false,
                formattedMessage: "❌ ${errorMsg}"
            ]
        }
        
        return report
    }
    
    String toString() {
        def sb = new StringBuilder()
        sb.append("Validation Result: ${isValid() ? 'PASSED' : 'FAILED'}\n")
        
        // Show structured errors first
        if (structuredErrors) {
            sb.append("\nSTRUCTURED ERRORS:\n")
            structuredErrors.each { error ->
                sb.append("  ${error.getFormattedMessage()}\n")
            }
        }
        
        // Show legacy errors
        def legacyErrors = errors.findAll { errorMsg ->
            !structuredErrors.any { it.message == errorMsg }
        }
        if (legacyErrors) {
            sb.append("\nERRORS:\n")
            legacyErrors.each { sb.append("  ❌ ${it}\n") }
        }
        
        if (warnings) {
            sb.append("\nWARNINGS:\n")
            warnings.each { sb.append("  ⚠️  ${it}\n") }
        }
        
        if (suggestions) {
            sb.append("\nSUGGESTIONS:\n")
            suggestions.each { sb.append("  💡 ${it}\n") }
        }
        
        if (info) {
            sb.append("\nINFO:\n")
            info.each { sb.append("  ℹ️  ${it}\n") }
        }
        
        return sb.toString()
    }
}