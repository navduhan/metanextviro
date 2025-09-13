/*
 * Performance Optimization Library
 * Provides dynamic resource scaling, intelligent parallelization, and performance monitoring
 */

class PerformanceOptimizer {
    
    static def calculateOptimalResources(inputFiles, processLabel, baseResources = [:]) {
        def totalSize = calculateTotalInputSize(inputFiles)
        def sampleCount = getSampleCount(inputFiles)
        
        def optimizedResources = [:]
        
        // Base resource scaling factors based on process type
        def scalingFactors = getProcessScalingFactors(processLabel)
        
        // Calculate CPU requirements
        optimizedResources.cpus = calculateOptimalCpus(
            totalSize, sampleCount, processLabel, scalingFactors, baseResources.cpus
        )
        
        // Calculate memory requirements
        optimizedResources.memory = calculateOptimalMemory(
            totalSize, sampleCount, processLabel, scalingFactors, baseResources.memory
        )
        
        // Calculate time requirements
        optimizedResources.time = calculateOptimalTime(
            totalSize, sampleCount, processLabel, scalingFactors, baseResources.time
        )
        
        // Add performance hints
        optimizedResources.performanceHints = generatePerformanceHints(
            totalSize, sampleCount, processLabel, optimizedResources
        )
        
        return optimizedResources
    }
    
    static def calculateOptimalParallelization(inputFiles, processLabel, maxForks = 10) {
        def sampleCount = getSampleCount(inputFiles)
        def totalSize = calculateTotalInputSize(inputFiles)
        def avgSampleSize = sampleCount > 0 ? totalSize / sampleCount : 0
        
        def parallelization = [:]
        
        // Determine optimal fork count based on process characteristics
        switch (processLabel) {
            case 'process_low':
            case 'process_quick':
                // I/O bound processes can handle more parallelization
                parallelization.optimalForks = Math.min(sampleCount, maxForks)
                parallelization.strategy = 'high_parallelization'
                break
                
            case 'process_memory_intensive':
                // Memory-intensive processes need limited parallelization
                parallelization.optimalForks = Math.min(Math.max(1, maxForks / 4), sampleCount)
                parallelization.strategy = 'memory_conservative'
                break
                
            case 'process_high':
                // CPU-intensive processes need balanced parallelization
                parallelization.optimalForks = Math.min(Math.max(2, maxForks / 2), sampleCount)
                parallelization.strategy = 'cpu_balanced'
                break
                
            case 'process_gpu':
                // GPU processes typically run one at a time per GPU
                parallelization.optimalForks = 1
                parallelization.strategy = 'gpu_exclusive'
                break
                
            default:
                parallelization.optimalForks = Math.min(Math.max(2, maxForks / 2), sampleCount)
                parallelization.strategy = 'balanced'
        }
        
        // Adjust based on sample size
        if (avgSampleSize > 10 * 1024 * 1024 * 1024) { // > 10GB per sample
            parallelization.optimalForks = Math.max(1, parallelization.optimalForks / 2)
            parallelization.sizeAdjustment = 'large_samples_detected'
        }
        
        // Calculate batch size for efficient processing
        parallelization.batchSize = calculateOptimalBatchSize(
            sampleCount, parallelization.optimalForks, processLabel
        )
        
        return parallelization
    }
    
    static def generateResourceMonitoringConfig(processLabel, resources) {
        def monitoring = [:]
        
        // Define monitoring thresholds based on allocated resources
        monitoring.memoryThreshold = resources.memory ? 
            (parseMemoryToGB(resources.memory) * 0.9) : 32
        monitoring.cpuThreshold = resources.cpus ? (resources.cpus * 0.8) : 4
        monitoring.timeThreshold = resources.time ? 
            (parseTimeToHours(resources.time) * 0.9) : 2
        
        // Process-specific monitoring
        switch (processLabel) {
            case 'process_memory_intensive':
                monitoring.memoryAlert = true
                monitoring.swapMonitoring = true
                monitoring.memoryLeakDetection = true
                break
                
            case 'process_gpu':
                monitoring.gpuUtilization = true
                monitoring.gpuMemoryUsage = true
                monitoring.gpuTemperature = true
                break
                
            case 'process_high':
                monitoring.cpuUtilization = true
                monitoring.loadAverage = true
                monitoring.ioWait = true
                break
                
            case 'process_quick':
                monitoring.executionTime = true
                monitoring.queueTime = true
                break
        }
        
        // Generate monitoring commands
        monitoring.commands = generateMonitoringCommands(monitoring)
        
        return monitoring
    }
    
