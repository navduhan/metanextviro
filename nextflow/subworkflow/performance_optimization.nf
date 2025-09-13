/*
 * Performance Optimization Subworkflow
 * Integrates dynamic resource scaling, intelligent parallelization, and performance monitoring
 */

include { performance_monitor } from '../modules/performance_monitor.nf'
include { collect_performance_stats } from '../modules/performance_monitor.nf'
include { generate_optimization_report } from '../modules/performance_monitor.nf'

workflow PERFORMANCE_OPTIMIZATION {
    take:
        input_files
        process_results
        
    main:
        // Calculate input characteristics for optimization
        input_characteristics = calculateInputCharacteristics(input_files)
        
        // Monitor performance for each process
        if (params.enable_performance_monitoring) {
            // Create performance monitoring channels
            performance_data = Channel.empty()
            
            // Monitor each process result
            process_results.each { process_name, results ->
                if (results) {
                    monitored_results = performance_monitor(
                        results,
                        process_name,
                        workflow.start.toEpochMilli() / 1000
                    )
                    performance_data = performance_data.mix(monitored_results.performance_stats)
                }
            }
            
            // Collect all performance statistics
            performance_summary = collect_performance_stats(
                performance_data.collect()
            )
            
            // Generate optimization recommendations
            optimization_report = generate_optimization_report(
                performance_summary.summary,
                input_characteristics
            )
        } else {
            performance_summary = Channel.empty()
            optimization_report = Channel.empty()
        }
        
        // Apply dynamic resource scaling if enabled
        if (params.enable_dynamic_scaling) {
            optimized_resources = calculateOptimizedResources(
                input_characteristics,
                process_results
            )
        } else {
            optimized_resources = Channel.empty()
        }
        
        // Calculate intelligent parallelization settings
        if (params.enable_intelligent_parallelization) {
            parallelization_config = calculateOptimalParallelization(
                input_characteristics
            )
        } else {
            parallelization_config = Channel.empty()
        }
        
    emit:
        performance_summary = performance_summary.summary
        optimization_report = optimization_report.report
        optimized_resources = optimized_resources
        parallelization_config = parallelization_config
        input_characteristics = input_characteristics
}

workflow DYNAMIC_RESOURCE_SCALING {
    take:
        input_files
        process_label
        base_resources
        
    main:
        // Calculate optimal resources based on input characteristics
        input_size = calculateTotalInputSize(input_files)
        sample_count = getSampleCount(input_files)
        
        // Use PerformanceOptimizer to calculate optimal resources
        optimal_resources = Channel.of([
            cpus: calculateOptimalCpus(input_size, sample_count, process_label, base_resources.cpus),
            memory: calculateOptimalMemory(input_size, sample_count, process_label, base_resources.memory),
            time: calculateOptimalTime(input_size, sample_count, process_label, base_resources.time)
        ])
        
        // Add performance hints
        performance_hints = generatePerformanceHints(
            input_size, sample_count, process_label, optimal_resources
        )
        
    emit:
        resources = optimal_resources
        hints = performance_hints
}

workflow INTELLIGENT_PARALLELIZATION {
    take:
        input_files
        process_label
        max_forks
        
    main:
        // Calculate optimal parallelization strategy
        sample_count = getSampleCount(input_files)
        total_size = calculateTotalInputSize(input_files)
        
        parallelization_strategy = Channel.of([
            optimal_forks: calculateOptimalForks(sample_count, process_label, max_forks),
            batch_size: calculateOptimalBatchSize(sample_count, process_label),
            strategy: determineParallelizationStrategy(process_label, total_size, sample_count)
        ])
        
    emit:
        strategy = parallelization_strategy
}

workflow PERFORMANCE_PROFILING {
    take:
        process_results
        resource_usage
        
    main:
        // Analyze performance bottlenecks
        bottleneck_analysis = analyzePerformanceBottlenecks(process_results, resource_usage)
        
        // Generate optimization recommendations
        optimization_recommendations = generateOptimizationRecommendations(
            process_results, resource_usage
        )
        
        // Create performance profile
        performance_profile = createPerformanceProfile(
            process_results, resource_usage
        )
        
    emit:
        bottlenecks = bottleneck_analysis
        recommendations = optimization_recommendations
        profile = performance_profile
}

