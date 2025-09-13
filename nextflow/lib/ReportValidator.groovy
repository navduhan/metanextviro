/**
 * Report Content Validation and Quality Assurance System
 * 
 * This module provides comprehensive validation for report content,
 * file integrity checks, and quality assurance for generated reports.
 */

/**
 * Validation result severity levels
 */
enum ValidationSeverity {
    INFO('ℹ️', 'Info', 0),
    WARNING('⚠️', 'Warning', 1),
    ERROR('❌', 'Error', 2),
    CRITICAL('🔴', 'Critical', 3)
    
    final String icon
    final String label
    final int level
    
    ValidationSeverity(String icon, String label, int level) {
        this.icon = icon
        this.label = label
        this.level = level
    }
}

/**
 * Individual validation result
 */
class ValidationResult {
    String validator
    String component
    ValidationSeverity severity
    String message
    String suggestion
    Map<String, Object> context = [:]
    Date timestamp
    
    ValidationResult(String validator, String component, ValidationSeverity severity, String message) {
        this.validator = validator
        this.component = component
        this.severity = severity
        this.message = message
        this.timestamp = new Date()
    }
    
    ValidationResult withSuggestion(String suggestion) {
        this.suggestion = suggestion
        return this
    }
    
    ValidationResult withContext(String key, Object value) {
        this.context[key] = value
        return this
    }
    
    ValidationResult withContext(Map<String, Object> contextMap) {
        this.context.putAll(contextMap)
        return this
    }
    
    Map toMap() {
        return [
            validator: validator,
            component: component,
            severity: severity.name(),
            severityIcon: severity.icon,
            severityLabel: severity.label,
            message: message,
            suggestion: suggestion,
            context: context,
            timestamp: timestamp.format('yyyy-MM-dd HH:mm:ss')
        ]
    }
    
    String getFormattedMessage() {
        def sb = new StringBuilder()
        sb.append("${severity.icon} [${component}] ${message}")
        
        if (suggestion) {
            sb.append("\n💡 Suggestion: ${suggestion}")
        }
        
        if (context) {
            sb.append("\n📋 Context:")
            context.each { key, value ->
                sb.append("\n   ${key}: ${value}")
            }
        }
        
        return sb.toString()
    }
}

/**
 * Base validator interface
 */
abstract class BaseValidator {
    String name
    String description
    
    BaseValidator(String name, String description) {
        this.name = name
        this.description = description
    }
    
    abstract List<ValidationResult> validate(Map reportData)
    
    protected ValidationResult createResult(String component, ValidationSeverity severity, String message) {
        return new ValidationResult(name, component, severity, message)
    }
}

/**
 * File existence and integrity validator
 */
class FileIntegrityValidator extends BaseValidator {
    
    FileIntegrityValidator() {
        super("FileIntegrityValidator", "Validates file existence, accessibility, and basic integrity")
    }
    
    @Override
    List<ValidationResult> validate(Map reportData) {
        def results = []
        
        reportData.sections?.each { sectionId, sectionData ->
            def sectionName = sectionData.name ?: sectionId
            
            // Validate section has files if it's marked as successful
            if (sectionData.status == 'SUCCESS') {
                def files = sectionData.files ?: []
                
                if (files.isEmpty()) {
                    results << createResult(sectionName, ValidationSeverity.WARNING, 
                        "Section marked as successful but contains no files")
                        .withSuggestion("Verify that the process actually generated output files")
                }
                
                // Validate each file
                files.each { fileInfo ->
                    def filePath = fileInfo.path
                    def fileName = fileInfo.name
                    
                    if (!filePath) {
                        results << createResult(sectionName, ValidationSeverity.ERROR,
                            "File entry missing path information")
                            .withContext("fileName", fileName)
                        return
                    }
                    
                    def file = new File(filePath)
                    
                    // Check file existence
                    if (!file.exists()) {
                        results << createResult(sectionName, ValidationSeverity.ERROR,
                            "Referenced file does not exist: ${fileName}")
                            .withContext("filePath", filePath)
                            .withSuggestion("Check if the file was moved or deleted after report generation")
                    } else {
                        // Check file accessibility
                        if (!file.canRead()) {
                            results << createResult(sectionName, ValidationSeverity.ERROR,
                                "File exists but is not readable: ${fileName}")
                                .withContext("filePath", filePath)
                                .withSuggestion("Check file permissions")
                        }
                        
                        // Check file size
                        def actualSize = file.length()
                        def reportedSize = fileInfo.size
                        
                        if (reportedSize != null && actualSize != reportedSize) {
                            results << createResult(sectionName, ValidationSeverity.WARNING,
                                "File size mismatch for ${fileName}: reported ${reportedSize}, actual ${actualSize}")
                                .withContext("filePath", filePath)
                                .withSuggestion("File may have been modified after report generation")
                        }
                        
                        // Check for empty files
                        if (actualSize == 0) {
                            results << createResult(sectionName, ValidationSeverity.WARNING,
                                "File is empty: ${fileName}")
                                .withContext("filePath", filePath)
                                .withSuggestion("Verify that the process completed successfully")
                        }
                    }
                }
            }
        }
        
        return results
    }
}

