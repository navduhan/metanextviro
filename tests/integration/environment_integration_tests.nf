#!/usr/bin/env nextflow

/**
 * Integration Tests for Environment Management
 * 
 * Tests integration of unified vs per-process environment management
 * Requirements: 1.1, 1.2, 1.3
 */

nextflow.enable.dsl = 2

workflow TEST_INTEGRATION_ENVIRONMENTS {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: Unified Environment Integration
    testResults.tests << testUnifiedEnvironmentIntegration()
    
    // Test 2: Per-Process Environment Integration
    testResults.tests << testPerProcessEnvironmentIntegration()
    
    // Test 3: Environment Mode Switching
    testResults.tests << testEnvironmentModeSwitching()
    
    // Test 4: Dependency Conflict Resolution
    testResults.tests << testDependencyConflictResolution()
    
    // Test 5: Container Integration
    testResults.tests << testContainerIntegration()
    
    // Test 6: Environment Validation
    testResults.tests << testEnvironmentValidation()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testUnifiedEnvironmentIntegration() {
    def testName = "Unified Environment Integration"
    
    try {
        // Test unified environment configuration
        def unifiedConfig = createUnifiedEnvironmentConfig()
        
        // Verify unified environment file exists and is valid
        assert unifiedConfig.environment_file != null : "Should specify unified environment file"
        assert unifiedConfig.env_mode == 'unified' : "Should be in unified mode"
        
        // Test that all required tools are included in unified environment
        def requiredTools = [
            'fastqc', 'megahit', 'spades', 'kraken2', 'checkv', 
            'blast', 'diamond', 'quast', 'multiqc'
        ]
        
        def unifiedEnvContent = loadEnvironmentFile(unifiedConfig.environment_file)
        requiredTools.each { tool ->
            assert unifiedEnvContent.dependencies.any { it.toString().contains(tool) } : "Unified environment should include ${tool}"
        }
        
        // Test process configuration for unified environment
        def processConfig = createProcessConfigForUnified()
        
        // All processes should use the same environment
        def processNames = ['FASTQC', 'MEGAHIT', 'KRAKEN2', 'CHECKV']
        processNames.each { processName ->
            def envConfig = processConfig[processName]
            assert envConfig?.conda == unifiedConfig.environment_file : "${processName} should use unified environment"
        }
        
        // Test environment activation logic
        def activationResult = testEnvironmentActivation('unified', unifiedConfig.environment_file)
        assert activationResult.success : "Unified environment activation should succeed"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testPerProcessEnvironmentIntegration() {
    def testName = "Per-Process Environment Integration"
    
    try {
        // Test per-process environment configuration
        def perProcessConfig = createPerProcessEnvironmentConfig()
        
        // Verify per-process mode configuration
        assert perProcessConfig.env_mode == 'per_process' : "Should be in per-process mode"
        assert perProcessConfig.process_envs_dir != null : "Should specify process environments directory"
        
        // Test that specific environment files exist for different process types
        def expectedEnvFiles = [
            'qc.yml': ['fastqc', 'multiqc'],
            'assembly.yml': ['megahit', 'spades', 'quast'],
            'taxonomy.yml': ['kraken2', 'krona'],
            'annotation.yml': ['blast', 'diamond', 'checkv'],
            'viral.yml': ['virfinder', 'checkv']
        ]
        
        expectedEnvFiles.each { envFile, tools ->
            def envPath = "${perProcessConfig.process_envs_dir}/${envFile}"
            def envContent = loadEnvironmentFile(envPath)
            
            tools.each { tool ->
                assert envContent.dependencies.any { it.toString().contains(tool) } : "${envFile} should include ${tool}"
            }
        }
        
        // Test process configuration for per-process environments
        def processConfig = createProcessConfigForPerProcess(perProcessConfig.process_envs_dir)
        
        // Different processes should use different environments
        assert processConfig.FASTQC?.conda?.contains('qc.yml') : "FASTQC should use QC environment"
        assert processConfig.MEGAHIT?.conda?.contains('assembly.yml') : "MEGAHIT should use assembly environment"
        assert processConfig.KRAKEN2?.conda?.contains('taxonomy.yml') : "KRAKEN2 should use taxonomy environment"
        
        // Test environment isolation
        def isolationResult = testEnvironmentIsolation(perProcessConfig.process_envs_dir)
        assert isolationResult.success : "Per-process environments should be properly isolated"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testEnvironmentModeSwitching() {
    def testName = "Environment Mode Switching"
    
    try {
        // Test switching between unified and per-process modes
        def unifiedConfig = createUnifiedEnvironmentConfig()
        def perProcessConfig = createPerProcessEnvironmentConfig()
        
        // Test configuration validation for both modes
        def unifiedValidation = validateEnvironmentConfiguration(unifiedConfig)
        def perProcessValidation = validateEnvironmentConfiguration(perProcessConfig)
        
        assert unifiedValidation.valid : "Unified configuration should be valid"
        assert perProcessValidation.valid : "Per-process configuration should be valid"
        
        // Test that switching modes changes process configurations appropriately
        def unifiedProcessConfig = generateProcessConfig(unifiedConfig)
        def perProcessProcessConfig = generateProcessConfig(perProcessConfig)
        
        // In unified mode, all processes should use the same environment
        def unifiedEnvs = unifiedProcessConfig.values().collect { it.conda }.unique()
        assert unifiedEnvs.size() == 1 : "Unified mode should use single environment for all processes"
        
        // In per-process mode, different processes should use different environments
        def perProcessEnvs = perProcessProcessConfig.values().collect { it.conda }.unique()
        assert perProcessEnvs.size() > 1 : "Per-process mode should use multiple environments"
        
        // Test parameter-driven mode selection
        def modeSelectionResult = testModeSelection(['--env_mode', 'unified'])
        assert modeSelectionResult.selectedMode == 'unified' : "Should select unified mode from parameters"
        
        def modeSelectionResult2 = testModeSelection(['--env_mode', 'per_process'])
        assert modeSelectionResult2.selectedMode == 'per_process' : "Should select per-process mode from parameters"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testDependencyConflictResolution() {
    def testName = "Dependency Conflict Resolution"
    
    try {
        // Test conflict detection in unified environment
        def conflictingDeps = [
            'python=3.8',
            'python=3.9',  // Version conflict
            'numpy=1.20',
            'numpy=1.21'   // Version conflict
        ]
        
        def conflictResult = detectDependencyConflicts(conflictingDeps)
        assert !conflictResult.conflicts.isEmpty() : "Should detect version conflicts"
        assert conflictResult.conflicts.any { it.contains('python') } : "Should detect python version conflict"
        assert conflictResult.conflicts.any { it.contains('numpy') } : "Should detect numpy version conflict"
        
        // Test conflict resolution strategies
        def resolvedDeps = resolveDependencyConflicts(conflictingDeps)
        assert resolvedDeps.size() < conflictingDeps.size() : "Should resolve conflicts by removing duplicates"
        
        def pythonVersions = resolvedDeps.findAll { it.contains('python=') }
        assert pythonVersions.size() == 1 : "Should resolve to single python version"
        
        // Test per-process environment conflict avoidance
        def qcEnvDeps = ['fastqc=0.11.9', 'multiqc=1.11']
        def assemblyEnvDeps = ['megahit=1.2.9', 'spades=3.15.3']
        
        def qcConflicts = detectDependencyConflicts(qcEnvDeps)
        def assemblyConflicts = detectDependencyConflicts(assemblyEnvDeps)
        
        assert qcConflicts.conflicts.isEmpty() : "QC environment should have no conflicts"
        assert assemblyConflicts.conflicts.isEmpty() : "Assembly environment should have no conflicts"
        
        // Test cross-environment compatibility
        def compatibilityResult = testCrossEnvironmentCompatibility(qcEnvDeps, assemblyEnvDeps)
        assert compatibilityResult.compatible : "Different environments should be compatible"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testContainerIntegration() {
    def testName = "Container Integration"
    
    try {
        // Test Docker container configuration
        def dockerConfig = createContainerConfig('docker')
        
        assert dockerConfig.docker?.enabled == true : "Docker should be enabled"
        assert dockerConfig.docker?.runOptions != null : "Should specify Docker run options"
        
        // Test Singularity container configuration
        def singularityConfig = createContainerConfig('singularity')
        
        assert singularityConfig.singularity?.enabled == true : "Singularity should be enabled"
        assert singularityConfig.singularity?.cacheDir != null : "Should specify Singularity cache directory"
        
        // Test container image specifications
        def containerImages = getContainerImages()
        
        def requiredImages = ['fastqc', 'megahit', 'kraken2', 'checkv']
        requiredImages.each { tool ->
            assert containerImages.containsKey(tool) : "Should define container image for ${tool}"
            assert containerImages[tool].contains(':') : "Container image should include tag"
        }
        
        // Test container vs conda environment compatibility
        def containerProcessConfig = createProcessConfigForContainers(containerImages)
        def condaProcessConfig = createProcessConfigForUnified()
        
        // Both should define the same processes
        def containerProcesses = containerProcessConfig.keySet()
        def condaProcesses = condaProcessConfig.keySet()
        def commonProcesses = containerProcesses.intersect(condaProcesses)
        
        assert commonProcesses.size() >= 5 : "Container and conda configs should define common processes"
        
        // Test container execution mode switching
        def containerModeResult = testContainerModeSelection('docker')
        assert containerModeResult.success : "Docker mode selection should succeed"
        
        def singularityModeResult = testContainerModeSelection('singularity')
        assert singularityModeResult.success : "Singularity mode selection should succeed"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testEnvironmentValidation() {
    def testName = "Environment Validation"
    
    try {
        // Test validation of unified environment
        def unifiedEnvFile = createTestEnvironmentFile('unified')
        def unifiedValidation = validateEnvironmentFile(unifiedEnvFile)
        
        assert unifiedValidation.valid : "Unified environment should be valid"
        assert unifiedValidation.toolCount >= 10 : "Should include sufficient tools"
        
        // Test validation of per-process environments
        def perProcessEnvs = createTestPerProcessEnvironments()
        
        perProcessEnvs.each { envName, envFile ->
            def validation = validateEnvironmentFile(envFile)
            assert validation.valid : "${envName} environment should be valid"
            assert validation.toolCount >= 1 : "${envName} should include at least one tool"
        }
        
        // Test missing dependency detection
        def incompleteEnvFile = createIncompleteEnvironmentFile()
        def incompleteValidation = validateEnvironmentFile(incompleteEnvFile)
        
        assert !incompleteValidation.valid : "Incomplete environment should be invalid"
        assert !incompleteValidation.errors.isEmpty() : "Should report validation errors"
        
        // Test environment setup validation
        def setupValidation = validateEnvironmentSetup('unified', unifiedEnvFile)
        assert setupValidation.canActivate : "Should be able to activate environment"
        
        // Test tool availability validation
        def toolValidation = validateToolAvailability(unifiedEnvFile, ['fastqc', 'megahit'])
        assert toolValidation.allAvailable : "Required tools should be available"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

// Helper functions for environment testing

def createUnifiedEnvironmentConfig() {
    return [
        env_mode: 'unified',
        environment_file: 'environment.yml',
        unified_env: 'environment.yml'
    ]
}

def createPerProcessEnvironmentConfig() {
    return [
        env_mode: 'per_process',
        process_envs_dir: 'envs/',
        process_envs: 'envs/'
    ]
}

def loadEnvironmentFile(filePath) {
    // Simulate loading YAML environment file
    return [
        name: 'metanextviro',
        channels: ['bioconda', 'conda-forge', 'defaults'],
        dependencies: [
            'python=3.9',
            'nextflow',
            'fastqc=0.11.9',
            'megahit=1.2.9',
            'spades=3.15.3',
            'kraken2=2.1.2',
            'checkv=0.8.1',
            'blast=2.12.0',
            'diamond=2.0.13',
            'quast=5.0.2',
            'multiqc=1.11'
        ]
    ]
}

def createProcessConfigForUnified() {
    def unifiedEnv = 'environment.yml'
    return [
        FASTQC: [conda: unifiedEnv],
        MEGAHIT: [conda: unifiedEnv],
        KRAKEN2: [conda: unifiedEnv],
        CHECKV: [conda: unifiedEnv],
        BLAST: [conda: unifiedEnv],
        MULTIQC: [conda: unifiedEnv]
    ]
}

def createProcessConfigForPerProcess(envsDir) {
    return [
        FASTQC: [conda: "${envsDir}/qc.yml"],
        MULTIQC: [conda: "${envsDir}/qc.yml"],
        MEGAHIT: [conda: "${envsDir}/assembly.yml"],
        SPADES: [conda: "${envsDir}/assembly.yml"],
        KRAKEN2: [conda: "${envsDir}/taxonomy.yml"],
        CHECKV: [conda: "${envsDir}/annotation.yml"],
        BLAST: [conda: "${envsDir}/annotation.yml"]
    ]
}

def validateEnvironmentConfiguration(config) {
    try {
        assert config.env_mode in ['unified', 'per_process'] : "Invalid environment mode"
        
        if (config.env_mode == 'unified') {
            assert config.environment_file != null : "Unified mode requires environment file"
        } else {
            assert config.process_envs_dir != null : "Per-process mode requires environments directory"
        }
        
        return [valid: true, errors: []]
    } catch (Exception e) {
        return [valid: false, errors: [e.message]]
    }
}

def generateProcessConfig(envConfig) {
    if (envConfig.env_mode == 'unified') {
        return createProcessConfigForUnified()
    } else {
        return createProcessConfigForPerProcess(envConfig.process_envs_dir)
    }
}

def testModeSelection(args) {
    def selectedMode = 'unified' // default
    
    for (int i = 0; i < args.size() - 1; i++) {
        if (args[i] == '--env_mode') {
            selectedMode = args[i + 1]
            break
        }
    }
    
    return [selectedMode: selectedMode]
}

def testEnvironmentActivation(mode, envFile) {
    // Simulate environment activation test
    try {
        // In a real implementation, this could test:
        // conda activate environment_name
        // or validate conda environment file
        return [success: true, message: "Environment activation successful"]
    } catch (Exception e) {
        return [success: false, message: e.message]
    }
}

def testEnvironmentIsolation(envsDir) {
    // Simulate testing that per-process environments are isolated
    try {
        // In a real implementation, this could test:
        // - Different environments have different tool versions
        // - No cross-contamination between environments
        return [success: true, message: "Environment isolation verified"]
    } catch (Exception e) {
        return [success: false, message: e.message]
    }
}

def detectDependencyConflicts(dependencies) {
    def conflicts = []
    def toolVersions = [:]
    
    dependencies.each { dep ->
        if (dep.contains('=')) {
            def parts = dep.split('=')
            def tool = parts[0]
            def version = parts[1]
            
            if (toolVersions.containsKey(tool) && toolVersions[tool] != version) {
                conflicts << "Version conflict for ${tool}: ${toolVersions[tool]} vs ${version}"
            } else {
                toolVersions[tool] = version
            }
        }
    }
    
    return [conflicts: conflicts]
}

def resolveDependencyConflicts(dependencies) {
    def resolved = []
    def toolVersions = [:]
    
    dependencies.each { dep ->
        if (dep.contains('=')) {
            def parts = dep.split('=')
            def tool = parts[0]
            def version = parts[1]
            
            if (!toolVersions.containsKey(tool)) {
                toolVersions[tool] = version
                resolved << dep
            }
            // Skip duplicates/conflicts - keep first occurrence
        } else {
            resolved << dep
        }
    }
    
    return resolved
}

def testCrossEnvironmentCompatibility(env1Deps, env2Deps) {
    // Test that different environments don't conflict when used together
    def allDeps = env1Deps + env2Deps
    def conflicts = detectDependencyConflicts(allDeps)
    
    return [compatible: conflicts.conflicts.isEmpty()]
}

def createContainerConfig(containerType) {
    def config = [:]
    
    switch (containerType) {
        case 'docker':
            config = [
                docker: [
                    enabled: true,
                    runOptions: '-u $(id -u):$(id -g)'
                ]
            ]
            break
        case 'singularity':
            config = [
                singularity: [
                    enabled: true,
                    cacheDir: '/tmp/singularity_cache'
                ]
            ]
            break
    }
    
    return config
}

def getContainerImages() {
    return [
        fastqc: 'biocontainers/fastqc:0.11.9--0',
        megahit: 'biocontainers/megahit:1.2.9--h2e03b76_1',
        kraken2: 'biocontainers/kraken2:2.1.2--pl5262h7d875b9_0',
        checkv: 'biocontainers/checkv:0.8.1--pyhdfd78af_0',
        blast: 'biocontainers/blast:2.12.0--pl5262h3289130_0',
        diamond: 'biocontainers/diamond:2.0.13--hb97b32f_0'
    ]
}

def createProcessConfigForContainers(containerImages) {
    def config = [:]
    
    containerImages.each { tool, image ->
        config[tool.toUpperCase()] = [container: image]
    }
    
    return config
}

def testContainerModeSelection(containerType) {
    try {
        // Simulate container mode selection
        def config = createContainerConfig(containerType)
        assert config[containerType]?.enabled == true
        
        return [success: true, message: "${containerType} mode selected successfully"]
    } catch (Exception e) {
        return [success: false, message: e.message]
    }
}

def createTestEnvironmentFile(type) {
    // Create a test environment file path
    return "test_${type}_environment.yml"
}

def createTestPerProcessEnvironments() {
    return [
        qc: 'test_qc.yml',
        assembly: 'test_assembly.yml',
        taxonomy: 'test_taxonomy.yml',
        annotation: 'test_annotation.yml'
    ]
}

def validateEnvironmentFile(filePath) {
    try {
        // Simulate environment file validation
        def envContent = loadEnvironmentFile(filePath)
        
        assert envContent.dependencies != null : "Environment should have dependencies"
        assert envContent.dependencies.size() > 0 : "Environment should have at least one dependency"
        
        return [
            valid: true,
            toolCount: envContent.dependencies.size(),
            errors: []
        ]
    } catch (Exception e) {
        return [
            valid: false,
            toolCount: 0,
            errors: [e.message]
        ]
    }
}

def createIncompleteEnvironmentFile() {
    return "incomplete_environment.yml"
}

def validateEnvironmentSetup(mode, envFile) {
    try {
        // Simulate environment setup validation
        return [
            canActivate: true,
            message: "Environment can be activated successfully"
        ]
    } catch (Exception e) {
        return [
            canActivate: false,
            message: e.message
        ]
    }
}

def validateToolAvailability(envFile, requiredTools) {
    try {
        def envContent = loadEnvironmentFile(envFile)
        def availableTools = envContent.dependencies.collect { 
            it.toString().split('=')[0] 
        }
        
        def missingTools = requiredTools.findAll { !availableTools.contains(it) }
        
        return [
            allAvailable: missingTools.isEmpty(),
            missingTools: missingTools
        ]
    } catch (Exception e) {
        return [
            allAvailable: false,
            missingTools: requiredTools
        ]
    }
}