#!/usr/bin/env nextflow

/**
 * Comprehensive Testing Framework for MetaNextViro Pipeline Improvements
 * 
 * This test suite provides comprehensive testing for:
 * - Configuration validation functions
 * - Partition selection and resource allocation
 * - End-to-end tests for different execution profiles and environments
 * - Performance tests for resource utilization and scalability
 * 
 * Requirements: 1.1, 1.2, 1.3, 6.1, 6.2, 6.3, 6.4
 */

nextflow.enable.dsl = 2

// Import test modules
include { TEST_CONFIG_VALIDATION } from './unit/config_validation_tests.nf'
include { TEST_PARTITION_SELECTION } from './unit/partition_selection_tests.nf'
include { TEST_INPUT_VALIDATION } from './unit/input_validation_tests.nf'
include { TEST_RESOURCE_ALLOCATION } from './unit/resource_allocation_tests.nf'
include { TEST_INTEGRATION_PROFILES } from './integration/profile_integration_tests.nf'
include { TEST_INTEGRATION_ENVIRONMENTS } from './integration/environment_integration_tests.nf'
include { TEST_END_TO_END } from './integration/end_to_end_tests.nf'
include { TEST_PERFORMANCE } from './performance/performance_tests.nf'

workflow COMPREHENSIVE_TEST_SUITE {
    main:
    
    log.info """
    =====================================
    MetaNextViro Comprehensive Test Suite
    =====================================
    
    Running comprehensive tests for pipeline improvements...
    """
    
    // Initialize test results tracking
    def testResults = [:]
    
    // Unit Tests
    log.info "=== UNIT TESTS ==="
    
    // Test 1: Configuration Validation
    log.info "Running configuration validation tests..."
    config_results = TEST_CONFIG_VALIDATION()
    testResults.config_validation = config_results
    
    // Test 2: Partition Selection Logic
    log.info "Running partition selection tests..."
    partition_results = TEST_PARTITION_SELECTION()
    testResults.partition_selection = partition_results
    
    // Test 3: Input Validation
    log.info "Running input validation tests..."
    input_results = TEST_INPUT_VALIDATION()
    testResults.input_validation = input_results
    
    // Test 4: Resource Allocation
    log.info "Running resource allocation tests..."
    resource_results = TEST_RESOURCE_ALLOCATION()
    testResults.resource_allocation = resource_results
    
    // Integration Tests
    log.info "=== INTEGRATION TESTS ==="
    
    // Test 5: Profile Integration
    log.info "Running profile integration tests..."
    profile_results = TEST_INTEGRATION_PROFILES()
    testResults.profile_integration = profile_results
    
    // Test 6: Environment Integration
    log.info "Running environment integration tests..."
    environment_results = TEST_INTEGRATION_ENVIRONMENTS()
    testResults.environment_integration = environment_results
    
    // Test 7: End-to-End Testing
    log.info "Running end-to-end tests..."
    e2e_results = TEST_END_TO_END()
    testResults.end_to_end = e2e_results
    
    // Performance Tests
    log.info "=== PERFORMANCE TESTS ==="
    
    // Test 8: Performance and Scalability
    log.info "Running performance tests..."
    performance_results = TEST_PERFORMANCE()
    testResults.performance = performance_results
    
    // Generate comprehensive test report
    generateTestReport(testResults)
    
    emit:
    results = testResults
}

def generateTestReport(testResults) {
    def report = []
    def totalTests = 0
    def passedTests = 0
    def failedTests = 0
    
    report << "="*60
    report << "COMPREHENSIVE TEST SUITE RESULTS"
    report << "="*60
    report << ""
    
    testResults.each { category, results ->
        report << "## ${category.toUpperCase().replace('_', ' ')}"
        
        if (results.tests) {
            results.tests.each { test ->
                def status = test.passed ? "✅ PASS" : "❌ FAIL"
                report << "  ${status} ${test.name}"
                if (!test.passed && test.error) {
                    report << "    Error: ${test.error}"
                }
                totalTests++
                if (test.passed) passedTests++ else failedTests++
            }
        }
        
        if (results.summary) {
            report << "  Summary: ${results.summary}"
        }
        
        report << ""
    }
    
    report << "="*60
    report << "OVERALL SUMMARY"
    report << "="*60
    report << "Total Tests: ${totalTests}"
    report << "Passed: ${passedTests}"
    report << "Failed: ${failedTests}"
    report << "Success Rate: ${totalTests > 0 ? (passedTests * 100 / totalTests).round(2) : 0}%"
    
    if (failedTests > 0) {
        report << ""
        report << "❌ TEST SUITE FAILED - ${failedTests} test(s) failed"
    } else {
        report << ""
        report << "✅ ALL TESTS PASSED"
    }
    
    // Write report to file
    def reportFile = new File("test_results_${new Date().format('yyyyMMdd_HHmmss')}.txt")
    reportFile.text = report.join('\n')
    
    // Print summary to console
    log.info report.join('\n')
}

// Main workflow execution
workflow {
    COMPREHENSIVE_TEST_SUITE()
}