#!/usr/bin/env nextflow

/**
 * Unit Tests for Configuration Validation Functions
 * 
 * Tests the ConfigValidator class and related validation functions
 * Requirements: 1.1, 1.2, 1.3
 */

nextflow.enable.dsl = 2

include { ConfigValidator } from '../../nextflow/lib/ConfigValidator.groovy'

workflow TEST_CONFIG_VALIDATION {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: Resource Configuration Validation
    testResults.tests << testResourceConfigurationValidation()
    
    // Test 2: Profile Consistency Validation
    testResults.tests << testProfileConsistencyValidation()
    
    // Test 3: Executor Configuration Validation
    testResults.tests << testExecutorConfigurationValidation()
    
    // Test 4: Database Path Validation
    testResults.tests << testDatabasePathValidation()
    
    // Test 5: Partition Configuration Validation
    testResults.tests << testPartitionConfigurationValidation()
    
    // Test 6: Complete Configuration Validation
    testResults.tests << testCompleteConfigurationValidation()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testResourceConfigurationValidation() {
    def testName = "Resource Configuration Validation"
    
    try {
        // Test valid configuration
        def validParams = [
            max_cpus: 16,
            max_memory: '64.GB',
            max_time: '24.h',
            max_retry_scaling: 3
        ]
        
        def validResult = ConfigValidator.validateResourceConfiguration(validParams)
        assert validResult.errors.isEmpty() : "Valid configuration should have no errors"
        
        // Test invalid configuration
        def invalidParams = [
            max_cpus: -1,
            max_memory: 'invalid',
            max_time: 'bad_time',
            max_retry_scaling: 0
        ]
        
        def invalidResult = ConfigValidator.validateResourceConfiguration(invalidParams)
        assert !invalidResult.errors.isEmpty() : "Invalid configuration should have errors"
        assert invalidResult.errors.size() >= 3 : "Should detect multiple errors"
        
        // Test edge cases
        def edgeParams = [
            max_cpus: 0,
            max_memory: '0.GB',
            max_time: '0.h',
            max_retry_scaling: 15
        ]
        
        def edgeResult = ConfigValidator.validateResourceConfiguration(edgeParams)
        assert !edgeResult.errors.isEmpty() : "Edge cases should produce errors"
        assert !edgeResult.warnings.isEmpty() : "High retry scaling should produce warnings"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testProfileConsistencyValidation() {
    def testName = "Profile Consistency Validation"
    
    try {
        // Test complete configuration
        def completeConfig = [
            process: [
                'withLabel:process_low': [
                    cpus: { 2 * task.attempt },
                    memory: { 4.GB * task.attempt },
                    time: { 2.h * task.attempt }
                ],
                'withLabel:process_medium': [
                    cpus: { 4 * task.attempt },
                    memory: { 8.GB * task.attempt },
                    time: { 4.h * task.attempt }
                ],
                'withLabel:process_high': [
                    cpus: { 8 * task.attempt },
                    memory: { 16.GB * task.attempt },
                    time: { 8.h * task.attempt }
                ],
                'withLabel:process_memory_intensive': [
                    cpus: { 4 * task.attempt },
                    memory: { 32.GB * task.attempt },
                    time: { 12.h * task.attempt }
                ],
                'withLabel:process_quick': [
                    cpus: { 1 * task.attempt },
                    memory: { 2.GB * task.attempt },
                    time: { 30.m * task.attempt }
                ]
            ]
        ]
        
        def completeResult = ConfigValidator.validateProfileConsistency(completeConfig)
        assert completeResult.errors.isEmpty() : "Complete configuration should have no errors"
        
        // Test incomplete configuration
        def incompleteConfig = [
            process: [
                'withLabel:process_low': [
                    cpus: 2,
                    memory: '4.GB'
                ]
            ]
        ]
        
        def incompleteResult = ConfigValidator.validateProfileConsistency(incompleteConfig)
        assert !incompleteResult.errors.isEmpty() : "Incomplete configuration should have errors"
        
        // Test configuration without scaling
        def noScalingConfig = [
            process: [
                'withLabel:process_low': [
                    cpus: 2,
                    memory: '4.GB',
                    time: '2.h'
                ]
            ]
        ]
        
        def noScalingResult = ConfigValidator.validateProfileConsistency(noScalingConfig)
        assert !noScalingResult.warnings.isEmpty() : "Non-scaling configuration should have warnings"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testExecutorConfigurationValidation() {
    def testName = "Executor Configuration Validation"
    
    try {
        // Test SLURM configuration
        def slurmConfig = [
            process: [
                executor: 'slurm',
                queue: 'compute',
                memory: '16.GB'
            ]
        ]
        
        def slurmResult = ConfigValidator.validateExecutorConfiguration(slurmConfig, 'slurm')
        // Should pass basic validation
        
        // Test local configuration
        def localConfig = [
            process: [
                executor: 'local',
                cpus: Runtime.runtime.availableProcessors() + 10, // Excessive CPUs
                memory: '1000.GB' // Excessive memory
            ]
        ]
        
        def localResult = ConfigValidator.validateExecutorConfiguration(localConfig, 'local')
        assert !localResult.warnings.isEmpty() : "Excessive resource configuration should produce warnings"
        
        // Test unknown executor
        def unknownResult = ConfigValidator.validateExecutorConfiguration([:], 'unknown_executor')
        assert !unknownResult.warnings.isEmpty() : "Unknown executor should produce warning"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testDatabasePathValidation() {
    def testName = "Database Path Validation"
    
    try {
        // Create temporary test directories
        def tempDir = new File("test_databases")
        tempDir.mkdirs()
        
        def kraken2Dir = new File(tempDir, "kraken2")
        kraken2Dir.mkdirs()
        
        def checkvDir = new File(tempDir, "checkv")
        checkvDir.mkdirs()
        
        // Test valid database configuration
        def validParams = [
            kraken2_db: kraken2Dir.absolutePath,
            checkv_db: checkvDir.absolutePath,
            blast_options: ['viruses'],
            blastdb_viruses: "/nonexistent/blast" // This should produce warning, not error
        ]
        
        def validResult = ConfigValidator.validateDatabasePaths(validParams)
        assert validResult.errors.isEmpty() : "Valid required databases should have no errors"
        assert !validResult.warnings.isEmpty() : "Missing optional databases should produce warnings"
        
        // Test missing required databases
        def missingParams = [
            kraken2_db: null,
            checkv_db: "/nonexistent/checkv"
        ]
        
        def missingResult = ConfigValidator.validateDatabasePaths(missingParams)
        assert !missingResult.errors.isEmpty() : "Missing required databases should produce errors"
        
        // Cleanup
        tempDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testPartitionConfigurationValidation() {
    def testName = "Partition Configuration Validation"
    
    try {
        // Test complete partition configuration
        def completeParams = [
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem',
                gpu: 'gpu',
                quick: 'quickq'
            ],
            default_partition: 'compute',
            partition_selection_strategy: 'intelligent',
            partition_thresholds: [
                bigmem_memory_gb: 128,
                quick_time_hours: 1,
                quick_memory_gb: 16,
                gpu_labels: ['process_gpu']
            ],
            partition_fallbacks: [
                bigmem: ['compute'],
                gpu: ['compute'],
                quick: ['compute']
            ]
        ]
        
        def completeResult = ConfigValidator.validatePartitionConfiguration(completeParams)
        assert completeResult.errors.isEmpty() : "Complete partition configuration should have no errors"
        
        // Test missing partition configuration
        def missingParams = [:]
        
        def missingResult = ConfigValidator.validatePartitionConfiguration(missingParams)
        assert !missingResult.errors.isEmpty() : "Missing partition configuration should produce errors"
        
        // Test invalid strategy
        def invalidStrategyParams = [
            partitions: [compute: 'compute'],
            partition_selection_strategy: 'invalid_strategy'
        ]
        
        def invalidStrategyResult = ConfigValidator.validatePartitionConfiguration(invalidStrategyParams)
        assert !invalidStrategyResult.errors.isEmpty() : "Invalid strategy should produce errors"
        
        // Test invalid thresholds
        def invalidThresholdParams = [
            partitions: [compute: 'compute'],
            partition_thresholds: [
                bigmem_memory_gb: -10,
                quick_time_hours: 0,
                gpu_labels: "not_a_list"
            ]
        ]
        
        def invalidThresholdResult = ConfigValidator.validatePartitionConfiguration(invalidThresholdParams)
        assert !invalidThresholdResult.errors.isEmpty() : "Invalid thresholds should produce errors"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testCompleteConfigurationValidation() {
    def testName = "Complete Configuration Validation"
    
    try {
        // Create a comprehensive test configuration
        def testParams = [
            max_cpus: 16,
            max_memory: '64.GB',
            max_time: '24.h',
            resource_profile: 'slurm',
            kraken2_db: "/tmp/test_kraken2",
            checkv_db: "/tmp/test_checkv",
            partitions: [
                compute: 'compute',
                bigmem: 'bigmem'
            ],
            default_partition: 'compute'
        ]
        
        def testConfig = [
            process: [
                executor: 'slurm',
                'withLabel:process_low': [
                    cpus: { 2 * task.attempt },
                    memory: { 4.GB * task.attempt }
                ],
                'withLabel:process_medium': [
                    cpus: { 4 * task.attempt },
                    memory: { 8.GB * task.attempt }
                ],
                'withLabel:process_high': [
                    cpus: { 8 * task.attempt },
                    memory: { 16.GB * task.attempt }
                ],
                'withLabel:process_memory_intensive': [
                    cpus: { 4 * task.attempt },
                    memory: { 32.GB * task.attempt }
                ],
                'withLabel:process_quick': [
                    cpus: { 1 * task.attempt },
                    memory: { 2.GB * task.attempt }
                ]
            ]
        ]
        
        def allResults = ConfigValidator.validateCompleteConfiguration(testParams, testConfig)
        
        // Check that all validation categories are present
        assert allResults.containsKey('resources') : "Should include resource validation"
        assert allResults.containsKey('profiles') : "Should include profile validation"
        assert allResults.containsKey('executor') : "Should include executor validation"
        assert allResults.containsKey('databases') : "Should include database validation"
        assert allResults.containsKey('partitions') : "Should include partition validation"
        
        // Generate validation report
        def reportResult = ConfigValidator.generateValidationReport(allResults)
        assert reportResult.containsKey('report') : "Should generate report"
        assert reportResult.containsKey('hasErrors') : "Should indicate error status"
        assert reportResult.containsKey('errorCount') : "Should count errors"
        assert reportResult.containsKey('warningCount') : "Should count warnings"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}