// Helper functions
def calculateInputCharacteristics(input_files) {
    def characteristics = [:]
    
    if (input_files instanceof List) {
        def totalSize = 0
        def fileCount = input_files.size()
        
        input_files.each { file ->
            if (file instanceof File && file.exists()) {
                totalSize += file.length()
            } else if (file instanceof String) {
                def f = new File(file)
                if (f.exists()) {
                    totalSize += f.length()
                }
            }
        }
        
        characteristics = [
            totalSize: totalSize,
            sampleCount: fileCount,
            avgSampleSize: fileCount > 0 ? totalSize / fileCount : 0,
            sizeCategory: categorizeInputSize(totalSize),
            dataType: determineDataType(input_files)
        ]
    } else {
        characteristics = [
            totalSize: 0,
            sampleCount: 1,
            avgSampleSize: 0,
            sizeCategory: 'small',
            dataType: 'unknown'
        ]
    }
    
    return characteristics
}

def calculateTotalInputSize(input_files) {
    def totalSize = 0
    
    if (input_files instanceof List) {
        input_files.each { file ->
            if (file instanceof File && file.exists()) {
                totalSize += file.length()
            } else if (file instanceof String) {
                def f = new File(file)
                if (f.exists()) {
                    totalSize += f.length()
                }
            }
        }
    } else if (input_files instanceof File && input_files.exists()) {
        totalSize = input_files.length()
    }
    
    return totalSize
}

def getSampleCount(input_files) {
    if (input_files instanceof List) {
        return input_files.size()
    } else {
        return 1
    }
}

def calculateOptimalCpus(inputSize, sampleCount, processLabel, baseCpus) {
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    def baseCpuCount = baseCpus ?: 2
    
    // Size-based scaling
    def sizeScaling = 1.0
    if (sizeGB > 50) {
        sizeScaling = Math.min(2.0, 1.0 + (sizeGB - 50) / 100)
    }
    
    // Process-specific scaling
    def processScaling = getProcessScalingFactor(processLabel, 'cpu')
    
    def optimalCpus = Math.ceil(baseCpuCount * processScaling * sizeScaling)
    
    // Apply reasonable limits
    return Math.min(Math.max(1, optimalCpus), 32)
}

def calculateOptimalMemory(inputSize, sampleCount, processLabel, baseMemory) {
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    def baseMemoryGB = baseMemory ? parseMemoryToGB(baseMemory) : 4
    
    // Size-based memory scaling
    def memoryScaling = 1.0
    
    switch (processLabel) {
        case 'process_memory_intensive':
            memoryScaling = Math.max(2.0, sizeGB * 0.5)
            break
        case 'process_high':
            memoryScaling = Math.max(1.5, sizeGB * 0.2)
            break
        case 'process_medium':
            memoryScaling = Math.max(1.2, sizeGB * 0.1)
            break
        default:
            memoryScaling = Math.max(1.0, sizeGB * 0.05)
    }
    
    def processScaling = getProcessScalingFactor(processLabel, 'memory')
    def optimalMemoryGB = baseMemoryGB * processScaling * memoryScaling
    
    // Apply reasonable limits
    optimalMemoryGB = Math.min(Math.max(2, optimalMemoryGB), 1000)
    
    return "${Math.ceil(optimalMemoryGB)}.GB"
}

def calculateOptimalTime(inputSize, sampleCount, processLabel, baseTime) {
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    def baseTimeHours = baseTime ? parseTimeToHours(baseTime) : 2
    
    // Size-based time scaling
    def timeScaling = 1.0
    if (sizeGB > 10) {
        timeScaling = Math.max(1.5, Math.log(sizeGB / 10) + 1)
    }
    
    def processScaling = getProcessScalingFactor(processLabel, 'time')
    def optimalTimeHours = baseTimeHours * processScaling * timeScaling
    
    // Apply reasonable limits
    optimalTimeHours = Math.min(Math.max(0.5, optimalTimeHours), 72)
    
    return "${Math.ceil(optimalTimeHours)}.h"
}

def calculateOptimalForks(sampleCount, processLabel, maxForks) {
    def optimalForks = maxForks
    
    switch (processLabel) {
        case 'process_low':
        case 'process_quick':
            optimalForks = Math.min(sampleCount, maxForks)
            break
        case 'process_memory_intensive':
            optimalForks = Math.min(Math.max(1, maxForks / 4), sampleCount)
            break
        case 'process_high':
            optimalForks = Math.min(Math.max(2, maxForks / 2), sampleCount)
            break
        case 'process_gpu':
            optimalForks = 1
            break
        default:
            optimalForks = Math.min(Math.max(2, maxForks / 2), sampleCount)
    }
    
    return optimalForks
}

