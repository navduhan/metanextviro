# Enhanced Error Handling System

The MetaNextViro pipeline now includes a comprehensive error handling system that provides structured error reporting, automatic recovery strategies, and graceful degradation for improved reliability and user experience.

## Overview

The enhanced error handling system consists of several key components:

1. **Structured Error Classes** - Provide detailed error information with actionable suggestions
2. **Error Recovery Strategies** - Automatically attempt to recover from common failures
3. **Process Failure Tracking** - Track and document all process failures for reporting
4. **Graceful Degradation** - Continue pipeline execution when optional components fail
5. **Enhanced Reporting** - Generate comprehensive reports that include error information

## Key Features

### Structured Error Classes

The system provides specific error classes for different types of failures:

- `InputValidationError` - Input file and parameter validation errors
- `ConfigurationError` - Configuration and setup errors
- `ResourceError` - Memory, CPU, and time allocation errors
- `ProcessExecutionError` - Process execution failures
- `DatabaseError` - Database access and validation errors
- `EnvironmentError` - Environment setup and dependency errors

Each error includes:
- **Error Code** - Unique identifier for the error type
- **Component** - Which part of the pipeline failed
- **Severity Level** - CRITICAL, ERROR, WARNING, or INFO
- **Suggestion** - Actionable advice for resolving the error
- **Context** - Additional information about the failure
- **Recoverability** - Whether the error can be automatically recovered

### Error Recovery Strategies

The system includes automatic recovery strategies for common failures:

#### Memory Retry Strategy
- Detects out-of-memory errors
- Automatically retries with doubled memory allocation
- Configurable maximum retry attempts

#### Time Retry Strategy
- Detects timeout errors
- Automatically retries with doubled time allocation
- Prevents infinite retry loops

#### Database Fallback Strategy
- Detects database access errors
- Attempts to use alternative databases when available
- Provides clear guidance when no fallback is available

### Process Failure Tracking

The `ProcessFailureTracker` class maintains comprehensive records of:
- Process execution status (completed, failed, skipped)
- Failure timestamps and context
- Error severity and recoverability
- Recovery attempts and outcomes

### Graceful Degradation

Optional processes can be gracefully skipped when they fail:
- **Optional Processes**: CheckV, VirFinder, Coverage plots, Heatmaps, Krona, HTML reports, MultiQC
- **Required Processes**: Input validation, Quality control, Assembly, Taxonomic classification

When an optional process fails:
1. The error is logged and documented
2. The process is marked as "skipped"
3. The pipeline continues with remaining processes
4. The final report includes information about skipped analyses

## Usage

### Basic Error Handling

```groovy
// Create a structured error
def error = new InputValidationError("File not found: sample.fastq", "FILE_NOT_FOUND")
    .withSuggestion("Check the file path and ensure the file exists")
    .withContext("filePath", "/path/to/sample.fastq")
    .asRecoverable()

// Handle the error
def errorHandler = new EnhancedErrorHandler()
def result = errorHandler.handleError(error, "FASTQC", [memory: "4.GB"])

if (result.recovered) {
    println "Error recovered: ${result.message}"
} else if (result.degraded) {
    println "Process degraded gracefully: ${result.message}"
} else {
    println "Error requires manual intervention: ${result.message}"
}
```

### Enhanced Validation

```groovy
// Use enhanced validation result
def validator = new InputValidator()
def result = validator.validateSamplesheet("/path/to/samplesheet.csv")

// Check for structured errors
if (result.hasStructuredErrors()) {
    def errorReport = result.generateErrorReport()
    
    errorReport.errors.each { error ->
        println "Error: ${error.formattedMessage}"
        if (error.suggestion) {
            println "Suggestion: ${error.suggestion}"
        }
    }
}
```

### Process Integration

```nextflow
process EXAMPLE_PROCESS {
    label 'process_medium'
    errorStrategy { task.attempt <= 3 ? 'retry' : 'ignore' }
    
    input:
        path input_file
        
    output:
        path "output.txt", emit: result
        path "error_info.json", emit: error_info, optional: true
        
    script:
    """
    # Your process logic here
    
    # On error, create structured error information
    if [ \$? -ne 0 ]; then
        cat > error_info.json << EOF
{
    "process_name": "${task.process}",
    "error_message": "Process failed with exit code \$?",
    "severity": "ERROR",
    "timestamp": "\$(date -Iseconds)",
    "context": {
        "attempt": ${task.attempt},
        "memory": "${task.memory}",
        "cpus": ${task.cpus}
    },
    "recoverable": true
}
EOF
    fi
    """
}
```