/**
 * Content completeness validator
 */
class ContentCompletenessValidator extends BaseValidator {
    
    ContentCompletenessValidator() {
        super("ContentCompletenessValidator", "Validates completeness of report content and required sections")
    }
    
    @Override
    List<ValidationResult> validate(Map reportData) {
        def results = []
        
        // Define required sections
        def requiredSections = ['quality', 'taxonomy', 'assembly']
        def optionalSections = ['viral_analysis', 'functional_annotation', 'coverage_analysis']
        
        // Check for required sections
        requiredSections.each { sectionId ->
            def section = reportData.sections?.get(sectionId)
            
            if (!section) {
                results << createResult("Report Structure", ValidationSeverity.CRITICAL,
                    "Required section missing: ${sectionId}")
                    .withSuggestion("Ensure the pipeline includes all required analysis steps")
            } else if (section.status == 'MISSING' || section.status == 'FAILED') {
                results << createResult(section.name ?: sectionId, ValidationSeverity.ERROR,
                    "Required section failed or missing")
                    .withContext("sectionStatus", section.status)
                    .withSuggestion("Check pipeline logs for errors in this analysis step")
            }
        }
        
        // Check section content completeness
        reportData.sections?.each { sectionId, sectionData ->
            def sectionName = sectionData.name ?: sectionId
            
            // Check for content field
            if (!sectionData.content) {
                results << createResult(sectionName, ValidationSeverity.WARNING,
                    "Section missing content field")
                    .withSuggestion("Ensure section generator produces content")
            } else if (sectionData.content.trim().isEmpty()) {
                results << createResult(sectionName, ValidationSeverity.WARNING,
                    "Section has empty content")
                    .withSuggestion("Verify section generation logic")
            }
            
            // Check for summary field in successful sections
            if (sectionData.status == 'SUCCESS' && !sectionData.summary) {
                results << createResult(sectionName, ValidationSeverity.INFO,
                    "Section missing summary statistics")
                    .withSuggestion("Add summary generation to improve report quality")
            }
            
            // Check timestamp
            if (!sectionData.timestamp) {
                results << createResult(sectionName, ValidationSeverity.INFO,
                    "Section missing timestamp")
                    .withSuggestion("Add timestamp tracking for better traceability")
            }
        }
        
        // Check metadata completeness
        def metadata = reportData.metadata
        if (!metadata) {
            results << createResult("Report Metadata", ValidationSeverity.WARNING,
                "Report missing metadata section")
                .withSuggestion("Add metadata for better report traceability")
        } else {
            def requiredMetadataFields = ['generated_at', 'pipeline', 'version']
            requiredMetadataFields.each { field ->
                if (!metadata[field]) {
                    results << createResult("Report Metadata", ValidationSeverity.INFO,
                        "Missing metadata field: ${field}")
                        .withSuggestion("Add ${field} to report metadata")
                }
            }
        }
        
        return results
    }
}

/**
 * Data consistency validator
 */
class DataConsistencyValidator extends BaseValidator {
    
    DataConsistencyValidator() {
        super("DataConsistencyValidator", "Validates consistency of data across report sections")
    }
    
