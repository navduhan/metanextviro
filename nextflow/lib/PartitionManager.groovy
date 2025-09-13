/*
 * SLURM Partition Management Library
 * Provides utilities for intelligent partition selection and management
 */

class PartitionManager {
    
    static def selectOptimalPartition(params, processLabel, memory, time, cpus = null) {
        def memoryGB = parseMemoryToGB(memory)
        def timeHours = parseTimeToHours(time)
        
        // Get configuration
        def strategy = params.partition_selection_strategy ?: 'intelligent'
        def thresholds = params.partition_thresholds ?: [:]
        def partitions = params.partitions ?: [:]
        
        def selectedPartition = null
        
        switch (strategy) {
            case 'intelligent':
                selectedPartition = selectIntelligentPartition(
                    processLabel, memoryGB, timeHours, cpus, thresholds, partitions
                )
                break
            case 'static':
                selectedPartition = partitions.compute ?: params.default_partition
                break
            case 'user_defined':
                selectedPartition = selectUserDefinedPartition(processLabel, params)
                break
            default:
                selectedPartition = selectIntelligentPartition(
                    processLabel, memoryGB, timeHours, cpus, thresholds, partitions
                )
        }
        
        // Apply fallback logic
        return applyFallbackLogic(selectedPartition, params)
    }
    
    static def selectIntelligentPartition(processLabel, memoryGB, timeHours, cpus, thresholds, partitions) {
        // Get thresholds with defaults
        def bigmemThreshold = thresholds.bigmem_memory_gb ?: 128
        def quickTimeThreshold = thresholds.quick_time_hours ?: 1
        def quickMemoryThreshold = thresholds.quick_memory_gb ?: 16
        def gpuLabels = thresholds.gpu_labels ?: ['process_gpu']
        
        // Priority 1: GPU processes
        if (isGpuProcess(processLabel, gpuLabels)) {
            return partitions.gpu ?: partitions.compute
        }
        
        // Priority 2: Memory-intensive processes
        if (isMemoryIntensive(processLabel, memoryGB, bigmemThreshold)) {
            return partitions.bigmem ?: partitions.compute
        }
        
        // Priority 3: Quick processes
        if (isQuickProcess(processLabel, timeHours, memoryGB, quickTimeThreshold, quickMemoryThreshold)) {
            return partitions.quick ?: partitions.compute
        }
        
        // Priority 4: High-performance processes
        if (isHighPerformanceProcess(processLabel, cpus, memoryGB, bigmemThreshold)) {
            return partitions.compute
        }
        
        // Default: compute partition
        return partitions.compute ?: 'compute'
    }
    
    static def selectUserDefinedPartition(processLabel, params) {
        def customMapping = params.custom_partition_mapping ?: [:]
        return customMapping[processLabel] ?: params.partitions?.compute ?: params.default_partition
    }
    
    static def applyFallbackLogic(selectedPartition, params) {
        if (!params.enable_partition_validation) {
            return selectedPartition
        }
        
        def fallbacks = params.partition_fallbacks ?: [:]
        def availablePartitions = getAvailablePartitions(params)
        
        // Check if selected partition is available
        if (availablePartitions.contains(selectedPartition)) {
            return selectedPartition
        }
        
        // Try fallback partitions
        def partitionFallbacks = fallbacks[selectedPartition] ?: []
        for (fallback in partitionFallbacks) {
            if (availablePartitions.contains(fallback)) {
                return fallback
            }
        }
        
        // Final fallback to default
        return params.default_partition ?: 'compute'
    }
    
    static def generateClusterOptions(processLabel, partition, memory, cpus, params) {
        def options = []
        
        // Basic resource specifications
        if (memory) {
            def memoryMB = parseMemoryToMB(memory)
            options << "--mem=${memoryMB}M"
        }
        
        if (cpus) {
            options << "--ntasks=1"
            options << "--cpus-per-task=${cpus}"
        }
        
        // Partition-specific options
        options.addAll(getPartitionOptions(partition, processLabel, memory, cpus, params))
        
        // Label-specific options
        options.addAll(getLabelOptions(processLabel, params))
        
        // Custom options
        if (params.custom_cluster_options) {
            options.addAll(params.custom_cluster_options)
        }
        
        return options.join(' ')
    }
    
