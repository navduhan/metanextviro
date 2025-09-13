#!/usr/bin/env nextflow

/*
 * Configuration Initialization Script
 * Helps users set up appropriate configuration for their environment
 */

nextflow.enable.dsl = 2

workflow {
    main:
        initializeConfiguration()
}

def initializeConfiguration() {
    log.info "=== MetaNextViro Configuration Initialization ==="
    log.info ""
    
    // Detect system capabilities
    def systemInfo = detectSystemCapabilities()
    log.info "Detected system capabilities:"
    log.info "  CPUs: ${systemInfo.cpus}"
    log.info "  Memory: ${systemInfo.memory}GB"
    log.info "  Executor: ${systemInfo.executor}"
    log.info ""
    
    // Recommend configuration profile
    def recommendedProfile = recommendProfile(systemInfo)
    log.info "Recommended configuration profile: ${recommendedProfile}"
    log.info ""
    
    // Generate configuration suggestions
    generateConfigurationSuggestions(systemInfo, recommendedProfile)
    
    // Validate current configuration if exists
    if (params.validate_resources) {
        log.info "Validating current configuration..."
        validateCurrentConfiguration()
    }
}

def detectSystemCapabilities() {
    def cpus = Runtime.runtime.availableProcessors()
    def maxMemoryGB = Runtime.runtime.maxMemory() / (1024 * 1024 * 1024)
    def executor = workflow.executor ?: 'local'
    
    return [
        cpus: cpus,
        memory: maxMemoryGB as int,
        executor: executor
    ]
}

def recommendProfile(systemInfo) {
    if (systemInfo.executor == 'slurm') {
        return 'large_hpc'
    } else if (systemInfo.cpus >= 16 && systemInfo.memory >= 64) {
        return 'medium'
    } else if (systemInfo.cpus >= 8 && systemInfo.memory >= 16) {
        return 'small'
    } else {
        return 'test'
    }
}

def generateConfigurationSuggestions(systemInfo, profile) {
    log.info "Configuration suggestions for your system:"
    log.info ""
    
    // Resource allocation suggestions
    log.info "Resource Allocation:"
    def maxForks = Math.min(systemInfo.cpus.intdiv(2), 10)
    log.info "  max_forks: ${maxForks}"
    log.info "  max_cpus: ${systemInfo.cpus}"
    log.info "  max_memory: '${(systemInfo.memory * 0.8) as int}.GB'"
    log.info ""
    
    // Profile-specific suggestions
    log.info "Profile-specific settings:"
    switch (profile) {
        case 'test':
            log.info "  - Use minimal resources for testing"
            log.info "  - Set max_retry_scaling = 1"
            log.info "  - Consider using smaller datasets"
            break
        case 'small':
            log.info "  - Limit parallel processes to avoid resource contention"
            log.info "  - Use conservative memory allocation"
            log.info "  - Consider per-process conda environments"
            break
        case 'medium':
            log.info "  - Good balance of parallelization and resource usage"
            log.info "  - Can use unified conda environment"
            log.info "  - Enable retry scaling for robustness"
            break
        case 'large_hpc':
            log.info "  - Optimize for cluster scheduling"
            log.info "  - Use intelligent partition selection"
            log.info "  - Enable aggressive retry scaling"
            break
    }
    log.info ""
    
    // Database configuration suggestions
    log.info "Database Configuration:"
    log.info "  - Ensure all database paths are accessible"
    log.info "  - Use local storage for better I/O performance"
    log.info "  - Consider database indexing for large datasets"
    log.info ""
    
    // Example configuration
    generateExampleConfig(systemInfo, profile)
}

def generateExampleConfig(systemInfo, profile) {
    log.info "Example configuration for your system:"
    log.info ""
    log.info "// Add to your nextflow.config or use as separate profile"
    log.info "profiles {"
    log.info "    ${profile}_custom {"
    log.info "        params {"
    log.info "            max_cpus = ${systemInfo.cpus}"
    log.info "            max_memory = '${(systemInfo.memory * 0.8) as int}.GB'"
    log.info "            max_forks = ${Math.min(systemInfo.cpus.intdiv(2), 10)}"
    log.info "            resource_profile = '${profile}'"
    log.info "            enable_retry_scaling = true"
    log.info "            max_retry_scaling = ${profile == 'test' ? 1 : (profile == 'large_hpc' ? 3 : 2)}"
    log.info "        }"
    
    if (systemInfo.executor == 'slurm') {
        log.info "        process {"
        log.info "            executor = 'slurm'"
        log.info "            queue = 'compute'"
        log.info "        }"
    }
    
    log.info "    }"
    log.info "}"
    log.info ""
}

def validateCurrentConfiguration() {
    // Import and run validation
    try {
        // This would normally import ConfigValidator, but for demo purposes:
        log.info "✅ Configuration validation would run here"
        log.info "   - Resource consistency checks"
        log.info "   - Database path validation"
        log.info "   - Profile compatibility verification"
    } catch (Exception e) {
        log.warn "Configuration validation failed: ${e.message}"
    }
}