    @Override
    List<ValidationResult> validate(Map reportData) {
        def results = []
        
        // Check status consistency
        def processStatus = reportData.process_status
        def sections = reportData.sections
        
        if (processStatus && sections) {
            def reportedSuccessful = processStatus.successful_sections ?: 0
            def actualSuccessful = sections.values().count { it.status == 'SUCCESS' }
            
            if (reportedSuccessful != actualSuccessful) {
                results << createResult("Status Consistency", ValidationSeverity.WARNING,
                    "Mismatch in successful sections count: reported ${reportedSuccessful}, actual ${actualSuccessful}")
                    .withSuggestion("Check status calculation logic")
            }
            
            def reportedFailed = processStatus.failed_sections ?: 0
            def actualFailed = sections.values().count { it.status == 'ERROR' }
            
            if (reportedFailed != actualFailed) {
                results << createResult("Status Consistency", ValidationSeverity.WARNING,
                    "Mismatch in failed sections count: reported ${reportedFailed}, actual ${actualFailed}")
                    .withSuggestion("Check status calculation logic")
            }
        }
        
        // Check file count consistency
        sections?.each { sectionId, sectionData ->
            def sectionName = sectionData.name ?: sectionId
            def files = sectionData.files ?: []
            def summary = sectionData.summary ?: [:]
            
            // Check if summary file counts match actual file counts
            if (summary.total_files != null) {
                def actualFileCount = files.size()
                def reportedFileCount = summary.total_files
                
                if (actualFileCount != reportedFileCount) {
                    results << createResult(sectionName, ValidationSeverity.WARNING,
                        "File count mismatch: summary reports ${reportedFileCount}, actual ${actualFileCount}")
                        .withSuggestion("Verify file collection and counting logic")
                }
            }
            
            // Check file size consistency
            if (summary.total_size != null && !files.isEmpty()) {
                def actualTotalSize = files.sum { it.size ?: 0 }
                def reportedTotalSize = summary.total_size
                
                if (actualTotalSize != reportedTotalSize) {
                    results << createResult(sectionName, ValidationSeverity.INFO,
                        "Total size mismatch: summary reports ${reportedTotalSize}, calculated ${actualTotalSize}")
                        .withSuggestion("Verify size calculation logic")
                }
            }
        }
        
        return results
    }
}

/**
 * Quality assurance validator
 */
class QualityAssuranceValidator extends BaseValidator {
    
    QualityAssuranceValidator() {
        super("QualityAssuranceValidator", "Performs quality assurance checks on report content")
    }
    
    @Override
    List<ValidationResult> validate(Map reportData) {
        def results = []
        
        // Check for suspicious patterns
        reportData.sections?.each { sectionId, sectionData ->
            def sectionName = sectionData.name ?: sectionId
            def files = sectionData.files ?: []
            
            // Check for unusually small files
            files.each { fileInfo ->
                def size = fileInfo.size ?: 0
                def name = fileInfo.name
                
                if (size > 0 && size < 100) { // Files smaller than 100 bytes
                    results << createResult(sectionName, ValidationSeverity.INFO,
                        "Unusually small file detected: ${name} (${size} bytes)")
                        .withSuggestion("Verify that the analysis completed successfully")
                }
                
                // Check for suspicious file extensions
                if (name && !hasValidExtension(name, sectionId)) {
                    results << createResult(sectionName, ValidationSeverity.WARNING,
                        "Unexpected file extension for section: ${name}")
                        .withSuggestion("Verify file type matches expected output")
                }
            }
            
            // Check for missing expected file types
            def expectedExtensions = getExpectedExtensions(sectionId)
            if (expectedExtensions && !files.isEmpty()) {
                def actualExtensions = files.collect { getFileExtension(it.name) }.unique()
                def missingExtensions = expectedExtensions - actualExtensions
                
                if (missingExtensions) {
                    results << createResult(sectionName, ValidationSeverity.INFO,
                        "Missing expected file types: ${missingExtensions.join(', ')}")
                        .withSuggestion("Check if all expected outputs were generated")
                }
            }
        }
        
        // Check overall report quality
        def totalSections = reportData.sections?.size() ?: 0
        def successfulSections = reportData.sections?.values()?.count { it.status == 'SUCCESS' } ?: 0
        
        if (totalSections > 0) {
            def successRate = (successfulSections / totalSections) * 100
            
            if (successRate < 50) {
                results << createResult("Overall Quality", ValidationSeverity.ERROR,
                    "Low success rate: ${successRate.round(1)}%")
                    .withSuggestion("Review pipeline configuration and input data quality")
            } else if (successRate < 80) {
                results << createResult("Overall Quality", ValidationSeverity.WARNING,
                    "Moderate success rate: ${successRate.round(1)}%")
                    .withSuggestion("Consider investigating failed sections")
            }
        }
        
        return results
    }
    
    private boolean hasValidExtension(String filename, String sectionId) {
        def expectedExtensions = getExpectedExtensions(sectionId)
        if (!expectedExtensions) return true
        
        def extension = getFileExtension(filename)
        return extension in expectedExtensions
    }
    