    static def getPartitionOptions(partition, processLabel, memory, cpus, params) {
        def options = []
        def partitions = params.partitions ?: [:]
        
        switch (partition) {
            case partitions.bigmem:
                options << '--constraint=bigmem'
                if (memory && parseMemoryToGB(memory) > 256) {
                    options << '--exclusive'
                }
                break
                
            case partitions.gpu:
                options << '--gres=gpu:1'
                options << '--constraint=gpu'
                if (params.gpu_type) {
                    options[options.size()-1] = "--gres=gpu:${params.gpu_type}:1"
                }
                break
                
            case partitions.quick:
                options << '--qos=quick'
                options << '--nice=100'
                break
                
            case partitions.compute:
                if (cpus && cpus >= 16) {
                    options << '--constraint=compute'
                }
                break
        }
        
        return options
    }
    
    static def getLabelOptions(processLabel, params) {
        def options = []
        
        switch (processLabel) {
            case 'process_memory_intensive':
                options << '--mem-per-cpu=8G'
                break
                
            case 'process_gpu':
                options << '--gres=gpu:1'
                if (params.gpu_memory_required) {
                    options << "--constraint=gpu_mem_${params.gpu_memory_required}"
                }
                break
                
            case 'process_quick':
                options << '--nice=100'
                options << '--no-requeue'
                break
                
            case 'process_high':
                options << '--exclusive'
                break
                
            case 'process_low':
                options << '--share'
                break
        }
        
        return options
    }
    
    static def validatePartitionSelection(params) {
        def results = [:]
        def errors = []
        def warnings = []
        
        // Test partition selection for different scenarios
        def testCases = [
            [label: 'process_low', memory: '4.GB', time: '1.h', expected: 'quick'],
            [label: 'process_medium', memory: '16.GB', time: '4.h', expected: 'compute'],
            [label: 'process_high', memory: '32.GB', time: '8.h', expected: 'compute'],
            [label: 'process_memory_intensive', memory: '256.GB', time: '12.h', expected: 'bigmem'],
            [label: 'process_gpu', memory: '32.GB', time: '8.h', expected: 'gpu'],
            [label: 'process_quick', memory: '8.GB', time: '30.m', expected: 'quick']
        ]
        
        testCases.each { testCase ->
            def selected = selectOptimalPartition(
                params, testCase.label, testCase.memory, testCase.time
            )
            def expectedPartition = params.partitions[testCase.expected] ?: testCase.expected
            
            if (selected != expectedPartition) {
                warnings << "Unexpected partition selection for ${testCase.label}: " +
                           "got '${selected}', expected '${expectedPartition}'"
            }
        }
        
        results.errors = errors
        results.warnings = warnings
        results.testResults = testCases.collect { testCase ->
            [
                label: testCase.label,
                selected: selectOptimalPartition(params, testCase.label, testCase.memory, testCase.time),
                expected: params.partitions[testCase.expected] ?: testCase.expected
            ]
        }
        
        return results
    }
    
    // Helper methods
    private static def parseMemoryToGB(memory) {
        if (!memory) return 0
        if (memory instanceof String) {
            return memory.toMemory().toGiga()
        }
        return memory.toGiga()
    }
    
    private static def parseMemoryToMB(memory) {
        if (!memory) return 0
        if (memory instanceof String) {
            return memory.toMemory().toMega()
        }
        return memory.toMega()
    }
    
    private static def parseTimeToHours(time) {
        if (!time) return 0
        if (time instanceof String) {
            return time.toDuration().toHours()
        }
        return time.toHours()
    }
    
    private static def isGpuProcess(processLabel, gpuLabels) {
        return gpuLabels.any { processLabel?.contains(it.replace('process_', '')) } || 
               processLabel?.contains('gpu')
    }
    
    private static def isMemoryIntensive(processLabel, memoryGB, threshold) {
        return processLabel?.contains('memory_intensive') || memoryGB > threshold
    }
    
    private static def isQuickProcess(processLabel, timeHours, memoryGB, timeThreshold, memoryThreshold) {
        return processLabel?.contains('quick') || 
               (timeHours > 0 && timeHours <= timeThreshold && memoryGB <= memoryThreshold)
    }
    
    private static def isHighPerformanceProcess(processLabel, cpus, memoryGB, bigmemThreshold) {
        return processLabel?.contains('high') && memoryGB <= bigmemThreshold
    }
    
    private static def getAvailablePartitions(params) {
        // In a real implementation, this could check SLURM partition availability
        // For now, return all configured partitions
        def configuredPartitions = params.partitions?.values() ?: []
        configuredPartitions << params.default_partition
        return configuredPartitions.unique().findAll { it != null }
    }
}