    static def analyzePerformanceBottlenecks(processResults, resourceUsage) {
        def bottlenecks = []
        def recommendations = []
        
        processResults.each { processName, result ->
            def analysis = analyzeProcessPerformance(processName, result, resourceUsage[processName])
            
            if (analysis.bottlenecks) {
                bottlenecks.addAll(analysis.bottlenecks.collect { 
                    [process: processName, bottleneck: it] 
                })
            }
            
            if (analysis.recommendations) {
                recommendations.addAll(analysis.recommendations.collect { 
                    [process: processName, recommendation: it] 
                })
            }
        }
        
        return [
            bottlenecks: bottlenecks,
            recommendations: recommendations,
            summary: generateBottleneckSummary(bottlenecks, recommendations)
        ]
    }
    
    static def generateOptimizationRecommendations(pipelineStats, resourceUsage) {
        def recommendations = []
        
        // Analyze overall pipeline performance
        def pipelineAnalysis = analyzePipelinePerformance(pipelineStats)
        
        // Resource utilization recommendations
        recommendations.addAll(generateResourceRecommendations(resourceUsage))
        
        // Parallelization recommendations
        recommendations.addAll(generateParallelizationRecommendations(pipelineStats))
        
        // Configuration recommendations
        recommendations.addAll(generateConfigurationRecommendations(pipelineStats, resourceUsage))
        
        // Priority-based sorting
        recommendations = recommendations.sort { -it.priority }
        
        return [
            recommendations: recommendations,
            summary: generateRecommendationSummary(recommendations),
            estimatedImprovement: calculateEstimatedImprovement(recommendations, pipelineStats)
        ]
    }
    
    static def createPerformanceProfile(inputCharacteristics, systemCapabilities) {
        def profile = [:]
        
        // Input characteristics
        profile.inputSize = inputCharacteristics.totalSize
        profile.sampleCount = inputCharacteristics.sampleCount
        profile.avgSampleSize = inputCharacteristics.avgSampleSize
        profile.dataType = inputCharacteristics.dataType
        
        // System capabilities
        profile.maxCpus = systemCapabilities.maxCpus
        profile.maxMemory = systemCapabilities.maxMemory
        profile.storageType = systemCapabilities.storageType
        profile.networkBandwidth = systemCapabilities.networkBandwidth
        
        // Generate optimal configuration
        profile.optimalConfiguration = generateOptimalConfiguration(
            inputCharacteristics, systemCapabilities
        )
        
        return profile
    }
    
    // Helper methods for resource calculations
    private static def calculateTotalInputSize(inputFiles) {
        def totalSize = 0
        
        if (inputFiles instanceof List) {
            inputFiles.each { file ->
                if (file instanceof File) {
                    totalSize += file.length()
                } else if (file instanceof String) {
                    def f = new File(file)
                    if (f.exists()) {
                        totalSize += f.length()
                    }
                }
            }
        } else if (inputFiles instanceof File) {
            totalSize = inputFiles.length()
        } else if (inputFiles instanceof String) {
            def f = new File(inputFiles)
            if (f.exists()) {
                totalSize = f.length()
            }
        }
        
        return totalSize
    }
    
    private static def getSampleCount(inputFiles) {
        if (inputFiles instanceof List) {
            return inputFiles.size()
        } else {
            return 1
        }
    }
    
    private static def getProcessScalingFactors(processLabel) {
        def factors = [:]
        
        switch (processLabel) {
            case 'process_low':
                factors = [cpu: 1.0, memory: 1.0, time: 1.0, io: 2.0]
                break
            case 'process_medium':
                factors = [cpu: 1.5, memory: 1.2, time: 1.2, io: 1.5]
                break
            case 'process_high':
                factors = [cpu: 2.0, memory: 1.5, time: 1.5, io: 1.0]
                break
            case 'process_memory_intensive':
                factors = [cpu: 1.2, memory: 3.0, time: 2.0, io: 0.8]
                break
            case 'process_gpu':
                factors = [cpu: 1.5, memory: 2.0, time: 0.5, io: 1.0]
                break
            case 'process_quick':
                factors = [cpu: 0.8, memory: 0.8, time: 0.5, io: 1.5]
                break
            default:
                factors = [cpu: 1.0, memory: 1.0, time: 1.0, io: 1.0]
        }
        
        return factors
    }
    
