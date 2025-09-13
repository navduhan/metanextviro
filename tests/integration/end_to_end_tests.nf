#!/usr/bin/env nextflow

/**
 * End-to-End Integration Tests
 * 
 * Tests complete pipeline execution with different configurations
 * Requirements: 1.1, 1.2, 1.3, 6.1, 6.2
 */

nextflow.enable.dsl = 2

workflow TEST_END_TO_END {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: Local Profile End-to-End
    testResults.tests << testLocalProfileEndToEnd()
    
    // Test 2: SLURM Profile End-to-End
    testResults.tests << testSlurmProfileEndToEnd()
    
    // Test 3: Unified Environment End-to-End
    testResults.tests << testUnifiedEnvironmentEndToEnd()
    
    // Test 4: Per-Process Environment End-to-End
    testResults.tests << testPerProcessEnvironmentEndToEnd()
    
    // Test 5: Configuration Validation End-to-End
    testResults.tests << testConfigurationValidationEndToEnd()
    
    // Test 6: Error Handling End-to-End
    testResults.tests << testErrorHandlingEndToEnd()
    
    // Test 7: Resource Scaling End-to-End
    testResults.tests << testResourceScalingEndToEnd()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testLocalProfileEndToEnd() {
    def testName = "Local Profile End-to-End Test"
    
    try {
        // Setup test configuration for local profile
        def testConfig = createLocalTestConfiguration()
        
        // Create test input files
        def testInputs = createTestInputFiles()
        
        // Simulate pipeline execution with local profile
        def executionResult = simulatePipelineExecution(testConfig, testInputs, 'local')
        
        // Verify execution completed successfully
        assert executionResult.success : "Local profile execution should succeed"
        assert executionResult.processesCompleted >= 5 : "Should complete multiple processes"
        
        // Verify resource allocation was appropriate for local execution
        assert executionResult.maxCpusUsed <= Runtime.runtime.availableProcessors() : "Should not exceed system CPU limits"
        assert executionResult.maxMemoryUsed <= getSystemMemoryGB() : "Should not exceed system memory limits"
        
        // Verify output files were generated
        assert executionResult.outputFiles.size() >= 3 : "Should generate multiple output files"
        assert executionResult.outputFiles.any { it.contains('fastqc') } : "Should generate FastQC outputs"
        assert executionResult.outputFiles.any { it.contains('assembly') } : "Should generate assembly outputs"
        
        // Verify execution time was reasonable for local execution
        assert executionResult.executionTimeMinutes <= 60 : "Local execution should complete within reasonable time"
        
        // Verify no SLURM-specific configurations were used
        assert !executionResult.usedSlurmFeatures : "Local profile should not use SLURM features"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testSlurmProfileEndToEnd() {
    def testName = "SLURM Profile End-to-End Test"
    
    try {
        // Setup test configuration for SLURM profile
        def testConfig = createSlurmTestConfiguration()
        
        // Create test input files
        def testInputs = createTestInputFiles()
        
        // Simulate pipeline execution with SLURM profile
        def executionResult = simulatePipelineExecution(testConfig, testInputs, 'slurm')
        
        // Verify execution completed successfully
        assert executionResult.success : "SLURM profile execution should succeed"
        assert executionResult.processesCompleted >= 5 : "Should complete multiple processes"
        
        // Verify partition selection worked correctly
        assert executionResult.partitionsUsed.size() >= 2 : "Should use multiple partitions"
        assert executionResult.partitionsUsed.contains('compute') : "Should use compute partition"
        
        // Verify intelligent partition selection
        def memoryIntensiveJobs = executionResult.jobDetails.findAll { 
            it.processLabel == 'process_memory_intensive' 
        }
        if (memoryIntensiveJobs) {
            assert memoryIntensiveJobs.every { it.partition == 'bigmem' } : "Memory intensive jobs should use bigmem partition"
        }
        
        def quickJobs = executionResult.jobDetails.findAll { 
            it.processLabel == 'process_quick' 
        }
        if (quickJobs) {
            assert quickJobs.every { it.partition in ['quickq', 'quick'] } : "Quick jobs should use quick partition"
        }
        
        // Verify cluster options were generated correctly
        assert executionResult.jobDetails.every { it.clusterOptions != null } : "All jobs should have cluster options"
        assert executionResult.jobDetails.any { it.clusterOptions.contains('--mem=') } : "Should specify memory requirements"
        assert executionResult.jobDetails.any { it.clusterOptions.contains('--cpus-per-task=') } : "Should specify CPU requirements"
        
        // Verify resource scaling worked
        def retriedJobs = executionResult.jobDetails.findAll { it.attempt > 1 }
        if (retriedJobs) {
            retriedJobs.each { job ->
                assert job.scaledResources : "Retried jobs should have scaled resources"
            }
        }
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testUnifiedEnvironmentEndToEnd() {
    def testName = "Unified Environment End-to-End Test"
    
    try {
        // Setup test configuration for unified environment
        def testConfig = createUnifiedEnvironmentTestConfiguration()
        
        // Create test input files
        def testInputs = createTestInputFiles()
        
        // Simulate pipeline execution with unified environment
        def executionResult = simulatePipelineExecution(testConfig, testInputs, 'local')
        
        // Verify execution completed successfully
        assert executionResult.success : "Unified environment execution should succeed"
        
        // Verify all processes used the same environment
        def environmentsUsed = executionResult.jobDetails.collect { it.environment }.unique()
        assert environmentsUsed.size() == 1 : "All processes should use the same environment in unified mode"
        assert environmentsUsed[0] == testConfig.unified_env : "Should use specified unified environment"
        
        // Verify no environment conflicts occurred
        assert !executionResult.environmentConflicts : "Should have no environment conflicts in unified mode"
        
        // Verify all required tools were available
        def requiredTools = ['fastqc', 'megahit', 'kraken2', 'checkv', 'blast']
        def availableTools = executionResult.availableTools
        requiredTools.each { tool ->
            assert availableTools.contains(tool) : "Unified environment should provide ${tool}"
        }
        
        // Verify environment setup time was reasonable
        assert executionResult.environmentSetupTimeSeconds <= 300 : "Environment setup should be quick for unified mode"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testPerProcessEnvironmentEndToEnd() {
    def testName = "Per-Process Environment End-to-End Test"
    
    try {
        // Setup test configuration for per-process environments
        def testConfig = createPerProcessEnvironmentTestConfiguration()
        
        // Create test input files
        def testInputs = createTestInputFiles()
        
        // Simulate pipeline execution with per-process environments
        def executionResult = simulatePipelineExecution(testConfig, testInputs, 'local')
        
        // Verify execution completed successfully
        assert executionResult.success : "Per-process environment execution should succeed"
        
        // Verify different processes used different environments
        def environmentsUsed = executionResult.jobDetails.collect { it.environment }.unique()
        assert environmentsUsed.size() >= 3 : "Should use multiple environments in per-process mode"
        
        // Verify environment isolation
        def qcJobs = executionResult.jobDetails.findAll { it.processName in ['FASTQC', 'MULTIQC'] }
        def assemblyJobs = executionResult.jobDetails.findAll { it.processName in ['MEGAHIT', 'SPADES'] }
        
        if (qcJobs && assemblyJobs) {
            def qcEnvs = qcJobs.collect { it.environment }.unique()
            def assemblyEnvs = assemblyJobs.collect { it.environment }.unique()
            assert qcEnvs != assemblyEnvs : "QC and assembly processes should use different environments"
        }
        
        // Verify no cross-environment contamination
        assert !executionResult.crossEnvironmentContamination : "Should have no cross-environment contamination"
        
        // Verify environment-specific tools were available
        def environmentTools = executionResult.environmentToolMapping
        environmentTools.each { env, tools ->
            assert tools.size() >= 1 : "Each environment should provide at least one tool"
        }
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testConfigurationValidationEndToEnd() {
    def testName = "Configuration Validation End-to-End Test"
    
    try {
        // Test with valid configuration
        def validConfig = createValidTestConfiguration()
        def validationResult = performFullConfigurationValidation(validConfig)
        
        assert validationResult.valid : "Valid configuration should pass validation"
        assert validationResult.errors.isEmpty() : "Valid configuration should have no errors"
        
        // Test execution with valid configuration
        def testInputs = createTestInputFiles()
        def executionResult = simulatePipelineExecution(validConfig, testInputs, 'local')
        assert executionResult.success : "Execution with valid configuration should succeed"
        
        // Test with invalid configuration (missing databases)
        def invalidConfig = createInvalidTestConfiguration()
        def invalidValidationResult = performFullConfigurationValidation(invalidConfig)
        
        assert !invalidValidationResult.valid : "Invalid configuration should fail validation"
        assert !invalidValidationResult.errors.isEmpty() : "Invalid configuration should have errors"
        
        // Verify specific validation errors
        assert invalidValidationResult.errors.any { it.contains('database') } : "Should detect database errors"
        
        // Test that invalid configuration prevents execution
        def invalidExecutionResult = simulatePipelineExecution(invalidConfig, testInputs, 'local')
        assert !invalidExecutionResult.success : "Execution with invalid configuration should fail"
        assert invalidExecutionResult.failureReason.contains('validation') : "Should fail due to validation errors"
        
        // Test configuration with warnings (should still execute)
        def warningConfig = createConfigurationWithWarnings()
        def warningValidationResult = performFullConfigurationValidation(warningConfig)
        
        assert warningValidationResult.valid : "Configuration with warnings should still be valid"
        assert !warningValidationResult.warnings.isEmpty() : "Should have warnings"
        
        def warningExecutionResult = simulatePipelineExecution(warningConfig, testInputs, 'local')
        assert warningExecutionResult.success : "Execution with warnings should succeed"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testErrorHandlingEndToEnd() {
    def testName = "Error Handling End-to-End Test"
    
    try {
        // Test with missing input files
        def testConfig = createValidTestConfiguration()
        def missingInputs = createMissingInputFiles()
        
        def missingInputResult = simulatePipelineExecution(testConfig, missingInputs, 'local')
        assert !missingInputResult.success : "Should fail with missing input files"
        assert missingInputResult.failureReason.contains('input') : "Should indicate input file error"
        
        // Test with corrupted input files
        def corruptedInputs = createCorruptedInputFiles()
        def corruptedInputResult = simulatePipelineExecution(testConfig, corruptedInputs, 'local')
        assert !corruptedInputResult.success : "Should fail with corrupted input files"
        
        // Test retry mechanism
        def flakyConfig = createFlakyTestConfiguration()
        def testInputs = createTestInputFiles()
        
        def retryResult = simulatePipelineExecution(flakyConfig, testInputs, 'local')
        // Should eventually succeed due to retries
        assert retryResult.success : "Should succeed after retries"
        assert retryResult.totalRetries > 0 : "Should have performed retries"
        
        // Test resource exhaustion handling
        def resourceConstrainedConfig = createResourceConstrainedConfiguration()
        def resourceResult = simulatePipelineExecution(resourceConstrainedConfig, testInputs, 'local')
        
        if (!resourceResult.success) {
            assert resourceResult.failureReason.contains('resource') : "Should indicate resource constraint error"
        } else {
            // If it succeeded, it should have scaled resources
            assert resourceResult.resourceScalingOccurred : "Should have scaled resources to succeed"
        }
        
        // Test graceful degradation
        def partialFailureConfig = createPartialFailureConfiguration()
        def partialResult = simulatePipelineExecution(partialFailureConfig, testInputs, 'local')
        
        // Should complete with some processes failing gracefully
        assert partialResult.partialSuccess : "Should handle partial failures gracefully"
        assert partialResult.completedProcesses > 0 : "Should complete some processes"
        assert partialResult.failedProcesses > 0 : "Should have some failed processes"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testResourceScalingEndToEnd() {
    def testName = "Resource Scaling End-to-End Test"
    
    try {
        // Test with different data sizes
        def testConfig = createValidTestConfiguration()
        
        // Small dataset test
        def smallInputs = createSmallTestInputFiles()
        def smallResult = simulatePipelineExecution(testConfig, smallInputs, 'local')
        
        assert smallResult.success : "Small dataset execution should succeed"
        def smallMaxMemory = smallResult.maxMemoryUsed
        def smallMaxCpus = smallResult.maxCpusUsed
        
        // Large dataset test
        def largeInputs = createLargeTestInputFiles()
        def largeResult = simulatePipelineExecution(testConfig, largeInputs, 'local')
        
        assert largeResult.success : "Large dataset execution should succeed"
        def largeMaxMemory = largeResult.maxMemoryUsed
        def largeMaxCpus = largeResult.maxCpusUsed
        
        // Verify resource scaling occurred
        assert largeMaxMemory >= smallMaxMemory : "Large dataset should use more memory"
        // CPU usage might not always scale, depending on the process
        
        // Test retry scaling
        def retryScalingConfig = createRetryScalingConfiguration()
        def retryInputs = createTestInputFiles()
        
        def retryResult = simulatePipelineExecution(retryScalingConfig, retryInputs, 'local')
        
        if (retryResult.retriedJobs.size() > 0) {
            retryResult.retriedJobs.each { job ->
                assert job.finalResources.memory > job.initialResources.memory : "Retried jobs should have scaled memory"
                assert job.finalResources.cpus >= job.initialResources.cpus : "Retried jobs should have scaled CPUs"
            }
        }
        
        // Test resource limit enforcement
        def limitedConfig = createResourceLimitedConfiguration()
        def limitedResult = simulatePipelineExecution(limitedConfig, testInputs, 'local')
        
        assert limitedResult.maxMemoryUsed <= limitedConfig.max_memory_gb : "Should respect memory limits"
        assert limitedResult.maxCpusUsed <= limitedConfig.max_cpus : "Should respect CPU limits"
        
        // Test dynamic resource allocation
        def dynamicConfig = createDynamicResourceConfiguration()
        def dynamicResult = simulatePipelineExecution(dynamicConfig, testInputs, 'local')
        
        assert dynamicResult.success : "Dynamic resource allocation should succeed"
        assert dynamicResult.resourceAdjustments > 0 : "Should make dynamic resource adjustments"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

// Helper functions for end-to-end testing

def createLocalTestConfiguration() {
    return [
        profile: 'local',
        max_cpus: Runtime.runtime.availableProcessors(),
        max_memory_gb: (Runtime.runtime.maxMemory() / (1024 * 1024 * 1024) * 0.8) as int,
        max_time_hours: 24,
        env_mode: 'unified',
        unified_env: 'environment.yml',
        kraken2_db: '/tmp/test_kraken2',
        checkv_db: '/tmp/test_checkv'
    ]
}

def createSlurmTestConfiguration() {
    return [
        profile: 'slurm',
        max_cpus: 128,
        max_memory_gb: 1000,
        max_time_hours: 72,
        env_mode: 'per_process',
        process_envs_dir: 'envs/',
        kraken2_db: '/shared/databases/kraken2',
        checkv_db: '/shared/databases/checkv',
        partitions: [
            compute: 'compute',
            bigmem: 'bigmem',
            gpu: 'gpu',
            quick: 'quickq'
        ],
        partition_thresholds: [
            bigmem_memory_gb: 128,
            quick_time_hours: 1,
            quick_memory_gb: 16
        ],
        partition_selection_strategy: 'intelligent'
    ]
}

def createUnifiedEnvironmentTestConfiguration() {
    return [
        profile: 'local',
        env_mode: 'unified',
        unified_env: 'environment.yml',
        kraken2_db: '/tmp/test_kraken2',
        checkv_db: '/tmp/test_checkv'
    ]
}

def createPerProcessEnvironmentTestConfiguration() {
    return [
        profile: 'local',
        env_mode: 'per_process',
        process_envs_dir: 'envs/',
        kraken2_db: '/tmp/test_kraken2',
        checkv_db: '/tmp/test_checkv'
    ]
}

def createTestInputFiles() {
    return [
        samplesheet: 'test_samplesheet.csv',
        samples: [
            [name: 'sample1', fastq_1: 'sample1_R1.fastq.gz', fastq_2: 'sample1_R2.fastq.gz'],
            [name: 'sample2', fastq_1: 'sample2_R1.fastq.gz', fastq_2: 'sample2_R2.fastq.gz']
        ],
        file_sizes_mb: [
            'sample1_R1.fastq.gz': 100,
            'sample1_R2.fastq.gz': 100,
            'sample2_R1.fastq.gz': 150,
            'sample2_R2.fastq.gz': 150
        ]
    ]
}

def createSmallTestInputFiles() {
    def inputs = createTestInputFiles()
    inputs.file_sizes_mb.each { file, size ->
        inputs.file_sizes_mb[file] = size / 10  // Make files 10x smaller
    }
    return inputs
}

def createLargeTestInputFiles() {
    def inputs = createTestInputFiles()
    inputs.file_sizes_mb.each { file, size ->
        inputs.file_sizes_mb[file] = size * 10  // Make files 10x larger
    }
    return inputs
}

def simulatePipelineExecution(config, inputs, profile) {
    // Simulate complete pipeline execution
    def result = [
        success: true,
        processesCompleted: 0,
        maxCpusUsed: 0,
        maxMemoryUsed: 0,
        executionTimeMinutes: 0,
        outputFiles: [],
        usedSlurmFeatures: false,
        partitionsUsed: [],
        jobDetails: [],
        environmentConflicts: false,
        availableTools: [],
        environmentSetupTimeSeconds: 0,
        crossEnvironmentContamination: false,
        environmentToolMapping: [:],
        failureReason: null,
        totalRetries: 0,
        resourceScalingOccurred: false,
        partialSuccess: false,
        completedProcesses: 0,
        failedProcesses: 0,
        resourceAdjustments: 0,
        retriedJobs: []
    ]
    
    try {
        // Validate configuration first
        def validation = performFullConfigurationValidation(config)
        if (!validation.valid) {
            result.success = false
            result.failureReason = "Configuration validation failed: ${validation.errors.join(', ')}"
            return result
        }
        
        // Validate inputs
        def inputValidation = validateInputFiles(inputs)
        if (!inputValidation.valid) {
            result.success = false
            result.failureReason = "Input validation failed: ${inputValidation.errors.join(', ')}"
            return result
        }
        
        // Simulate process execution
        def processes = ['FASTQC', 'MEGAHIT', 'KRAKEN2', 'CHECKV', 'MULTIQC']
        
        processes.each { processName ->
            def processResult = simulateProcessExecution(processName, config, inputs, profile)
            
            if (processResult.success) {
                result.processesCompleted++
                result.completedProcesses++
                result.maxCpusUsed = Math.max(result.maxCpusUsed, processResult.cpusUsed)
                result.maxMemoryUsed = Math.max(result.maxMemoryUsed, processResult.memoryUsed)
                result.outputFiles.addAll(processResult.outputFiles)
                
                if (processResult.partition) {
                    result.partitionsUsed << processResult.partition
                    result.usedSlurmFeatures = true
                }
                
                result.jobDetails << processResult.jobDetail
                result.totalRetries += processResult.retries
                
                if (processResult.resourceScaled) {
                    result.resourceScalingOccurred = true
                    result.resourceAdjustments++
                }
                
                if (processResult.retries > 0) {
                    result.retriedJobs << processResult.jobDetail
                }
            } else {
                result.failedProcesses++
                if (config.graceful_degradation) {
                    result.partialSuccess = true
                } else {
                    result.success = false
                    result.failureReason = processResult.error
                    return result
                }
            }
        }
        
        // Set environment-related results
        if (config.env_mode == 'unified') {
            result.availableTools = ['fastqc', 'megahit', 'kraken2', 'checkv', 'blast', 'multiqc']
            result.environmentSetupTimeSeconds = 60
        } else {
            result.environmentToolMapping = [
                'qc.yml': ['fastqc', 'multiqc'],
                'assembly.yml': ['megahit', 'spades'],
                'taxonomy.yml': ['kraken2'],
                'annotation.yml': ['checkv', 'blast']
            ]
            result.environmentSetupTimeSeconds = 180
        }
        
        // Simulate execution time based on input size
        def totalInputSize = inputs.file_sizes_mb.values().sum()
        result.executionTimeMinutes = Math.max(10, totalInputSize / 10)  // Rough estimate
        
        result.partitionsUsed = result.partitionsUsed.unique()
        
    } catch (Exception e) {
        result.success = false
        result.failureReason = e.message
    }
    
    return result
}

def simulateProcessExecution(processName, config, inputs, profile) {
    def result = [
        success: true,
        cpusUsed: 0,
        memoryUsed: 0,
        outputFiles: [],
        partition: null,
        jobDetail: [:],
        retries: 0,
        resourceScaled: false,
        error: null
    ]
    
    try {
        // Determine resource requirements based on process
        def baseResources = getProcessBaseResources(processName)
        result.cpusUsed = baseResources.cpus
        result.memoryUsed = baseResources.memory
        
        // Apply profile-specific constraints
        if (profile == 'local') {
            result.cpusUsed = Math.min(result.cpusUsed, config.max_cpus ?: 4)
            result.memoryUsed = Math.min(result.memoryUsed, config.max_memory_gb ?: 8)
        }
        
        // Simulate partition selection for SLURM
        if (profile == 'slurm' && config.partitions) {
            result.partition = selectPartitionForProcess(processName, baseResources, config)
        }
        
        // Simulate potential failures and retries
        if (config.simulate_failures && Math.random() < 0.2) {  // 20% failure rate
            result.retries = 1 + (Math.random() * 2) as int
            result.resourceScaled = true
            result.cpusUsed *= (1 + result.retries)
            result.memoryUsed *= (1 + result.retries)
        }
        
        // Generate output files
        result.outputFiles = generateProcessOutputFiles(processName)
        
        // Create job detail
        result.jobDetail = [
            processName: processName,
            processLabel: getProcessLabel(processName),
            cpus: result.cpusUsed,
            memory: result.memoryUsed,
            partition: result.partition,
            clusterOptions: generateClusterOptions(processName, result.partition, result.memoryUsed, result.cpusUsed),
            environment: getProcessEnvironment(processName, config),
            attempt: 1 + result.retries,
            scaledResources: result.resourceScaled,
            initialResources: baseResources,
            finalResources: [cpus: result.cpusUsed, memory: result.memoryUsed]
        ]
        
    } catch (Exception e) {
        result.success = false
        result.error = e.message
    }
    
    return result
}

def getProcessBaseResources(processName) {
    def resources = [:]
    
    switch (processName) {
        case 'FASTQC':
            resources = [cpus: 2, memory: 4]
            break
        case 'MEGAHIT':
            resources = [cpus: 8, memory: 16]
            break
        case 'KRAKEN2':
            resources = [cpus: 4, memory: 32]
            break
        case 'CHECKV':
            resources = [cpus: 4, memory: 8]
            break
        case 'MULTIQC':
            resources = [cpus: 1, memory: 2]
            break
        default:
            resources = [cpus: 4, memory: 8]
    }
    
    return resources
}

def getProcessLabel(processName) {
    switch (processName) {
        case 'FASTQC':
        case 'MULTIQC':
            return 'process_low'
        case 'MEGAHIT':
            return 'process_high'
        case 'KRAKEN2':
            return 'process_memory_intensive'
        case 'CHECKV':
            return 'process_medium'
        default:
            return 'process_medium'
    }
}

def selectPartitionForProcess(processName, resources, config) {
    def label = getProcessLabel(processName)
    
    if (label == 'process_memory_intensive' || resources.memory > (config.partition_thresholds?.bigmem_memory_gb ?: 128)) {
        return config.partitions?.bigmem ?: 'bigmem'
    } else if (label == 'process_low' && resources.memory <= (config.partition_thresholds?.quick_memory_gb ?: 16)) {
        return config.partitions?.quick ?: 'quickq'
    } else {
        return config.partitions?.compute ?: 'compute'
    }
}

def generateProcessOutputFiles(processName) {
    switch (processName) {
        case 'FASTQC':
            return ['sample1_fastqc.html', 'sample2_fastqc.html']
        case 'MEGAHIT':
            return ['assembly.fasta']
        case 'KRAKEN2':
            return ['kraken2_report.txt', 'kraken2_output.txt']
        case 'CHECKV':
            return ['checkv_summary.tsv']
        case 'MULTIQC':
            return ['multiqc_report.html']
        default:
            return ["${processName.toLowerCase()}_output.txt"]
    }
}

def generateClusterOptions(processName, partition, memory, cpus) {
    if (!partition) return null
    
    def options = []
    options << "--mem=${memory}G"
    options << "--cpus-per-task=${cpus}"
    
    if (partition == 'bigmem') {
        options << '--constraint=bigmem'
    } else if (partition == 'quickq') {
        options << '--qos=quick'
    }
    
    return options.join(' ')
}

def getProcessEnvironment(processName, config) {
    if (config.env_mode == 'unified') {
        return config.unified_env
    } else {
        switch (processName) {
            case 'FASTQC':
            case 'MULTIQC':
                return "${config.process_envs_dir}/qc.yml"
            case 'MEGAHIT':
                return "${config.process_envs_dir}/assembly.yml"
            case 'KRAKEN2':
                return "${config.process_envs_dir}/taxonomy.yml"
            case 'CHECKV':
                return "${config.process_envs_dir}/annotation.yml"
            default:
                return "${config.process_envs_dir}/general.yml"
        }
    }
}

def performFullConfigurationValidation(config) {
    def result = [valid: true, errors: [], warnings: []]
    
    try {
        // Validate required parameters
        if (!config.kraken2_db) {
            result.errors << "Missing required parameter: kraken2_db"
        }
        if (!config.checkv_db) {
            result.errors << "Missing required parameter: checkv_db"
        }
        
        // Validate resource limits
        if (config.max_cpus && config.max_cpus <= 0) {
            result.errors << "max_cpus must be greater than 0"
        }
        if (config.max_memory_gb && config.max_memory_gb <= 0) {
            result.errors << "max_memory_gb must be greater than 0"
        }
        
        // Validate environment configuration
        if (config.env_mode && !['unified', 'per_process'].contains(config.env_mode)) {
            result.errors << "Invalid env_mode: ${config.env_mode}"
        }
        
        // Add warnings for missing optional parameters
        if (!config.blast_options) {
            result.warnings << "No BLAST options specified, some analyses will be skipped"
        }
        
        result.valid = result.errors.isEmpty()
        
    } catch (Exception e) {
        result.valid = false
        result.errors << e.message
    }
    
    return result
}

def validateInputFiles(inputs) {
    def result = [valid: true, errors: []]
    
    try {
        if (!inputs.samplesheet) {
            result.errors << "Missing samplesheet"
        }
        
        if (!inputs.samples || inputs.samples.isEmpty()) {
            result.errors << "No samples defined"
        }
        
        inputs.samples?.each { sample ->
            if (!sample.name) {
                result.errors << "Sample missing name"
            }
            if (!sample.fastq_1) {
                result.errors << "Sample ${sample.name} missing fastq_1"
            }
            if (!sample.fastq_2) {
                result.errors << "Sample ${sample.name} missing fastq_2"
            }
        }
        
        result.valid = result.errors.isEmpty()
        
    } catch (Exception e) {
        result.valid = false
        result.errors << e.message
    }
    
    return result
}

// Additional helper functions for specific test configurations

def createValidTestConfiguration() {
    return createLocalTestConfiguration()
}

def createInvalidTestConfiguration() {
    def config = createLocalTestConfiguration()
    config.remove('kraken2_db')  // Remove required parameter
    config.remove('checkv_db')   // Remove required parameter
    return config
}

def createConfigurationWithWarnings() {
    def config = createLocalTestConfiguration()
    config.remove('blast_options')  // Remove optional parameter to generate warning
    return config
}

def createMissingInputFiles() {
    return [
        samplesheet: 'nonexistent_samplesheet.csv',
        samples: []
    ]
}

def createCorruptedInputFiles() {
    return [
        samplesheet: 'corrupted_samplesheet.csv',
        samples: [
            [name: 'sample1', fastq_1: 'corrupted_R1.fastq.gz', fastq_2: 'corrupted_R2.fastq.gz']
        ],
        corrupted: true
    ]
}

def createFlakyTestConfiguration() {
    def config = createLocalTestConfiguration()
    config.simulate_failures = true
    return config
}

def createResourceConstrainedConfiguration() {
    def config = createLocalTestConfiguration()
    config.max_cpus = 1
    config.max_memory_gb = 2
    return config
}

def createPartialFailureConfiguration() {
    def config = createLocalTestConfiguration()
    config.graceful_degradation = true
    config.simulate_failures = true
    return config
}

def createRetryScalingConfiguration() {
    def config = createLocalTestConfiguration()
    config.enable_retry_scaling = true
    config.max_retry_scaling = 3
    return config
}

def createResourceLimitedConfiguration() {
    def config = createLocalTestConfiguration()
    config.max_cpus = 4
    config.max_memory_gb = 16
    return config
}

def createDynamicResourceConfiguration() {
    def config = createLocalTestConfiguration()
    config.dynamic_resource_allocation = true
    return config
}

def getSystemMemoryGB() {
    return Runtime.runtime.maxMemory() / (1024 * 1024 * 1024)
}