def calculateOptimalBatchSize(sampleCount, processLabel) {
    def batchSize = 1
    
    if (sampleCount > 10) {
        switch (processLabel) {
            case 'process_memory_intensive':
                batchSize = Math.min(2, sampleCount / 5)
                break
            case 'process_quick':
                batchSize = Math.min(10, sampleCount / 2)
                break
            default:
                batchSize = Math.min(5, sampleCount / 3)
        }
    }
    
    return Math.max(1, batchSize)
}

def determineParallelizationStrategy(processLabel, totalSize, sampleCount) {
    def sizeGB = totalSize / (1024 * 1024 * 1024)
    
    if (processLabel == 'process_gpu') {
        return 'gpu_exclusive'
    } else if (processLabel == 'process_memory_intensive') {
        return 'memory_conservative'
    } else if (sizeGB > 100) {
        return 'io_optimized'
    } else if (sampleCount > 20) {
        return 'high_parallelization'
    } else {
        return 'balanced'
    }
}

def categorizeInputSize(totalSize) {
    def sizeGB = totalSize / (1024 * 1024 * 1024)
    
    if (sizeGB < 1) return 'small'
    else if (sizeGB < 10) return 'medium'
    else if (sizeGB < 100) return 'large'
    else return 'very_large'
}

def determineDataType(input_files) {
    if (input_files instanceof List && input_files.size() > 0) {
        def firstFile = input_files[0]
        def fileName = firstFile instanceof File ? firstFile.name : firstFile.toString()
        
        if (fileName.endsWith('.fastq.gz') || fileName.endsWith('.fq.gz')) {
            return 'fastq'
        } else if (fileName.endsWith('.fasta') || fileName.endsWith('.fa')) {
            return 'fasta'
        } else {
            return 'unknown'
        }
    }
    return 'unknown'
}

def getProcessScalingFactor(processLabel, resourceType) {
    def scalingFactors = [
        'process_low': [cpu: 1.0, memory: 1.0, time: 1.0],
        'process_medium': [cpu: 1.2, memory: 1.2, time: 1.2],
        'process_high': [cpu: 1.5, memory: 1.5, time: 1.5],
        'process_memory_intensive': [cpu: 1.2, memory: 2.5, time: 2.0],
        'process_gpu': [cpu: 1.3, memory: 1.8, time: 0.7],
        'process_quick': [cpu: 0.8, memory: 0.8, time: 0.5]
    ]
    
    return scalingFactors[processLabel]?[resourceType] ?: 1.0
}

def generatePerformanceHints(inputSize, sampleCount, processLabel, resources) {
    def hints = []
    def sizeGB = inputSize / (1024 * 1024 * 1024)
    
    if (sizeGB > 100) {
        hints << "Large input detected (${Math.round(sizeGB)}GB). Consider using SSD storage for better I/O performance."
    }
    
    if (sampleCount > 20) {
        hints << "Multiple samples detected (${sampleCount}). Enable parallel processing for better throughput."
    }
    
    if (processLabel == 'process_memory_intensive') {
        hints << "Memory-intensive process detected. Consider using bigmem partition or nodes with sufficient RAM."
    }
    
    if (processLabel == 'process_gpu') {
        hints << "GPU-accelerated process. Ensure GPU nodes are available and properly configured."
    }
    
    return hints
}

def analyzePerformanceBottlenecks(processResults, resourceUsage) {
    def bottlenecks = []
    def recommendations = []
    
    processResults.each { processName, result ->
        def usage = resourceUsage[processName]
        if (usage) {
            // Memory bottleneck detection
            if (usage.memoryUtilization > 0.95) {
                bottlenecks << [process: processName, type: 'memory', severity: 'high']
                recommendations << [process: processName, action: 'increase_memory', priority: 3]
            }
            
            // CPU bottleneck detection
            if (usage.cpuUtilization < 0.3) {
                bottlenecks << [process: processName, type: 'cpu_underutilization', severity: 'medium']
                recommendations << [process: processName, action: 'reduce_cpu_allocation', priority: 2]
            }
            
            // Time bottleneck detection
            if (usage.timeUtilization > 0.9) {
                bottlenecks << [process: processName, type: 'time', severity: 'high']
                recommendations << [process: processName, action: 'increase_time_limit', priority: 3]
            }
        }
    }
    
    return [bottlenecks: bottlenecks, recommendations: recommendations]
}

