#!/usr/bin/env nextflow

/**
 * Unit Tests for Partition Selection and Resource Allocation
 * 
 * Tests the PartitionManager class and intelligent partition selection logic
 * Requirements: 6.1, 6.2, 6.3, 6.4
 */

nextflow.enable.dsl = 2

include { PartitionManager } from '../../nextflow/lib/PartitionManager.groovy'

workflow TEST_PARTITION_SELECTION {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: Intelligent Partition Selection
    testResults.tests << testIntelligentPartitionSelection()
    
    // Test 2: User-Defined Partition Selection
    testResults.tests << testUserDefinedPartitionSelection()
    
    // Test 3: Fallback Logic
    testResults.tests << testFallbackLogic()
    
    // Test 4: Cluster Options Generation
    testResults.tests << testClusterOptionsGeneration()
    
    // Test 5: Partition Validation
    testResults.tests << testPartitionValidation()
    
    // Test 6: Resource Threshold Logic
    testResults.tests << testResourceThresholdLogic()
    
    // Test 7: GPU Process Detection
    testResults.tests << testGpuProcessDetection()
    
    // Test 8: Memory-Intensive Process Detection
    testResults.tests << testMemoryIntensiveProcessDetection()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testIntelligentPartitionSelection() {
    def testName = "Intelligent Partition Selection"
    
    try {
        def testParams = [
            partition_selection_strategy: 'intelligent',
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem',
                gpu: 'gpu',
                quick: 'quickq'
            ],
            partition_thresholds: [
                bigmem_memory_gb: 128,
                quick_time_hours: 1,
                quick_memory_gb: 16,
                gpu_labels: ['process_gpu']
            ],
            default_partition: 'compute'
        ]
        
        // Test GPU process selection
        def gpuPartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_gpu', '32.GB', '8.h', 8
        )
        assert gpuPartition == 'gpu' : "GPU processes should select GPU partition"
        
        // Test memory-intensive process selection
        def bigmemPartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_memory_intensive', '256.GB', '12.h', 4
        )
        assert bigmemPartition == 'bigmem' : "Memory-intensive processes should select bigmem partition"
        
        // Test quick process selection
        def quickPartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_quick', '8.GB', '30.m', 2
        )
        assert quickPartition == 'quickq' : "Quick processes should select quick partition"
        
        // Test standard process selection
        def computePartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '16.GB', '4.h', 4
        )
        assert computePartition == 'compute' : "Standard processes should select compute partition"
        
        // Test high-memory process that exceeds threshold
        def highMemoryPartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_high', '200.GB', '8.h', 8
        )
        assert highMemoryPartition == 'bigmem' : "High memory processes should select bigmem partition"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testUserDefinedPartitionSelection() {
    def testName = "User-Defined Partition Selection"
    
    try {
        def testParams = [
            partition_selection_strategy: 'user_defined',
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem'
            ],
            custom_partition_mapping: [
                'process_low': 'compute',
                'process_high': 'bigmem',
                'process_custom': 'special_partition'
            ],
            default_partition: 'compute'
        ]
        
        // Test mapped process
        def mappedPartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_high', '32.GB', '8.h', 8
        )
        assert mappedPartition == 'bigmem' : "Mapped process should use custom mapping"
        
        // Test unmapped process (should use default)
        def unmappedPartition = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '16.GB', '4.h', 4
        )
        assert unmappedPartition == 'compute' : "Unmapped process should use default partition"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testFallbackLogic() {
    def testName = "Fallback Logic"
    
    try {
        def testParams = [
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem',
                gpu: 'gpu'
            ],
            partition_fallbacks: [
                bigmem: ['compute'],
                gpu: ['compute'],
                unavailable: ['compute']
            ],
            default_partition: 'compute',
            enable_partition_validation: false // Disable for testing
        ]
        
        // Test normal partition selection (no fallback needed)
        def normalPartition = PartitionManager.applyFallbackLogic('compute', testParams)
        assert normalPartition == 'compute' : "Available partition should not trigger fallback"
        
        // Test fallback to default when validation disabled
        def fallbackPartition = PartitionManager.applyFallbackLogic('nonexistent', testParams)
        assert fallbackPartition == 'nonexistent' : "Should return original when validation disabled"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testClusterOptionsGeneration() {
    def testName = "Cluster Options Generation"
    
    try {
        def testParams = [
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem',
                gpu: 'gpu',
                quick: 'quickq'
            ],
            custom_cluster_options: ['--account=myproject']
        ]
        
        // Test basic cluster options
        def basicOptions = PartitionManager.generateClusterOptions(
            'process_medium', 'compute', '16.GB', 4, testParams
        )
        assert basicOptions.contains('--mem=') : "Should include memory specification"
        assert basicOptions.contains('--cpus-per-task=4') : "Should include CPU specification"
        assert basicOptions.contains('--ntasks=1') : "Should include task specification"
        
        // Test GPU-specific options
        def gpuOptions = PartitionManager.generateClusterOptions(
            'process_gpu', 'gpu', '32.GB', 8, testParams
        )
        assert gpuOptions.contains('--gres=gpu:1') : "Should include GPU resource request"
        assert gpuOptions.contains('--constraint=gpu') : "Should include GPU constraint"
        
        // Test bigmem-specific options
        def bigmemOptions = PartitionManager.generateClusterOptions(
            'process_memory_intensive', 'bigmem', '256.GB', 4, testParams
        )
        assert bigmemOptions.contains('--constraint=bigmem') : "Should include bigmem constraint"
        assert bigmemOptions.contains('--exclusive') : "Should request exclusive access for large memory"
        
        // Test quick partition options
        def quickOptions = PartitionManager.generateClusterOptions(
            'process_quick', 'quickq', '8.GB', 2, testParams
        )
        assert quickOptions.contains('--qos=quick') : "Should include quick QoS"
        assert quickOptions.contains('--nice=100') : "Should include nice priority"
        
        // Test custom options inclusion
        assert basicOptions.contains('--account=myproject') : "Should include custom cluster options"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testPartitionValidation() {
    def testName = "Partition Validation"
    
    try {
        def testParams = [
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem',
                gpu: 'gpu',
                quick: 'quickq'
            ],
            partition_thresholds: [
                bigmem_memory_gb: 128,
                quick_time_hours: 1,
                quick_memory_gb: 16,
                gpu_labels: ['process_gpu']
            ]
        ]
        
        def validationResults = PartitionManager.validatePartitionSelection(testParams)
        
        assert validationResults.containsKey('errors') : "Should include error list"
        assert validationResults.containsKey('warnings') : "Should include warning list"
        assert validationResults.containsKey('testResults') : "Should include test results"
        
        // Check that test results contain expected test cases
        def testResults = validationResults.testResults
        assert testResults.size() >= 6 : "Should test multiple process labels"
        
        // Verify specific test cases
        def lowProcessTest = testResults.find { it.label == 'process_low' }
        assert lowProcessTest != null : "Should test process_low"
        
        def gpuProcessTest = testResults.find { it.label == 'process_gpu' }
        assert gpuProcessTest != null : "Should test process_gpu"
        assert gpuProcessTest.selected == 'gpu' : "GPU process should select GPU partition"
        
        def memoryIntensiveTest = testResults.find { it.label == 'process_memory_intensive' }
        assert memoryIntensiveTest != null : "Should test process_memory_intensive"
        assert memoryIntensiveTest.selected == 'bigmem' : "Memory intensive process should select bigmem partition"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testResourceThresholdLogic() {
    def testName = "Resource Threshold Logic"
    
    try {
        def testParams = [
            partition_selection_strategy: 'intelligent',
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem',
                quick: 'quickq'
            ],
            partition_thresholds: [
                bigmem_memory_gb: 64,  // Lower threshold for testing
                quick_time_hours: 2,   // Higher threshold for testing
                quick_memory_gb: 8     // Lower threshold for testing
            ],
            default_partition: 'compute'
        ]
        
        // Test memory threshold for bigmem
        def belowThreshold = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '32.GB', '4.h', 4
        )
        assert belowThreshold == 'compute' : "Below memory threshold should use compute"
        
        def aboveThreshold = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '128.GB', '4.h', 4
        )
        assert aboveThreshold == 'bigmem' : "Above memory threshold should use bigmem"
        
        // Test time and memory thresholds for quick partition
        def quickQualified = PartitionManager.selectOptimalPartition(
            testParams, 'process_low', '4.GB', '1.h', 2
        )
        assert quickQualified == 'quickq' : "Quick qualified job should use quick partition"
        
        def tooLongForQuick = PartitionManager.selectOptimalPartition(
            testParams, 'process_low', '4.GB', '4.h', 2
        )
        assert tooLongForQuick == 'compute' : "Too long for quick should use compute"
        
        def tooMuchMemoryForQuick = PartitionManager.selectOptimalPartition(
            testParams, 'process_low', '16.GB', '1.h', 2
        )
        assert tooMuchMemoryForQuick == 'compute' : "Too much memory for quick should use compute"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testGpuProcessDetection() {
    def testName = "GPU Process Detection"
    
    try {
        def testParams = [
            partition_selection_strategy: 'intelligent',
            partitions: [
                compute: 'compute',
                gpu: 'gpu'
            ],
            partition_thresholds: [
                gpu_labels: ['process_gpu', 'gpu_accelerated']
            ],
            default_partition: 'compute'
        ]
        
        // Test explicit GPU label
        def explicitGpu = PartitionManager.selectOptimalPartition(
            testParams, 'process_gpu', '32.GB', '8.h', 8
        )
        assert explicitGpu == 'gpu' : "Explicit GPU label should select GPU partition"
        
        // Test custom GPU label
        def customGpu = PartitionManager.selectOptimalPartition(
            testParams, 'gpu_accelerated', '32.GB', '8.h', 8
        )
        assert customGpu == 'gpu' : "Custom GPU label should select GPU partition"
        
        // Test label containing 'gpu'
        def containsGpu = PartitionManager.selectOptimalPartition(
            testParams, 'my_gpu_process', '32.GB', '8.h', 8
        )
        assert containsGpu == 'gpu' : "Label containing 'gpu' should select GPU partition"
        
        // Test non-GPU process
        def nonGpu = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '32.GB', '8.h', 8
        )
        assert nonGpu == 'compute' : "Non-GPU process should not select GPU partition"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testMemoryIntensiveProcessDetection() {
    def testName = "Memory-Intensive Process Detection"
    
    try {
        def testParams = [
            partition_selection_strategy: 'intelligent',
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem'
            ],
            partition_thresholds: [
                bigmem_memory_gb: 64
            ],
            default_partition: 'compute'
        ]
        
        // Test explicit memory-intensive label
        def explicitMemoryIntensive = PartitionManager.selectOptimalPartition(
            testParams, 'process_memory_intensive', '32.GB', '8.h', 4
        )
        assert explicitMemoryIntensive == 'bigmem' : "Memory-intensive label should select bigmem partition"
        
        // Test high memory requirement
        def highMemory = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '128.GB', '8.h', 4
        )
        assert highMemory == 'bigmem' : "High memory requirement should select bigmem partition"
        
        // Test normal memory requirement
        def normalMemory = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '16.GB', '8.h', 4
        )
        assert normalMemory == 'compute' : "Normal memory requirement should select compute partition"
        
        // Test edge case at threshold
        def atThreshold = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '64.GB', '8.h', 4
        )
        assert atThreshold == 'compute' : "At threshold should still use compute (not greater than)"
        
        def justOverThreshold = PartitionManager.selectOptimalPartition(
            testParams, 'process_medium', '65.GB', '8.h', 4
        )
        assert justOverThreshold == 'bigmem' : "Just over threshold should use bigmem"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}