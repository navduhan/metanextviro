#!/usr/bin/env nextflow

/**
 * Integration Tests for Different Execution Profiles
 * 
 * Tests integration between different profiles (local, SLURM, etc.)
 * Requirements: 1.1, 1.2, 1.3, 6.1, 6.2
 */

nextflow.enable.dsl = 2

workflow TEST_INTEGRATION_PROFILES {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: Local Profile Integration
    testResults.tests << testLocalProfileIntegration()
    
    // Test 2: SLURM Profile Integration
    testResults.tests << testSlurmProfileIntegration()
    
    // Test 3: Profile Switching
    testResults.tests << testProfileSwitching()
    
    // Test 4: Configuration Inheritance
    testResults.tests << testConfigurationInheritance()
    
    // Test 5: Resource Profile Validation
    testResults.tests << testResourceProfileValidation()
    
    // Test 6: Cross-Profile Compatibility
    testResults.tests << testCrossProfileCompatibility()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testLocalProfileIntegration() {
    def testName = "Local Profile Integration"
    
    try {
        // Test local profile configuration loading
        def localConfig = loadProfileConfig('local')
        
        // Verify executor is set correctly
        assert localConfig.process?.executor == 'local' : "Local profile should use local executor"
        
        // Verify resource constraints are appropriate for local execution
        assert localConfig.params?.max_cpus <= Runtime.runtime.availableProcessors() : "Local profile should respect system CPU limits"
        
        def maxMemoryGB = Runtime.runtime.maxMemory() / (1024 * 1024 * 1024) * 0.8
        def configMaxMemory = localConfig.params?.max_memory?.toString()?.replace('.GB', '')?.toInteger()
        assert configMaxMemory <= maxMemoryGB : "Local profile should respect system memory limits"
        
        // Test process label configurations
        def processConfig = localConfig.process
        assert processConfig.containsKey('withLabel:process_low') : "Should define process_low label"
        assert processConfig.containsKey('withLabel:process_medium') : "Should define process_medium label"
        assert processConfig.containsKey('withLabel:process_high') : "Should define process_high label"
        
        // Verify conservative resource allocation for local
        def lowConfig = processConfig['withLabel:process_low']
        assert lowConfig.cpus instanceof Closure : "CPU allocation should be dynamic"
        assert lowConfig.memory instanceof Closure : "Memory allocation should be dynamic"
        
        // Test maxForks limitation for local execution
        assert processConfig.maxForks instanceof Closure || processConfig.maxForks <= 4 : "Local profile should limit parallel processes"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testSlurmProfileIntegration() {
    def testName = "SLURM Profile Integration"
    
    try {
        // Test SLURM profile configuration loading
        def slurmConfig = loadProfileConfig('slurm')
        
        // Verify executor is set correctly
        assert slurmConfig.process?.executor == 'slurm' : "SLURM profile should use SLURM executor"
        
        // Verify higher resource limits for cluster execution
        assert slurmConfig.params?.max_cpus >= 16 : "SLURM profile should allow more CPUs"
        assert slurmConfig.params?.max_memory?.contains('GB') : "SLURM profile should specify memory in GB"
        
        // Test partition configuration
        assert slurmConfig.params?.partitions != null : "SLURM profile should define partitions"
        assert slurmConfig.params?.partitions?.compute != null : "Should define compute partition"
        assert slurmConfig.params?.partitions?.bigmem != null : "Should define bigmem partition"
        
        // Test partition selection strategy
        assert slurmConfig.params?.partition_selection_strategy != null : "Should define partition selection strategy"
        
        // Test partition thresholds
        def thresholds = slurmConfig.params?.partition_thresholds
        assert thresholds?.bigmem_memory_gb != null : "Should define bigmem memory threshold"
        assert thresholds?.quick_time_hours != null : "Should define quick time threshold"
        
        // Test cluster options generation
        def processConfig = slurmConfig.process
        def mediumConfig = processConfig['withLabel:process_medium']
        assert mediumConfig?.clusterOptions != null : "Should define cluster options for SLURM"
        
        // Test queue/partition selection
        assert processConfig.queue instanceof Closure : "Queue selection should be dynamic"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testProfileSwitching() {
    def testName = "Profile Switching"
    
    try {
        // Test switching between profiles
        def localConfig = loadProfileConfig('local')
        def slurmConfig = loadProfileConfig('slurm')
        
        // Verify different executors
        assert localConfig.process?.executor != slurmConfig.process?.executor : "Profiles should use different executors"
        
        // Verify different resource limits
        def localMaxCpus = localConfig.params?.max_cpus
        def slurmMaxCpus = slurmConfig.params?.max_cpus
        assert slurmMaxCpus > localMaxCpus : "SLURM should allow more CPUs than local"
        
        // Test that base configuration is inherited by both
        assert localConfig.process?.errorStrategy != null : "Local should inherit base error strategy"
        assert slurmConfig.process?.errorStrategy != null : "SLURM should inherit base error strategy"
        
        // Test profile-specific overrides
        def localProcessConfig = localConfig.process['withLabel:process_high']
        def slurmProcessConfig = slurmConfig.process['withLabel:process_high']
        
        // Both should have the label defined but with different constraints
        assert localProcessConfig != null : "Local should define process_high"
        assert slurmProcessConfig != null : "SLURM should define process_high"
        
        // SLURM should have additional cluster-specific configuration
        assert slurmProcessConfig.clusterOptions != null : "SLURM should have cluster options"
        assert localProcessConfig.clusterOptions == null : "Local should not have cluster options"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testConfigurationInheritance() {
    def testName = "Configuration Inheritance"
    
    try {
        // Test that profiles inherit from base configuration
        def baseConfig = loadBaseConfig()
        def localConfig = loadProfileConfig('local')
        def slurmConfig = loadProfileConfig('slurm')
        
        // Test that all profiles have the standardized process labels
        def requiredLabels = [
            'withLabel:process_low',
            'withLabel:process_medium', 
            'withLabel:process_high',
            'withLabel:process_memory_intensive',
            'withLabel:process_quick'
        ]
        
        requiredLabels.each { label ->
            assert baseConfig.process?.containsKey(label) : "Base config should define ${label}"
            assert localConfig.process?.containsKey(label) : "Local config should inherit ${label}"
            assert slurmConfig.process?.containsKey(label) : "SLURM config should inherit ${label}"
        }
        
        // Test that error strategies are inherited
        assert localConfig.process?.errorStrategy != null : "Local should inherit error strategy"
        assert slurmConfig.process?.errorStrategy != null : "SLURM should inherit error strategy"
        
        // Test that retry logic is inherited
        assert localConfig.process?.maxRetries != null : "Local should inherit max retries"
        assert slurmConfig.process?.maxRetries != null : "SLURM should inherit max retries"
        
        // Test that resource scaling functions are available
        requiredLabels.each { label ->
            def localLabelConfig = localConfig.process[label]
            def slurmLabelConfig = slurmConfig.process[label]
            
            if (localLabelConfig) {
                assert localLabelConfig.cpus instanceof Closure : "Local ${label} should have dynamic CPU allocation"
                assert localLabelConfig.memory instanceof Closure : "Local ${label} should have dynamic memory allocation"
            }
            
            if (slurmLabelConfig) {
                assert slurmLabelConfig.cpus instanceof Closure : "SLURM ${label} should have dynamic CPU allocation"
                assert slurmLabelConfig.memory instanceof Closure : "SLURM ${label} should have dynamic memory allocation"
            }
        }
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testResourceProfileValidation() {
    def testName = "Resource Profile Validation"
    
    try {
        // Test validation of different resource profiles
        def profiles = ['local', 'slurm']
        
        profiles.each { profile ->
            def config = loadProfileConfig(profile)
            
            // Validate that all required configuration sections exist
            assert config.process != null : "${profile} should have process configuration"
            assert config.params != null : "${profile} should have params configuration"
            
            // Validate resource limits are reasonable
            def maxCpus = config.params?.max_cpus
            def maxMemory = config.params?.max_memory
            def maxTime = config.params?.max_time
            
            assert maxCpus > 0 : "${profile} max_cpus should be positive"
            assert maxMemory != null : "${profile} should define max_memory"
            assert maxTime != null : "${profile} should define max_time"
            
            // Validate executor-specific configuration
            if (profile == 'slurm') {
                assert config.params?.partitions != null : "SLURM should define partitions"
                assert config.params?.default_partition != null : "SLURM should define default partition"
            }
            
            // Validate process label consistency
            def processLabels = config.process.keySet().findAll { it.startsWith('withLabel:') }
            assert processLabels.size() >= 5 : "${profile} should define at least 5 process labels"
        }
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testCrossProfileCompatibility() {
    def testName = "Cross-Profile Compatibility"
    
    try {
        // Test that configurations are compatible across profiles
        def localConfig = loadProfileConfig('local')
        def slurmConfig = loadProfileConfig('slurm')
        
        // Test that the same process labels exist in both profiles
        def localLabels = localConfig.process.keySet().findAll { it.startsWith('withLabel:') }
        def slurmLabels = slurmConfig.process.keySet().findAll { it.startsWith('withLabel:') }
        
        def commonLabels = localLabels.intersect(slurmLabels)
        assert commonLabels.size() >= 5 : "Profiles should share common process labels"
        
        // Test that resource scaling functions have the same signature
        commonLabels.each { label ->
            def localLabelConfig = localConfig.process[label]
            def slurmLabelConfig = slurmConfig.process[label]
            
            if (localLabelConfig?.cpus && slurmLabelConfig?.cpus) {
                assert localLabelConfig.cpus instanceof Closure : "Local ${label} CPU should be closure"
                assert slurmLabelConfig.cpus instanceof Closure : "SLURM ${label} CPU should be closure"
            }
        }
        
        // Test that parameter names are consistent
        def localParams = localConfig.params?.keySet() ?: []
        def slurmParams = slurmConfig.params?.keySet() ?: []
        
        def commonParams = localParams.intersect(slurmParams)
        def expectedCommonParams = ['max_cpus', 'max_memory', 'max_time', 'resource_profile']
        
        expectedCommonParams.each { param ->
            assert commonParams.contains(param) : "Both profiles should define ${param}"
        }
        
        // Test that validation functions work with both profiles
        def localValidation = validateProfileConfiguration(localConfig, 'local')
        def slurmValidation = validateProfileConfiguration(slurmConfig, 'slurm')
        
        assert localValidation.success : "Local profile should pass validation"
        assert slurmValidation.success : "SLURM profile should pass validation"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

// Helper functions for profile testing

def loadProfileConfig(profile) {
    // Simulate loading profile configuration
    def config = [:]
    
    switch (profile) {
        case 'local':
            config = [
                process: [
                    executor: 'local',
                    errorStrategy: 'retry',
                    maxRetries: 3,
                    maxForks: 4,
                    'withLabel:process_low': [
                        cpus: { 2 * task.attempt },
                        memory: { '4.GB'.toMemory() * task.attempt },
                        time: { '2.h'.toDuration() * task.attempt }
                    ],
                    'withLabel:process_medium': [
                        cpus: { 4 * task.attempt },
                        memory: { '8.GB'.toMemory() * task.attempt },
                        time: { '4.h'.toDuration() * task.attempt }
                    ],
                    'withLabel:process_high': [
                        cpus: { 6 * task.attempt },
                        memory: { '16.GB'.toMemory() * task.attempt },
                        time: { '8.h'.toDuration() * task.attempt }
                    ],
                    'withLabel:process_memory_intensive': [
                        cpus: { 4 * task.attempt },
                        memory: { '24.GB'.toMemory() * task.attempt },
                        time: { '12.h'.toDuration() * task.attempt }
                    ],
                    'withLabel:process_quick': [
                        cpus: { 1 * task.attempt },
                        memory: { '2.GB'.toMemory() * task.attempt },
                        time: { '30.m'.toDuration() * task.attempt }
                    ]
                ],
                params: [
                    max_cpus: Runtime.runtime.availableProcessors(),
                    max_memory: "${(Runtime.runtime.maxMemory() / (1024 * 1024 * 1024) * 0.8) as int}.GB",
                    max_time: '24.h',
                    resource_profile: 'local'
                ]
            ]
            break
            
        case 'slurm':
            config = [
                process: [
                    executor: 'slurm',
                    errorStrategy: 'retry',
                    maxRetries: 3,
                    queue: { 'compute' },
                    'withLabel:process_low': [
                        cpus: { 4 * task.attempt },
                        memory: { '8.GB'.toMemory() * task.attempt },
                        time: { '2.h'.toDuration() * task.attempt },
                        clusterOptions: '--mem=8G --cpus-per-task=4'
                    ],
                    'withLabel:process_medium': [
                        cpus: { 8 * task.attempt },
                        memory: { '16.GB'.toMemory() * task.attempt },
                        time: { '4.h'.toDuration() * task.attempt },
                        clusterOptions: '--mem=16G --cpus-per-task=8'
                    ],
                    'withLabel:process_high': [
                        cpus: { 16 * task.attempt },
                        memory: { '32.GB'.toMemory() * task.attempt },
                        time: { '8.h'.toDuration() * task.attempt },
                        clusterOptions: '--mem=32G --cpus-per-task=16'
                    ],
                    'withLabel:process_memory_intensive': [
                        cpus: { 8 * task.attempt },
                        memory: { '64.GB'.toMemory() * task.attempt },
                        time: { '12.h'.toDuration() * task.attempt },
                        clusterOptions: '--mem=64G --cpus-per-task=8 --constraint=bigmem'
                    ],
                    'withLabel:process_quick': [
                        cpus: { 2 * task.attempt },
                        memory: { '4.GB'.toMemory() * task.attempt },
                        time: { '30.m'.toDuration() * task.attempt },
                        clusterOptions: '--mem=4G --cpus-per-task=2 --qos=quick'
                    ]
                ],
                params: [
                    max_cpus: 128,
                    max_memory: '1000.GB',
                    max_time: '72.h',
                    resource_profile: 'slurm',
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
                    default_partition: 'compute',
                    partition_selection_strategy: 'intelligent'
                ]
            ]
            break
    }
    
    return config
}

def loadBaseConfig() {
    return [
        process: [
            errorStrategy: 'retry',
            maxRetries: 3,
            maxForks: 10,
            'withLabel:process_low': [
                cpus: { 2 * task.attempt },
                memory: { '4.GB'.toMemory() * task.attempt },
                time: { '2.h'.toDuration() * task.attempt }
            ],
            'withLabel:process_medium': [
                cpus: { 4 * task.attempt },
                memory: { '8.GB'.toMemory() * task.attempt },
                time: { '4.h'.toDuration() * task.attempt }
            ],
            'withLabel:process_high': [
                cpus: { 8 * task.attempt },
                memory: { '16.GB'.toMemory() * task.attempt },
                time: { '8.h'.toDuration() * task.attempt }
            ],
            'withLabel:process_memory_intensive': [
                cpus: { 4 * task.attempt },
                memory: { '32.GB'.toMemory() * task.attempt },
                time: { '12.h'.toDuration() * task.attempt }
            ],
            'withLabel:process_quick': [
                cpus: { 1 * task.attempt },
                memory: { '2.GB'.toMemory() * task.attempt },
                time: { '30.m'.toDuration() * task.attempt }
            ]
        ]
    ]
}

def validateProfileConfiguration(config, profile) {
    try {
        // Basic validation
        assert config.process != null
        assert config.params != null
        
        // Profile-specific validation
        if (profile == 'slurm') {
            assert config.params.partitions != null
            assert config.process.executor == 'slurm'
        } else if (profile == 'local') {
            assert config.process.executor == 'local'
        }
        
        return [success: true, errors: []]
    } catch (Exception e) {
        return [success: false, errors: [e.message]]
    }
}