/*
 * Configuration Validation Library
 * Provides functions to validate resource configurations and consistency
 */

class ConfigValidator {
    
    static def validateResourceConfiguration(params) {
        def errors = []
        def warnings = []
        
        // Validate basic resource parameters
        if (params.max_cpus && params.max_cpus <= 0) {
            errors << "max_cpus must be greater than 0, got: ${params.max_cpus}"
        }
        
        if (params.max_memory) {
            try {
                def memory = params.max_memory instanceof String ? 
                    params.max_memory.toMemory() : params.max_memory
                if (memory.toBytes() <= 0) {
                    errors << "max_memory must be greater than 0, got: ${params.max_memory}"
                }
            } catch (Exception e) {
                errors << "Invalid memory format for max_memory: ${params.max_memory}"
            }
        }
        
        if (params.max_time) {
            try {
                def time = params.max_time instanceof String ? 
                    params.max_time.toDuration() : params.max_time
                if (time.toMillis() <= 0) {
                    errors << "max_time must be greater than 0, got: ${params.max_time}"
                }
            } catch (Exception e) {
                errors << "Invalid time format for max_time: ${params.max_time}"
            }
        }
        
        // Validate retry scaling parameters
        if (params.max_retry_scaling && params.max_retry_scaling < 1) {
            errors << "max_retry_scaling must be at least 1, got: ${params.max_retry_scaling}"
        }
        
        if (params.max_retry_scaling && params.max_retry_scaling > 10) {
            warnings << "max_retry_scaling is very high (${params.max_retry_scaling}), this may cause excessive resource usage"
        }
        
        return [errors: errors, warnings: warnings]
    }
    
    static def validateProfileConsistency(config) {
        def errors = []
        def warnings = []
        
        // Check if required process labels are defined
        def requiredLabels = [
            'process_low', 'process_medium', 'process_high', 
            'process_memory_intensive', 'process_quick'
        ]
        
        requiredLabels.each { label ->
            if (!hasProcessLabel(config, label)) {
                errors << "Missing required process label configuration: ${label}"
            }
        }
        
        // Validate resource scaling logic
        def processConfig = config.process
        if (processConfig) {
            requiredLabels.each { label ->
                def labelConfig = getProcessLabelConfig(processConfig, label)
                if (labelConfig) {
                    validateLabelResourceScaling(label, labelConfig, errors, warnings)
                }
            }
        }
        
        return [errors: errors, warnings: warnings]
    }
    
    static def validateExecutorConfiguration(config, executor) {
        def errors = []
        def warnings = []
        
        switch (executor) {
            case 'slurm':
                validateSlurmConfiguration(config, errors, warnings)
                break
            case 'local':
                validateLocalConfiguration(config, errors, warnings)
                break
            case 'sge':
                validateSgeConfiguration(config, errors, warnings)
                break
            default:
                warnings << "Unknown executor '${executor}', skipping executor-specific validation"
        }
        
        return [errors: errors, warnings: warnings]
    }
    
    static def validateDatabasePaths(params) {
        def errors = []
        def warnings = []
        
        // Required databases
        def requiredDbs = [
            'kraken2_db': params.kraken2_db,
            'checkv_db': params.checkv_db
        ]
        
        requiredDbs.each { name, path ->
            if (!path) {
                errors << "Required database path not specified: ${name}"
            } else if (!new File(path).exists()) {
                errors << "Database path does not exist: ${name} = ${path}"
            }
        }
        
        // Optional BLAST databases
        def blastDbs = [
            'blastdb_viruses': params.blastdb_viruses,
            'blastdb_nt': params.blastdb_nt,
            'blastdb_nr': params.blastdb_nr,
            'diamonddb': params.diamonddb
        ]
        
        blastDbs.each { name, path ->
            if (path && !new File(path).exists()) {
                warnings << "Optional database path does not exist: ${name} = ${path}"
            }
        }
        
        return [errors: errors, warnings: warnings]
    }
    