    private static def calculateOptimalCpus(totalSize, sampleCount, processLabel, factors, baseCpus) {
        def sizeGB = totalSize / (1024 * 1024 * 1024)
        def baseCpuCount = baseCpus ?: 2
        
        // Size-based scaling
        def sizeScaling = 1.0
        if (sizeGB > 50) {
            sizeScaling = Math.min(2.0, 1.0 + (sizeGB - 50) / 100)
        }
        
        // Sample count scaling for parallelizable processes
        def sampleScaling = 1.0
        if (sampleCount > 1 && processLabel in ['process_low', 'process_medium']) {
            sampleScaling = Math.min(1.5, 1.0 + (sampleCount - 1) / 10)
        }
        
        def optimalCpus = Math.ceil(baseCpuCount * factors.cpu * sizeScaling * sampleScaling)
        
        // Apply reasonable limits
        return Math.min(Math.max(1, optimalCpus), 32)
    }
    
    private static def calculateOptimalMemory(totalSize, sampleCount, processLabel, factors, baseMemory) {
        def sizeGB = totalSize / (1024 * 1024 * 1024)
        def baseMemoryGB = baseMemory ? parseMemoryToGB(baseMemory) : 4
        
        // Size-based memory scaling
        def memoryScaling = 1.0
        
        switch (processLabel) {
            case 'process_memory_intensive':
                // Assembly and memory-intensive processes need significant memory
                memoryScaling = Math.max(2.0, sizeGB * 0.5)
                break
            case 'process_high':
                // High-performance processes need moderate memory scaling
                memoryScaling = Math.max(1.5, sizeGB * 0.2)
                break
            case 'process_medium':
                memoryScaling = Math.max(1.2, sizeGB * 0.1)
                break
            default:
                memoryScaling = Math.max(1.0, sizeGB * 0.05)
        }
        
        def optimalMemoryGB = baseMemoryGB * factors.memory * memoryScaling
        
        // Apply reasonable limits
        optimalMemoryGB = Math.min(Math.max(2, optimalMemoryGB), 1000)
        
        return "${Math.ceil(optimalMemoryGB)}.GB"
    }
    
    private static def calculateOptimalTime(totalSize, sampleCount, processLabel, factors, baseTime) {
        def sizeGB = totalSize / (1024 * 1024 * 1024)
        def baseTimeHours = baseTime ? parseTimeToHours(baseTime) : 2
        
        // Size-based time scaling
        def timeScaling = 1.0
        if (sizeGB > 10) {
            timeScaling = Math.max(1.5, Math.log(sizeGB / 10) + 1)
        }
        
        // Sample count scaling
        def sampleTimeScaling = 1.0
        if (sampleCount > 1) {
            sampleTimeScaling = Math.max(1.2, Math.log(sampleCount) + 1)
        }
        
        def optimalTimeHours = baseTimeHours * factors.time * timeScaling * sampleTimeScaling
        
        // Apply reasonable limits
        optimalTimeHours = Math.min(Math.max(0.5, optimalTimeHours), 72)
        
        return "${Math.ceil(optimalTimeHours)}.h"
    }
    
    private static def calculateOptimalBatchSize(sampleCount, optimalForks, processLabel) {
        if (sampleCount <= optimalForks) {
            return 1
        }
        
        def batchSize = Math.ceil(sampleCount / optimalForks)
        
        // Adjust batch size based on process characteristics
        switch (processLabel) {
            case 'process_memory_intensive':
                // Smaller batches for memory-intensive processes
                batchSize = Math.min(batchSize, 2)
                break
            case 'process_quick':
                // Larger batches for quick processes to reduce overhead
                batchSize = Math.min(batchSize * 2, 10)
                break
        }
        
        return Math.max(1, batchSize)
    }
    
