#!/usr/bin/env nextflow

/*
 * Test script for SLURM partition selection system
 * This script validates the intelligent partition selection logic
 */

// Import required libraries
import nextflow.util.MemoryUnit
import nextflow.util.Duration

// Include configuration
includeConfig '../configs/slurm.config'

// Test parameters
params {
    test_mode = true
    enable_partition_validation = true
    partition_selection_strategy = 'intelligent'
    
    // Test partition configuration
    partitions = [
        compute: 'compute',
        bigmem: 'bigmem',
        gpu: 'gpu',
        quick: 'quickq'
    ]
    
    partition_thresholds = [
        bigmem_memory_gb: 128,
        quick_time_hours: 1,
        quick_memory_gb: 16,
        gpu_labels: ['process_gpu']
    ]
    
    partition_fallbacks = [
        bigmem: ['compute'],
        gpu: ['compute'],
        quick: ['compute'],
        compute: []
    ]
    
    default_partition = 'compute'
}

workflow TEST_PARTITION_SELECTION {
    
    main:
        // Test cases for partition selection
        def testCases = [
            // Low resource process - should go to quick partition
            [
                label: 'process_low',
                memory: '4.GB',
                time: '30.m',
                cpus: 2,
                expected: 'quickq'
            ],
            // Medium resource process - should go to compute partition
            [
                label: 'process_medium',
                memory: '16.GB',
                time: '4.h',
                cpus: 8,
                expected: 'compute'
            ],
            // High resource process - should go to compute partition
            [
                label: 'process_high',
                memory: '32.GB',
                time: '8.h',
                cpus: 16,
                expected: 'compute'
            ],
            // Memory intensive process - should go to bigmem partition
            [
                label: 'process_memory_intensive',
                memory: '256.GB',
                time: '12.h',
                cpus: 8,
                expected: 'bigmem'
            ],
            // GPU process - should go to gpu partition
            [
                label: 'process_gpu',
                memory: '32.GB',
                time: '8.h',
                cpus: 8,
                expected: 'gpu'
            ],
            // Quick process - should go to quick partition
            [
                label: 'process_quick',
                memory: '8.GB',
                time: '30.m',
                cpus: 2,
                expected: 'quickq'
            ]
        ]
        
        // Run partition selection tests
        testResults = Channel.from(testCases)
            | map { testCase ->
                def selectedPartition = selectPartition(
                    testCase.label, 
                    testCase.memory, 
                    testCase.time
                )
                
                def clusterOptions = getClusterOptions(
                    testCase.label,
                    testCase.memory,
                    testCase.cpus
                )
                
                return [
                    label: testCase.label,
                    memory: testCase.memory,
                    time: testCase.time,
                    cpus: testCase.cpus,
                    expected: testCase.expected,
                    selected: selectedPartition,
                    cluster_options: clusterOptions,
                    passed: selectedPartition == testCase.expected
                ]
            }
            | collect
        
        // Generate test report
        GENERATE_TEST_REPORT(testResults)
        
    emit:
        results = testResults
}

process GENERATE_TEST_REPORT {
    label 'process_low'
    
    input:
    val testResults
    
    output:
    path "partition_selection_test_report.txt"
    
    script:
    """
    echo "=== SLURM Partition Selection Test Report ===" > partition_selection_test_report.txt
    echo "" >> partition_selection_test_report.txt
    echo "Test Date: \$(date)" >> partition_selection_test_report.txt
    echo "Configuration:" >> partition_selection_test_report.txt
    echo "  Strategy: ${params.partition_selection_strategy}" >> partition_selection_test_report.txt
    echo "  Partitions: ${params.partitions}" >> partition_selection_test_report.txt
    echo "  Thresholds: ${params.partition_thresholds}" >> partition_selection_test_report.txt
    echo "" >> partition_selection_test_report.txt
    echo "Test Results:" >> partition_selection_test_report.txt
    echo "=============" >> partition_selection_test_report.txt
    
    # Process test results
    cat << 'EOF' >> partition_selection_test_report.txt
${testResults.collect { result ->
    def status = result.passed ? "✅ PASS" : "❌ FAIL"
    return """
${status} ${result.label}
  Memory: ${result.memory}, Time: ${result.time}, CPUs: ${result.cpus}
  Expected: ${result.expected}
  Selected: ${result.selected}
  Cluster Options: ${result.cluster_options}
"""
}.join('\n')}
EOF
    
    # Summary
    passed=\$(echo '${testResults.findAll { it.passed }.size()}')
    total=\$(echo '${testResults.size()}')
    failed=\$((total - passed))
    
    echo "" >> partition_selection_test_report.txt
    echo "=== Summary ===" >> partition_selection_test_report.txt
    echo "Total Tests: \$total" >> partition_selection_test_report.txt
    echo "Passed: \$passed" >> partition_selection_test_report.txt
    echo "Failed: \$failed" >> partition_selection_test_report.txt
    
    if [ \$failed -eq 0 ]; then
        echo "✅ All partition selection tests PASSED" >> partition_selection_test_report.txt
    else
        echo "❌ \$failed partition selection tests FAILED" >> partition_selection_test_report.txt
    fi
    """
}

workflow {
    TEST_PARTITION_SELECTION()
}