    private String getFileExtension(String filename) {
        def lastDot = filename.lastIndexOf('.')
        return lastDot >= 0 ? filename.substring(lastDot + 1).toLowerCase() : ''
    }
    
    private List<String> getExpectedExtensions(String sectionId) {
        def extensionMap = [
            'quality': ['html', 'zip'],
            'taxonomy': ['report', 'txt', 'kraken', 'output'],
            'assembly': ['fa', 'fasta', 'fna'],
            'viral_analysis': ['tsv', 'txt', 'csv', 'fasta'],
            'functional_annotation': ['txt', 'tsv', 'xml', 'out'],
            'coverage_analysis': ['txt', 'tsv', 'cov', 'png', 'pdf'],
            'assembly_quality': ['txt', 'tsv', 'html', 'pdf']
        ]
        
        return extensionMap[sectionId] ?: []
    }
}

/**
 * HTML content validator
 */
class HTMLContentValidator extends BaseValidator {
    
    HTMLContentValidator() {
        super("HTMLContentValidator", "Validates HTML report content and structure")
    }
    
    @Override
    List<ValidationResult> validate(Map reportData) {
        def results = []
        
        // Check for HTML content in sections
        reportData.sections?.each { sectionId, sectionData ->
            def sectionName = sectionData.name ?: sectionId
            def content = sectionData.content
            
            if (content && content.contains('<')) {
                // Basic HTML validation
                if (!content.contains('</')) {
                    results << createResult(sectionName, ValidationSeverity.WARNING,
                        "HTML content appears to have unclosed tags")
                        .withSuggestion("Verify HTML structure in section content")
                }
                
                // Check for common HTML issues
                if (content.contains('<script')) {
                    results << createResult(sectionName, ValidationSeverity.WARNING,
                        "Section contains script tags")
                        .withSuggestion("Ensure scripts are safe and necessary")
                }
                
                // Check for broken links
                def linkPattern = /href=['"]([^'"]+)['"]/
                def matcher = content =~ linkPattern
                matcher.each { match ->
                    def link = match[1]
                    if (link.startsWith('http')) {
                        // External link - could validate if needed
                    } else {
                        // Local file link - check if file exists
                        def linkFile = new File(link)
                        if (!linkFile.exists()) {
                            results << createResult(sectionName, ValidationSeverity.WARNING,
                                "Broken link detected: ${link}")
                                .withSuggestion("Verify linked file exists")
                        }
                    }
                }
            }
        }
        
        return results
    }
}

/**
 * Comprehensive report validator
 */
class ReportValidator {
    private List<BaseValidator> validators = []
    
    ReportValidator() {
        // Initialize default validators
        validators << new FileIntegrityValidator()
        validators << new ContentCompletenessValidator()
        validators << new DataConsistencyValidator()
        validators << new QualityAssuranceValidator()
        validators << new HTMLContentValidator()
    }
    
    /**
     * Add custom validator
     */
    void addValidator(BaseValidator validator) {
        validators << validator
    }
    
    /**
     * Remove validator by name
     */
    void removeValidator(String validatorName) {
        validators.removeAll { it.name == validatorName }
    }
    
    /**
     * Validate report data
     */
    ValidationReport validateReport(Map reportData) {
        def allResults = []
        def validatorResults = [:]
        
        validators.each { validator ->
            try {
                def results = validator.validate(reportData)
                allResults.addAll(results)
                validatorResults[validator.name] = [
                    status: 'SUCCESS',
                    resultCount: results.size(),
                    results: results.collect { it.toMap() }
                ]
            } catch (Exception e) {
                def errorResult = new ValidationResult(
                    validator.name, 
                    "Validator Error", 
                    ValidationSeverity.ERROR,
                    "Validator failed: ${e.message}"
                )
                allResults << errorResult
                validatorResults[validator.name] = [
                    status: 'ERROR',
                    error: e.message,
                    resultCount: 1,
                    results: [errorResult.toMap()]
                ]
            }
        }
        
        return new ValidationReport(allResults, validatorResults)
    }
}

/**
 * Validation report container
 */
class ValidationReport {
    List<ValidationResult> results
    Map<String, Object> validatorResults
    Date timestamp
    
    ValidationReport(List<ValidationResult> results, Map<String, Object> validatorResults) {
        this.results = results
        this.validatorResults = validatorResults
        this.timestamp = new Date()
    }
    