    static def validatePartitionConfiguration(params) {
        def errors = []
        def warnings = []
        
        // Validate partition mapping
        if (!params.partitions) {
            errors << "Partition mapping not configured"
            return [errors: errors, warnings: warnings]
        }
        
        // Check required partition types
        def requiredPartitionTypes = ['compute', 'bigmem', 'gpu', 'quick']
        requiredPartitionTypes.each { type ->
            if (!params.partitions.containsKey(type)) {
                warnings << "Partition type '${type}' not configured, some features may not work optimally"
            }
        }
        
        // Validate default partition
        if (!params.default_partition) {
            errors << "Default partition not specified"
        } else if (!params.partitions.values().contains(params.default_partition)) {
            warnings << "Default partition '${params.default_partition}' not found in partition mapping"
        }
        
        // Validate partition selection strategy
        def validStrategies = ['intelligent', 'static', 'user_defined']
        if (params.partition_selection_strategy && 
            !validStrategies.contains(params.partition_selection_strategy)) {
            errors << "Invalid partition selection strategy: ${params.partition_selection_strategy}. " +
                     "Valid options: ${validStrategies.join(', ')}"
        }
        
        // Validate partition thresholds
        if (params.partition_thresholds) {
            validatePartitionThresholds(params.partition_thresholds, errors, warnings)
        }
        
        // Validate partition fallbacks
        if (params.partition_fallbacks) {
            validatePartitionFallbacks(params.partition_fallbacks, params.partitions, errors, warnings)
        }
        
        return [errors: errors, warnings: warnings]
    }
    
    static def validateSlurmPartitionAvailability(params) {
        def errors = []
        def warnings = []
        
        if (!params.enable_partition_validation) {
            return [errors: errors, warnings: warnings]
        }
        
        // This would ideally check actual SLURM partition availability
        // For now, we'll do basic validation
        def configuredPartitions = params.partitions?.values() ?: []
        
        configuredPartitions.each { partition ->
            // In a real implementation, this could execute:
            // sinfo -h -p ${partition} -o "%P" 2>/dev/null
            // For now, we'll assume partitions are available if configured
            if (!partition || partition.trim().isEmpty()) {
                errors << "Empty partition name found in configuration"
            }
        }
        
        return [errors: errors, warnings: warnings]
    }
    
    static def validateCompleteConfiguration(params, config) {
        def allResults = [:]
        
        // Validate resource configuration
        allResults.resources = validateResourceConfiguration(params)
        
        // Validate profile consistency
        allResults.profiles = validateProfileConsistency(config)
        
        // Validate executor configuration
        if (params.resource_profile) {
            allResults.executor = validateExecutorConfiguration(config, params.resource_profile)
        }
        
        // Validate database paths
        allResults.databases = validateDatabasePaths(params)
        
        // Validate partition configuration (SLURM-specific)
        if (params.resource_profile == 'slurm' || config.process?.executor == 'slurm') {
            allResults.partitions = validatePartitionConfiguration(params)
            allResults.partition_availability = validateSlurmPartitionAvailability(params)
        }
        
        return allResults
    }
    
    static def generateValidationReport(allResults) {
        def report = []
        def totalErrors = 0
        def totalWarnings = 0
        
        report << "=== Configuration Validation Report ==="
        report << ""
        
        allResults.each { category, results ->
            if (results.errors || results.warnings) {
                report << "## ${category.toUpperCase()}"
                
                if (results.errors) {
                    report << "### Errors:"
                    results.errors.each { error ->
                        report << "  ❌ ${error}"
                        totalErrors++
                    }
                }
                
                if (results.warnings) {
                    report << "### Warnings:"
                    results.warnings.each { warning ->
                        report << "  ⚠️  ${warning}"
                        totalWarnings++
                    }
                }
                report << ""
            }
        }
        
        // Add partition selection test results if available
        if (allResults.partition_tests) {
            report << "## PARTITION SELECTION TESTS"
            allResults.partition_tests.testResults?.each { test ->
                def status = test.selected == test.expected ? "✅" : "❌"
                report << "  ${status} ${test.label}: ${test.selected} (expected: ${test.expected})"
            }
            report << ""
        }
        
        report << "=== Summary ==="
        report << "Total Errors: ${totalErrors}"
        report << "Total Warnings: ${totalWarnings}"
        
        if (totalErrors > 0) {
            report << ""
            report << "❌ Configuration validation FAILED. Please fix the errors above before proceeding."
        } else if (totalWarnings > 0) {
            report << ""
            report << "⚠️  Configuration validation passed with warnings. Review warnings above."
        } else {
            report << ""
            report << "✅ Configuration validation PASSED successfully."
        }
        
        return [
            report: report.join('\n'),
            hasErrors: totalErrors > 0,
            hasWarnings: totalWarnings > 0,
            errorCount: totalErrors,
            warningCount: totalWarnings
        ]
    }
    
    // Helper methods
    private static def hasProcessLabel(config, label) {
        return config.process && config.process.containsKey("withLabel:${label}")
    }
    
    private static def getProcessLabelConfig(processConfig, label) {
        return processConfig["withLabel:${label}"]
    }
    
