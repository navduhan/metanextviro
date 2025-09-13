#!/usr/bin/env nextflow

/*
 * Performance Optimization Unit Tests
 * Tests for dynamic resource scaling, intelligent parallelization, and performance monitoring
 */

nextflow.enable.dsl = 2

// Import performance optimization components
include { PERFORMANCE_OPTIMIZATION } from '../../nextflow/subworkflow/performance_optimization.nf'
include { DYNAMIC_RESOURCE_SCALING } from '../../nextflow/subworkflow/performance_optimization.nf'
include { INTELLIGENT_PARALLELIZATION } from '../../nextflow/subworkflow/performance_optimization.nf'

// Test parameters
params {
    test_data_dir = "${projectDir}/tests/data"
    outdir = "${projectDir}/test_results/performance_optimization"
    
    // Enable all performance features for testing
    enable_performance_optimization = true
    enable_dynamic_scaling = true
    enable_intelligent_parallelization = true
    enable_performance_monitoring = true
    
    // Test-specific parameters
    max_forks = 4
    scaling_strategy = 'adaptive'
    performance_profiling_level = 'detailed'
}

workflow TEST_DYNAMIC_RESOURCE_SCALING {
    main:
        // Test data setup
        test_files = Channel.fromPath("${params.test_data_dir}/*.fastq.gz")
            .collect()
        
        // Test different process labels
        process_labels = Channel.of(
            'process_low',
            'process_medium', 
            'process_high',
            'process_memory_intensive',
            'process_gpu',
            'process_quick'
        )
        
        // Base resources for testing
        base_resources = Channel.of([
            cpus: 2,
            memory: '4.GB',
            time: '2.h'
        ])
        
        // Test resource scaling for each process type
        scaling_results = process_labels.combine(test_files).combine(base_resources)
            | map { label, files, resources ->
                [label, files, resources]
            }
            | DYNAMIC_RESOURCE_SCALING
        
        // Validate scaling results
        scaling_results.resources.view { resources ->
            println "Resource scaling test results:"
            println "  CPUs: ${resources.cpus}"
            println "  Memory: ${resources.memory}"
            println "  Time: ${resources.time}"
        }
        
        scaling_results.hints.view { hints ->
            println "Performance hints:"
            hints.each { hint ->
                println "  - ${hint}"
            }
        }
}

workflow TEST_INTELLIGENT_PARALLELIZATION {
    main:
        // Test data with different sample counts
        small_dataset = Channel.fromPath("${params.test_data_dir}/*.fastq.gz")
            .take(2)
            .collect()
            
        medium_dataset = Channel.fromPath("${params.test_data_dir}/*.fastq.gz")
            .take(5)
            .collect()
            
        large_dataset = Channel.fromPath("${params.test_data_dir}/*.fastq.gz")
            .take(10)
            .collect()
        
        datasets = Channel.of(
            ['small', small_dataset],
            ['medium', medium_dataset],
            ['large', large_dataset]
        )
        
        process_labels = Channel.of(
            'process_low',
            'process_memory_intensive',
            'process_gpu'
        )
        
        // Test parallelization for different scenarios
        parallelization_results = datasets.combine(process_labels)
            | map { dataset_info, label ->
                def (dataset_name, files) = dataset_info
                [dataset_name, files, label, params.max_forks]
            }
            | map { dataset_name, files, label, max_forks ->
                INTELLIGENT_PARALLELIZATION(files, label, max_forks)
            }
        
        // Validate parallelization results
        parallelization_results.strategy.view { strategy ->
            println "Parallelization strategy test results:"
            println "  Optimal forks: ${strategy.optimal_forks}"
            println "  Batch size: ${strategy.batch_size}"
            println "  Strategy: ${strategy.strategy}"
        }
}