    /**
     * Get results by severity
     */
    List<ValidationResult> getResultsBySeverity(ValidationSeverity severity) {
        return results.findAll { it.severity == severity }
    }
    
    /**
     * Get results by component
     */
    List<ValidationResult> getResultsByComponent(String component) {
        return results.findAll { it.component == component }
    }
    
    /**
     * Check if validation passed
     */
    boolean isPassed() {
        return !results.any { it.severity in [ValidationSeverity.ERROR, ValidationSeverity.CRITICAL] }
    }
    
    /**
     * Get highest severity level
     */
    ValidationSeverity getHighestSeverity() {
        if (results.isEmpty()) return ValidationSeverity.INFO
        
        return results.collect { it.severity }.max { it.level }
    }
    
    /**
     * Get validation summary
     */
    Map getSummary() {
        def severityCounts = [:]
        ValidationSeverity.values().each { severity ->
            severityCounts[severity.name()] = results.count { it.severity == severity }
        }
        
        return [
            timestamp: timestamp.format('yyyy-MM-dd HH:mm:ss'),
            totalResults: results.size(),
            passed: isPassed(),
            highestSeverity: getHighestSeverity().name(),
            severityCounts: severityCounts,
            validatorCount: validatorResults.size(),
            successfulValidators: validatorResults.count { it.value.status == 'SUCCESS' }
        ]
    }
    
    /**
     * Generate detailed report
     */
    Map generateDetailedReport() {
        return [
            summary: getSummary(),
            results: results.collect { it.toMap() },
            validators: validatorResults,
            recommendations: generateRecommendations()
        ]
    }
    
    /**
     * Generate recommendations based on validation results
     */
    List<String> generateRecommendations() {
        def recommendations = []
        
        def criticalResults = getResultsBySeverity(ValidationSeverity.CRITICAL)
        def errorResults = getResultsBySeverity(ValidationSeverity.ERROR)
        def warningResults = getResultsBySeverity(ValidationSeverity.WARNING)
        
        if (criticalResults) {
            recommendations << "🔴 Critical issues found: Address immediately to ensure report reliability"
        }
        
        if (errorResults) {
            recommendations << "❌ Errors detected: Review and fix to improve report quality"
        }
        
        if (warningResults) {
            recommendations << "⚠️ Warnings present: Consider addressing to enhance report completeness"
        }
        
        if (isPassed()) {
            recommendations << "✅ Validation passed: Report meets quality standards"
        }
        
        // Add specific recommendations based on common issues
        def missingFiles = results.findAll { it.message.contains("does not exist") }
        if (missingFiles) {
            recommendations << "📁 Missing files detected: Verify pipeline output integrity"
        }
        
        def emptyFiles = results.findAll { it.message.contains("empty") }
        if (emptyFiles) {
            recommendations << "📄 Empty files found: Check process completion status"
        }
        
        return recommendations
    }
    
    /**
     * Export validation report to JSON
     */
    void exportToJson(String filePath) {
        def report = generateDetailedReport()
        def json = new groovy.json.JsonBuilder(report)
        
        new File(filePath).text = json.toPrettyString()
    }
    
    /**
     * Export validation summary to text
     */
    void exportSummaryToText(String filePath) {
        def summary = getSummary()
        def text = new StringBuilder()
        
        text << "Report Validation Summary\n"
        text << "========================\n\n"
        text << "Validation Time: ${summary.timestamp}\n"
        text << "Overall Status: ${summary.passed ? 'PASSED' : 'FAILED'}\n"
        text << "Highest Severity: ${summary.highestSeverity}\n"
        text << "Total Issues: ${summary.totalResults}\n\n"
        
        text << "Issue Breakdown:\n"
        summary.severityCounts.each { severity, count ->
            if (count > 0) {
                text << "  ${severity}: ${count}\n"
            }
        }
        
        text << "\nValidators: ${summary.successfulValidators}/${summary.validatorCount} successful\n\n"
        
        if (results) {
            text << "Issues Found:\n"
            results.each { result ->
                text << "${result.severity.icon} [${result.component}] ${result.message}\n"
                if (result.suggestion) {
                    text << "   💡 ${result.suggestion}\n"
                }
                text << "\n"
            }
        }
        
        def recommendations = generateRecommendations()
        if (recommendations) {
            text << "Recommendations:\n"
            recommendations.each { recommendation ->
                text << "• ${recommendation}\n"
            }
        }
        
        new File(filePath).text = text.toString()
    }
}