    private static def validateLabelResourceScaling(label, labelConfig, errors, warnings) {
        // Check if resources scale with task.attempt
        ['cpus', 'memory', 'time'].each { resource ->
            def resourceConfig = labelConfig[resource]
            if (resourceConfig && resourceConfig instanceof Closure) {
                def configString = resourceConfig.toString()
                if (!configString.contains('task.attempt')) {
                    warnings << "Process label '${label}' ${resource} configuration does not scale with task.attempt"
                }
            }
        }
    }
    
    private static def validateSlurmConfiguration(config, errors, warnings) {
        def processConfig = config.process
        
        if (!processConfig?.queue && !processConfig?.clusterOptions?.contains('--partition')) {
            warnings << "No SLURM partition/queue specified, jobs may fail to submit"
        }
        
        if (processConfig?.memory) {
            def memoryConfig = processConfig.memory
            if (memoryConfig instanceof String && !memoryConfig.contains('GB') && !memoryConfig.contains('MB')) {
                warnings << "SLURM memory specification should include units (GB/MB)"
            }
        }
    }
    
    private static def validateLocalConfiguration(config, errors, warnings) {
        def processConfig = config.process
        
        if (processConfig?.cpus && processConfig.cpus > Runtime.runtime.availableProcessors()) {
            warnings << "Configured CPUs (${processConfig.cpus}) exceeds available processors (${Runtime.runtime.availableProcessors()})"
        }
        
        // Check for reasonable memory limits on local execution
        if (processConfig?.memory) {
            def memoryConfig = processConfig.memory
            if (memoryConfig instanceof String) {
                try {
                    def memory = memoryConfig.toMemory()
                    def maxMemoryGB = Runtime.runtime.maxMemory() / (1024 * 1024 * 1024)
                    if (memory.toGiga() > maxMemoryGB * 0.8) {
                        warnings << "Configured memory (${memoryConfig}) may exceed available system memory"
                    }
                } catch (Exception e) {
                    // Memory parsing handled elsewhere
                }
            }
        }
    }
    
    private static def validateSgeConfiguration(config, errors, warnings) {
        def processConfig = config.process
        
        if (!processConfig?.queue) {
            warnings << "No SGE queue specified, using default queue"
        }
        
        if (processConfig?.clusterOptions && !processConfig.clusterOptions.contains('-l')) {
            warnings << "SGE cluster options should typically include resource requests (-l)"
        }
    }
    
    private static def validatePartitionThresholds(thresholds, errors, warnings) {
        // Validate bigmem memory threshold
        if (thresholds.bigmem_memory_gb && thresholds.bigmem_memory_gb <= 0) {
            errors << "bigmem_memory_gb threshold must be greater than 0"
        }
        
        // Validate quick time threshold
        if (thresholds.quick_time_hours && thresholds.quick_time_hours <= 0) {
            errors << "quick_time_hours threshold must be greater than 0"
        }
        
        // Validate quick memory threshold
        if (thresholds.quick_memory_gb && thresholds.quick_memory_gb <= 0) {
            errors << "quick_memory_gb threshold must be greater than 0"
        }
        
        // Validate GPU labels
        if (thresholds.gpu_labels && !(thresholds.gpu_labels instanceof List)) {
            errors << "gpu_labels must be a list of label names"
        }
        
        // Check for reasonable threshold values
        if (thresholds.bigmem_memory_gb && thresholds.bigmem_memory_gb < 32) {
            warnings << "bigmem_memory_gb threshold (${thresholds.bigmem_memory_gb}GB) seems low for a bigmem partition"
        }
        
        if (thresholds.quick_time_hours && thresholds.quick_time_hours > 4) {
            warnings << "quick_time_hours threshold (${thresholds.quick_time_hours}h) seems high for a quick partition"
        }
    }
    
    private static def validatePartitionFallbacks(fallbacks, partitions, errors, warnings) {
        fallbacks.each { partition, fallbackList ->
            // Check if the partition exists in the partition mapping
            if (!partitions.values().contains(partition)) {
                warnings << "Fallback configuration references unknown partition: ${partition}"
            }
            
            // Check if fallback partitions exist
            if (fallbackList instanceof List) {
                fallbackList.each { fallback ->
                    if (!partitions.values().contains(fallback)) {
                        warnings << "Fallback partition '${fallback}' for '${partition}' not found in partition mapping"
                    }
                }
            } else {
                errors << "Fallback configuration for '${partition}' must be a list"
            }
            
            // Check for circular fallbacks
            if (fallbackList instanceof List && fallbackList.contains(partition)) {
                errors << "Circular fallback detected: partition '${partition}' cannot fallback to itself"
            }
        }
    }
}