## Enhanced Reporting

The enhanced reporting system generates comprehensive HTML reports that include:

### Report Sections
- **Pipeline Summary** - Overall status and success rate
- **Process Status** - Individual process completion status
- **Failure Summary** - Detailed information about any failures
- **Section Reports** - Results from each analysis component
- **Recovery Information** - Details about any recovery attempts

### Error Information in Reports
- Visual indicators for process status (✅ success, ❌ error, ⚠️ warning, ℹ️ skipped)
- Detailed error messages with suggestions
- Recovery attempt information
- Impact assessment (critical vs. optional failures)

### Report Features
- **Graceful Degradation** - Reports are generated even with partial failures
- **Missing File Handling** - Placeholder content for missing results
- **Status Tracking** - Clear indication of what completed successfully
- **Actionable Information** - Specific guidance for resolving issues

## Configuration

### Enable Enhanced Error Handling

Add to your `nextflow.config`:

```groovy
// Enable enhanced error handling
params {
    enhanced_error_handling = true
    graceful_degradation = true
    max_retry_attempts = 3
}

// Configure error recovery
process {
    errorStrategy = { task.attempt <= params.max_retry_attempts ? 'retry' : 'ignore' }
    
    // Memory scaling on retry
    memory = { 4.GB * task.attempt }
    time = { 2.h * task.attempt }
}
```

### Optional Process Configuration

Define which processes are optional:

```groovy
params {
    optional_processes = [
        'CHECKV', 'VIRFINDER', 'COVERAGE_PLOT', 
        'HEATMAP', 'KRONA', 'HTML_REPORT', 'MULTIQC'
    ]
}
```

## Integration with Existing Pipeline

### 1. Update Process Modules

Modify existing process modules to use enhanced error handling:

```nextflow
// Add error tracking to process outputs
output:
    path "results/*", emit: results
    path "process_status.json", emit: status, optional: true
```

### 2. Use Enhanced Final Report

Replace the existing final report with the enhanced version:

```nextflow
include { enhanced_final_report } from './nextflow/modules/enhanced_final_report'

workflow {
    // ... your pipeline processes ...
    
    // Generate enhanced final report
    enhanced_final_report(
        kraken2_results,
        fastqc_results,
        // ... other outputs ...
        process_failures.collect().ifEmpty([])
    )
}
```

### 3. Add Error Tracking Workflow

Include the error tracking subworkflow:

```nextflow
include { ERROR_TRACKING } from './nextflow/subworkflow/error_tracking'

workflow {
    // ... your pipeline processes ...
    
    // Track errors and generate reports
    ERROR_TRACKING(
        all_process_outputs.collect(),
        process_failures.collect()
    )
}
```

## Benefits

### For Users
- **Clear Error Messages** - Understand exactly what went wrong and how to fix it
- **Automatic Recovery** - Many common issues are resolved automatically
- **Partial Results** - Get useful results even when some analyses fail
- **Actionable Reports** - Know exactly what to do to resolve issues

### For Developers
- **Structured Debugging** - Comprehensive error information for troubleshooting
- **Consistent Error Handling** - Standardized approach across all processes
- **Easy Integration** - Simple to add to existing processes
- **Extensible Design** - Easy to add new error types and recovery strategies

### For Pipeline Reliability
- **Graceful Degradation** - Pipeline continues running when possible
- **Resource Optimization** - Automatic resource scaling on retry
- **Comprehensive Logging** - Complete audit trail of all issues
- **Recovery Strategies** - Automatic resolution of common problems

## Troubleshooting

### Common Issues

1. **Memory Errors**
   - Automatically retried with increased memory
   - Check system memory availability
   - Consider using high-memory partitions

2. **Database Errors**
   - Verify database paths in configuration
   - Check file permissions and accessibility
   - Ensure databases are properly indexed

3. **Time Limit Errors**
   - Automatically retried with increased time
   - Consider using longer-running partitions
   - Check for infinite loops in processes

### Manual Intervention Required

Some errors require manual intervention:
- Configuration errors (incorrect paths, missing parameters)
- Environment setup issues (missing dependencies, version conflicts)
- Critical process failures (core pipeline components)

The enhanced error handling system will clearly indicate when manual intervention is required and provide specific guidance for resolution.