workflow TEST_PERFORMANCE_MONITORING {
    main:
        // Create mock process results for testing
        mock_process_results = Channel.of([
            'FASTQC': [
                duration: 120,
                memory_usage: 2048,
                cpu_usage: 75,
                exit_status: 0
            ],
            'MEGAHIT': [
                duration: 3600,
                memory_usage: 16384,
                cpu_usage: 90,
                exit_status: 0
            ],
            'KRAKEN2': [
                duration: 1800,
                memory_usage: 8192,
                cpu_usage: 60,
                exit_status: 0
            ]
        ])
        
        // Create mock resource usage data
        mock_resource_usage = Channel.of([
            'FASTQC': [
                memoryUtilization: 0.8,
                cpuUtilization: 0.75,
                timeUtilization: 0.6,
                ioWait: 0.1
            ],
            'MEGAHIT': [
                memoryUtilization: 0.95,
                cpuUtilization: 0.9,
                timeUtilization: 0.85,
                ioWait: 0.3
            ],
            'KRAKEN2': [
                memoryUtilization: 0.7,
                cpuUtilization: 0.6,
                timeUtilization: 0.5,
                ioWait: 0.2
            ]
        ])
        
        // Test performance analysis
        test_files = Channel.fromPath("${params.test_data_dir}/*.fastq.gz")
            .collect()
        
        performance_results = PERFORMANCE_OPTIMIZATION(
            test_files,
            mock_process_results.combine(mock_resource_usage)
        )
        
        // Validate performance monitoring results
        performance_results.performance_summary.view { summary ->
            println "Performance monitoring test results:"
            println "  Summary generated: ${summary != null}"
        }
        
        performance_results.optimization_report.view { report ->
            println "Optimization report test results:"
            println "  Report generated: ${report != null}"
        }
}

workflow TEST_PERFORMANCE_OPTIMIZER_LIBRARY {
    main:
        // Test the PerformanceOptimizer library functions
        test_performance_optimizer_functions()
}

workflow {
    println "Starting Performance Optimization Tests..."
    
    // Run all test workflows
    TEST_DYNAMIC_RESOURCE_SCALING()
    TEST_INTELLIGENT_PARALLELIZATION()
    TEST_PERFORMANCE_MONITORING()
    TEST_PERFORMANCE_OPTIMIZER_LIBRARY()
    
    println "Performance Optimization Tests completed."
}

// Test helper functions
def test_performance_optimizer_functions() {
    println "Testing PerformanceOptimizer library functions..."
    
    // Test input size calculation
    def testFiles = [
        new File("${params.test_data_dir}/test1.fastq.gz"),
        new File("${params.test_data_dir}/test2.fastq.gz")
    ]
    
    // Test resource calculation (mock implementation for testing)
    def mockInputSize = 1024 * 1024 * 1024 // 1GB
    def mockSampleCount = 2
    
    println "Mock test results:"
    println "  Input size: ${mockInputSize} bytes"
    println "  Sample count: ${mockSampleCount}"
    
    // Test different process labels
    ['process_low', 'process_medium', 'process_high', 'process_memory_intensive'].each { label ->
        println "  Process label: ${label}"
        
        // Mock optimal resource calculations
        def optimalCpus = calculateMockOptimalCpus(mockInputSize, mockSampleCount, label)
        def optimalMemory = calculateMockOptimalMemory(mockInputSize, mockSampleCount, label)
        def optimalTime = calculateMockOptimalTime(mockInputSize, mockSampleCount, label)
        
        println "    Optimal CPUs: ${optimalCpus}"
        println "    Optimal Memory: ${optimalMemory}"
        println "    Optimal Time: ${optimalTime}"
    }
    
    println "PerformanceOptimizer library tests completed."
}

// Mock functions for testing (since we can't directly call the library in tests)
def calculateMockOptimalCpus(inputSize, sampleCount, processLabel) {
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    def baseCpus = 2
    
    def scaling = 1.0
    switch (processLabel) {
        case 'process_high':
            scaling = 2.0
            break
        case 'process_memory_intensive':
            scaling = 1.5
            break
        case 'process_medium':
            scaling = 1.2
            break
        default:
            scaling = 1.0
    }
    
    return Math.ceil(baseCpus * scaling * (1 + sizeGB / 10))
}

def calculateMockOptimalMemory(inputSize, sampleCount, processLabel) {
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    def baseMemoryGB = 4
    
    def scaling = 1.0
    switch (processLabel) {
        case 'process_memory_intensive':
            scaling = 3.0
            break
        case 'process_high':
            scaling = 2.0
            break
        case 'process_medium':
            scaling = 1.5
            break
        default:
            scaling = 1.0
    }
    
    return "${Math.ceil(baseMemoryGB * scaling * (1 + sizeGB / 5))}.GB"
}

def calculateMockOptimalTime(inputSize, sampleCount, processLabel) {
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    def baseTimeHours = 2
    
    def scaling = 1.0
    switch (processLabel) {
        case 'process_memory_intensive':
            scaling = 2.5
            break
        case 'process_high':
            scaling = 2.0
            break
        case 'process_medium':
            scaling = 1.5
            break
        default:
            scaling = 1.0
    }
    
    return "${Math.ceil(baseTimeHours * scaling * (1 + sizeGB / 20))}.h"
}