def generateOptimizationRecommendations(processResults, resourceUsage) {
    def recommendations = []
    
    // Analyze resource utilization patterns
    resourceUsage.each { processName, usage ->
        if (usage.memoryUtilization > 0.9) {
            recommendations << [
                type: 'memory',
                process: processName,
                description: "Increase memory allocation",
                priority: 3,
                estimatedImprovement: "20-30% performance gain"
            ]
        }
        
        if (usage.cpuUtilization < 0.4) {
            recommendations << [
                type: 'cpu',
                process: processName,
                description: "Reduce CPU allocation or increase parallelization",
                priority: 2,
                estimatedImprovement: "10-15% resource efficiency"
            ]
        }
    }
    
    return recommendations
}

def createPerformanceProfile(processResults, resourceUsage) {
    def profile = [:]
    
    // Calculate overall pipeline efficiency
    def totalProcesses = processResults.size()
    def avgMemoryUtilization = resourceUsage.values().collect { it.memoryUtilization }.sum() / totalProcesses
    def avgCpuUtilization = resourceUsage.values().collect { it.cpuUtilization }.sum() / totalProcesses
    
    profile.efficiency = [
        memory: avgMemoryUtilization,
        cpu: avgCpuUtilization,
        overall: (avgMemoryUtilization + avgCpuUtilization) / 2
    ]
    
    // Identify performance characteristics
    profile.characteristics = [
        memoryIntensive: avgMemoryUtilization > 0.8,
        cpuIntensive: avgCpuUtilization > 0.8,
        ioIntensive: resourceUsage.values().any { it.ioWait > 0.3 }
    ]
    
    return profile
}

// Utility functions
def parseMemoryToGB(memory) {
    if (!memory) return 0
    if (memory instanceof String) {
        return memory.toMemory().toGiga()
    }
    return memory.toGiga()
}

def parseTimeToHours(time) {
    if (!time) return 0
    if (time instanceof String) {
        return time.toDuration().toHours()
    }
    return time.toHours()
}

def calculateOptimizedResources(inputCharacteristics, processResults) {
    def optimizedResources = [:]
    
    processResults.each { processName, results ->
        def processLabel = extractProcessLabel(processName)
        def baseResources = getBaseResources(processLabel)
        
        optimizedResources[processName] = [
            cpus: calculateOptimalCpus(
                inputCharacteristics.totalSize,
                inputCharacteristics.sampleCount,
                processLabel,
                baseResources.cpus
            ),
            memory: calculateOptimalMemory(
                inputCharacteristics.totalSize,
                inputCharacteristics.sampleCount,
                processLabel,
                baseResources.memory
            ),
            time: calculateOptimalTime(
                inputCharacteristics.totalSize,
                inputCharacteristics.sampleCount,
                processLabel,
                baseResources.time
            )
        ]
    }
    
    return optimizedResources
}

def calculateOptimalParallelization(inputCharacteristics) {
    def parallelizationConfig = [:]
    
    def sampleCount = inputCharacteristics.sampleCount
    def totalSize = inputCharacteristics.totalSize
    
    // Calculate optimal fork settings for different process types
    ['process_low', 'process_medium', 'process_high', 'process_memory_intensive', 'process_gpu', 'process_quick'].each { processLabel ->
        parallelizationConfig[processLabel] = [
            optimalForks: calculateOptimalForks(sampleCount, processLabel, params.max_forks ?: 10),
            batchSize: calculateOptimalBatchSize(sampleCount, processLabel),
            strategy: determineParallelizationStrategy(processLabel, totalSize, sampleCount)
        ]
    }
    
    return parallelizationConfig
}

def extractProcessLabel(processName) {
    // Extract process label from process name
    if (processName.contains('memory_intensive')) return 'process_memory_intensive'
    else if (processName.contains('gpu')) return 'process_gpu'
    else if (processName.contains('high')) return 'process_high'
    else if (processName.contains('medium')) return 'process_medium'
    else if (processName.contains('quick')) return 'process_quick'
    else return 'process_low'
}

def getBaseResources(processLabel) {
    def baseResources = [
        'process_low': [cpus: 2, memory: '4.GB', time: '2.h'],
        'process_medium': [cpus: 4, memory: '8.GB', time: '4.h'],
        'process_high': [cpus: 8, memory: '16.GB', time: '8.h'],
        'process_memory_intensive': [cpus: 4, memory: '32.GB', time: '12.h'],
        'process_gpu': [cpus: 4, memory: '16.GB', time: '8.h'],
        'process_quick': [cpus: 1, memory: '2.GB', time: '30.m']
    ]
    
    return baseResources[processLabel] ?: baseResources['process_low']
}