    private static def generatePerformanceHints(totalSize, sampleCount, processLabel, resources) {
        def hints = []
        def sizeGB = totalSize / (1024 * 1024 * 1024)
        
        if (sizeGB > 100) {
            hints << "Large input detected (${Math.round(sizeGB)}GB). Consider using SSD storage for better I/O performance."
        }
        
        if (sampleCount > 20) {
            hints << "Multiple samples detected (${sampleCount}). Enable parallel processing for better throughput."
        }
        
        if (processLabel == 'process_memory_intensive' && parseMemoryToGB(resources.memory) > 128) {
            hints << "High memory requirement detected. Consider using bigmem partition or nodes with sufficient RAM."
        }
        
        if (processLabel == 'process_gpu') {
            hints << "GPU-accelerated process. Ensure GPU nodes are available and properly configured."
        }
        
        return hints
    }
    
    private static def generateMonitoringCommands(monitoring) {
        def commands = []
        
        if (monitoring.memoryAlert) {
            commands << "ps -o pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -10"
        }
        
        if (monitoring.cpuUtilization) {
            commands << "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1"
        }
        
        if (monitoring.gpuUtilization) {
            commands << "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits"
        }
        
        if (monitoring.ioWait) {
            commands << "iostat -x 1 1 | tail -n +4"
        }
        
        return commands
    }
    
    private static def analyzeProcessPerformance(processName, result, resourceUsage) {
        def analysis = [bottlenecks: [], recommendations: []]
        
        if (!resourceUsage) {
            return analysis
        }
        
        // Memory bottleneck detection
        if (resourceUsage.maxMemoryUsage && resourceUsage.allocatedMemory) {
            def memoryUtilization = resourceUsage.maxMemoryUsage / resourceUsage.allocatedMemory
            if (memoryUtilization > 0.95) {
                analysis.bottlenecks << "Memory bottleneck: ${Math.round(memoryUtilization * 100)}% utilization"
                analysis.recommendations << "Increase memory allocation by ${Math.ceil(memoryUtilization * 1.2 - 1) * 100}%"
            }
        }
        
        // CPU bottleneck detection
        if (resourceUsage.avgCpuUsage && resourceUsage.allocatedCpus) {
            def cpuUtilization = resourceUsage.avgCpuUsage / (resourceUsage.allocatedCpus * 100)
            if (cpuUtilization < 0.5) {
                analysis.bottlenecks << "CPU underutilization: ${Math.round(cpuUtilization * 100)}% average usage"
                analysis.recommendations << "Reduce CPU allocation or increase parallelization"
            }
        }
        
        // Time bottleneck detection
        if (resourceUsage.executionTime && resourceUsage.allocatedTime) {
            def timeUtilization = resourceUsage.executionTime / resourceUsage.allocatedTime
            if (timeUtilization > 0.9) {
                analysis.bottlenecks << "Time bottleneck: ${Math.round(timeUtilization * 100)}% of allocated time used"
                analysis.recommendations << "Increase time allocation or optimize process"
            }
        }
        
        return analysis
    }
    
    private static def analyzePipelinePerformance(pipelineStats) {
        def analysis = [:]
        
        // Calculate total pipeline time
        analysis.totalTime = pipelineStats.endTime - pipelineStats.startTime
        
        // Identify longest running processes
        analysis.longestProcesses = pipelineStats.processes
            .sort { -it.duration }
            .take(5)
        
        // Calculate parallelization efficiency
        analysis.parallelizationEfficiency = calculateParallelizationEfficiency(pipelineStats)
        
        return analysis
    }
    
    private static def generateResourceRecommendations(resourceUsage) {
        def recommendations = []
        
        resourceUsage.each { processName, usage ->
            if (usage.memoryUtilization > 0.9) {
                recommendations << [
                    type: 'memory',
                    process: processName,
                    description: "Increase memory allocation for ${processName}",
                    priority: 3,
                    currentValue: usage.allocatedMemory,
                    recommendedValue: usage.allocatedMemory * 1.3
                ]
            }
            
            if (usage.cpuUtilization < 0.3) {
                recommendations << [
                    type: 'cpu',
                    process: processName,
                    description: "Reduce CPU allocation for ${processName}",
                    priority: 2,
                    currentValue: usage.allocatedCpus,
                    recommendedValue: Math.max(1, usage.allocatedCpus * 0.7)
                ]
            }
        }
        
        return recommendations
    }
    
