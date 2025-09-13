#!/usr/bin/env nextflow

/*
 * Configuration Validation Script
 * Validates pipeline configuration for consistency and correctness
 */

nextflow.enable.dsl = 2

// Import validation library
import ConfigValidator

workflow {
    main:
        validateConfiguration()
}

def validateConfiguration() {
    log.info "=== MetaNextViro Configuration Validation ==="
    log.info ""
    
    def allResults = [:]
    
    // Validate resource configuration
    log.info "Validating resource configuration..."
    allResults.resources = ConfigValidator.validateResourceConfiguration(params)
    
    // Validate profile consistency
    log.info "Validating profile consistency..."
    allResults.profiles = ConfigValidator.validateProfileConsistency(workflow.config)
    
    // Validate executor configuration
    if (workflow.executor) {
        log.info "Validating executor configuration (${workflow.executor})..."
        allResults.executor = ConfigValidator.validateExecutorConfiguration(
            workflow.config, workflow.executor
        )
    }
    
    // Validate database paths
    log.info "Validating database paths..."
    allResults.databases = ConfigValidator.validateDatabasePaths(params)
    
    // Generate and display validation report
    def report = ConfigValidator.generateValidationReport(allResults)
    
    log.info ""
    log.info report.report
    
    // Exit with error code if validation failed
    if (report.hasErrors) {
        log.error "Configuration validation failed with ${report.errorCount} errors"
        System.exit(1)
    } else if (report.hasWarnings) {
        log.warn "Configuration validation completed with ${report.warningCount} warnings"
    } else {
        log.info "Configuration validation passed successfully"
    }
}