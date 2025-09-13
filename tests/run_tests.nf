#!/usr/bin/env nextflow

/**
 * Test Runner for MetaNextViro Pipeline Improvements
 * 
 * Executes the comprehensive test suite and generates reports
 * Requirements: 1.1, 1.2, 1.3, 6.1, 6.2, 6.3, 6.4
 */

nextflow.enable.dsl = 2

// Import the comprehensive test suite
include { COMPREHENSIVE_TEST_SUITE } from './comprehensive_test_suite.nf'

workflow {
    main:
    
    log.info """
    =====================================
    MetaNextViro Test Suite Runner
    =====================================
    
    Starting comprehensive testing framework...
    
    Test Categories:
    - Unit Tests (Configuration, Partition Selection, Input Validation, Resource Allocation)
    - Integration Tests (Profile Integration, Environment Integration, End-to-End)
    - Performance Tests (Resource Utilization, Scalability, Memory Optimization)
    
    """
    
    // Run the comprehensive test suite
    COMPREHENSIVE_TEST_SUITE()
    
    // The test suite will generate its own reports
    log.info """
    
    =====================================
    Test Suite Execution Complete
    =====================================
    
    Check the generated test report files for detailed results.
    """
}