    private static def generateParallelizationRecommendations(pipelineStats) {
        def recommendations = []
        
        // Analyze process dependencies and parallelization opportunities
        def serialProcesses = pipelineStats.processes.findAll { 
            it.parallelizationPotential > 0.7 && it.actualParallelization < 0.5 
        }
        
        serialProcesses.each { process ->
            recommendations << [
                type: 'parallelization',
                process: process.name,
                description: "Increase parallelization for ${process.name}",
                priority: 3,
                currentValue: process.actualParallelization,
                recommendedValue: Math.min(0.8, process.parallelizationPotential)
            ]
        }
        
        return recommendations
    }
    
    private static def generateConfigurationRecommendations(pipelineStats, resourceUsage) {
        def recommendations = []
        
        // Profile-based recommendations
        def avgMemoryUsage = resourceUsage.values().collect { it.memoryUtilization }.sum() / resourceUsage.size()
        
        if (avgMemoryUsage > 0.8) {
            recommendations << [
                type: 'profile',
                description: "Consider using a higher memory profile",
                priority: 2,
                suggestion: "Switch to 'large_hpc' or 'medium' profile"
            ]
        }
        
        return recommendations
    }
    
    private static def generateRecommendationSummary(recommendations) {
        def summary = [:]
        
        summary.totalRecommendations = recommendations.size()
        summary.highPriority = recommendations.count { it.priority >= 3 }
        summary.mediumPriority = recommendations.count { it.priority == 2 }
        summary.lowPriority = recommendations.count { it.priority == 1 }
        
        summary.categories = recommendations.groupBy { it.type }.collectEntries { k, v -> 
            [k, v.size()] 
        }
        
        return summary
    }
    
    private static def calculateEstimatedImprovement(recommendations, pipelineStats) {
        def improvement = [:]
        
        // Estimate time improvement
        def timeRecommendations = recommendations.findAll { 
            it.type in ['parallelization', 'cpu', 'profile'] 
        }
        improvement.estimatedTimeReduction = timeRecommendations.size() * 0.15 // 15% per recommendation
        
        // Estimate resource efficiency improvement
        def resourceRecommendations = recommendations.findAll { 
            it.type in ['memory', 'cpu'] 
        }
        improvement.estimatedResourceEfficiency = resourceRecommendations.size() * 0.10 // 10% per recommendation
        
        return improvement
    }
    
    private static def calculateParallelizationEfficiency(pipelineStats) {
        def totalProcessTime = pipelineStats.processes.sum { it.duration }
        def wallClockTime = pipelineStats.totalTime
        
        return totalProcessTime > 0 ? wallClockTime / totalProcessTime : 0
    }
    
    private static def generateOptimalConfiguration(inputCharacteristics, systemCapabilities) {
        def config = [:]
        
        // Determine optimal resource profile
        def totalSizeGB = inputCharacteristics.totalSize / (1024 * 1024 * 1024)
        
        if (totalSizeGB > 500 || inputCharacteristics.sampleCount > 50) {
            config.recommendedProfile = 'large_hpc'
        } else if (totalSizeGB > 100 || inputCharacteristics.sampleCount > 20) {
            config.recommendedProfile = 'medium'
        } else if (totalSizeGB > 20 || inputCharacteristics.sampleCount > 5) {
            config.recommendedProfile = 'small'
        } else {
            config.recommendedProfile = 'test'
        }
        
        // Optimal parallelization settings
        config.maxForks = Math.min(
            inputCharacteristics.sampleCount,
            systemCapabilities.maxCpus / 4,
            20
        )
        
        // Memory optimization
        config.memoryStrategy = totalSizeGB > 200 ? 'memory_conservative' : 'balanced'
        
        return config
    }
    
    // Utility methods
    private static def parseMemoryToGB(memory) {
        if (!memory) return 0
        if (memory instanceof String) {
            return memory.toMemory().toGiga()
        }
        return memory.toGiga()
    }
    
    private static def parseTimeToHours(time) {
        if (!time) return 0
        if (time instanceof String) {
            return time.toDuration().toHours()
        }
        return time.toHours()
    }
    
    private static def generateBottleneckSummary(bottlenecks, recommendations) {
        def summary = [:]
        
        summary.totalBottlenecks = bottlenecks.size()
        summary.bottleneckTypes = bottlenecks.groupBy { 
            it.bottleneck.split(':')[0] 
        }.collectEntries { k, v -> [k, v.size()] }
        
        summary.totalRecommendations = recommendations.size()
        summary.criticalIssues = bottlenecks.count { 
            it.bottleneck.contains('bottleneck') 
        }
        
        return summary
    }
}