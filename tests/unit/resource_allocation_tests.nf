#!/usr/bin/env nextflow

/**
 * Unit Tests for Resource Allocation Functions
 * 
 * Tests resource allocation logic, scaling, and validation
 * Requirements: 6.1, 6.2, 6.3, 6.4
 */

nextflow.enable.dsl = 2

workflow TEST_RESOURCE_ALLOCATION {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: Resource Scaling Logic
    testResults.tests << testResourceScalingLogic()
    
    // Test 2: Resource Limit Validation
    testResults.tests << testResourceLimitValidation()
    
    // Test 3: Memory Unit Conversion
    testResults.tests << testMemoryUnitConversion()
    
    // Test 4: Time Unit Conversion
    testResults.tests << testTimeUnitConversion()
    
    // Test 5: CPU Allocation Logic
    testResults.tests << testCpuAllocationLogic()
    
    // Test 6: Retry Scaling Behavior
    testResults.tests << testRetryScalingBehavior()
    
    // Test 7: Profile-Specific Resource Allocation
    testResults.tests << testProfileSpecificAllocation()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testResourceScalingLogic() {
    def testName = "Resource Scaling Logic"
    
    try {
        // Test basic scaling function
        def scaledCpus = check_max(4 * 2, 8)  // task.attempt = 2, max = 8
        assert scaledCpus == 8 : "Should scale CPUs correctly within limits"
        
        def exceededCpus = check_max(4 * 5, 8)  // task.attempt = 5, max = 8
        assert exceededCpus == 8 : "Should cap CPUs at maximum"
        
        // Test memory scaling
        def scaledMemory = check_max('8.GB'.toMemory() * 2, '16.GB'.toMemory())
        assert scaledMemory.toGiga() == 16 : "Should scale memory correctly within limits"
        
        def exceededMemory = check_max('8.GB'.toMemory() * 5, '16.GB'.toMemory())
        assert exceededMemory.toGiga() == 16 : "Should cap memory at maximum"
        
        // Test time scaling
        def scaledTime = check_max('2.h'.toDuration() * 2, '8.h'.toDuration())
        assert scaledTime.toHours() == 4 : "Should scale time correctly within limits"
        
        def exceededTime = check_max('2.h'.toDuration() * 10, '8.h'.toDuration())
        assert exceededTime.toHours() == 8 : "Should cap time at maximum"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testResourceLimitValidation() {
    def testName = "Resource Limit Validation"
    
    try {
        // Test valid resource limits
        def validLimits = [
            max_cpus: 16,
            max_memory: '64.GB',
            max_time: '24.h'
        ]
        
        assert validateResourceLimits(validLimits) : "Valid limits should pass validation"
        
        // Test invalid CPU limit
        def invalidCpuLimits = [
            max_cpus: -1,
            max_memory: '64.GB',
            max_time: '24.h'
        ]
        
        assert !validateResourceLimits(invalidCpuLimits) : "Negative CPU limit should fail validation"
        
        // Test invalid memory limit
        def invalidMemoryLimits = [
            max_cpus: 16,
            max_memory: 'invalid',
            max_time: '24.h'
        ]
        
        assert !validateResourceLimits(invalidMemoryLimits) : "Invalid memory format should fail validation"
        
        // Test zero limits
        def zeroLimits = [
            max_cpus: 0,
            max_memory: '0.GB',
            max_time: '0.h'
        ]
        
        assert !validateResourceLimits(zeroLimits) : "Zero limits should fail validation"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testMemoryUnitConversion() {
    def testName = "Memory Unit Conversion"
    
    try {
        // Test GB to MB conversion
        def gbToMb = convertMemoryToMB('16.GB')
        assert gbToMb == 16384 : "Should convert GB to MB correctly"
        
        // Test MB input
        def mbToMb = convertMemoryToMB('1024.MB')
        assert mbToMb == 1024 : "Should handle MB input correctly"
        
        // Test memory object conversion
        def memoryObj = '32.GB'.toMemory()
        def objToMb = convertMemoryToMB(memoryObj)
        assert objToMb == 32768 : "Should convert memory object to MB correctly"
        
        // Test GB conversion
        def gbConversion = convertMemoryToGB('2048.MB')
        assert gbConversion == 2 : "Should convert MB to GB correctly"
        
        def gbFromGb = convertMemoryToGB('8.GB')
        assert gbFromGb == 8 : "Should handle GB input correctly"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testTimeUnitConversion() {
    def testName = "Time Unit Conversion"
    
    try {
        // Test hours conversion
        def hoursFromH = convertTimeToHours('4.h')
        assert hoursFromH == 4 : "Should convert hours correctly"
        
        def hoursFromM = convertTimeToHours('120.m')
        assert hoursFromM == 2 : "Should convert minutes to hours correctly"
        
        def hoursFromS = convertTimeToHours('7200.s')
        assert hoursFromS == 2 : "Should convert seconds to hours correctly"
        
        // Test duration object conversion
        def durationObj = '6.h'.toDuration()
        def objToHours = convertTimeToHours(durationObj)
        assert objToHours == 6 : "Should convert duration object to hours correctly"
        
        // Test fractional hours
        def fractionalHours = convertTimeToHours('90.m')
        assert fractionalHours == 1.5 : "Should handle fractional hours correctly"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testCpuAllocationLogic() {
    def testName = "CPU Allocation Logic"
    
    try {
        // Test CPU allocation for different process labels
        def lowCpus = calculateCpuAllocation('process_low', 1, 16)
        assert lowCpus <= 4 : "Low processes should use few CPUs"
        
        def mediumCpus = calculateCpuAllocation('process_medium', 1, 16)
        assert mediumCpus >= lowCpus : "Medium processes should use more CPUs than low"
        assert mediumCpus <= 8 : "Medium processes should not exceed reasonable limits"
        
        def highCpus = calculateCpuAllocation('process_high', 1, 16)
        assert highCpus >= mediumCpus : "High processes should use more CPUs than medium"
        assert highCpus <= 16 : "High processes should not exceed system limits"
        
        // Test scaling with retry attempts
        def scaledCpus = calculateCpuAllocation('process_medium', 3, 16)
        def baseCpus = calculateCpuAllocation('process_medium', 1, 16)
        assert scaledCpus >= baseCpus : "Should scale CPUs with retry attempts"
        
        // Test system limit enforcement
        def limitedCpus = calculateCpuAllocation('process_high', 1, 4)
        assert limitedCpus <= 4 : "Should respect system CPU limits"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testRetryScalingBehavior() {
    def testName = "Retry Scaling Behavior"
    
    try {
        // Test linear scaling
        def attempt1 = calculateResourceWithRetry(4, 1, 16)
        def attempt2 = calculateResourceWithRetry(4, 2, 16)
        def attempt3 = calculateResourceWithRetry(4, 3, 16)
        
        assert attempt2 == attempt1 * 2 : "Should scale linearly with attempts"
        assert attempt3 == attempt1 * 3 : "Should continue linear scaling"
        
        // Test maximum limit enforcement
        def attemptHigh = calculateResourceWithRetry(4, 10, 16)
        assert attemptHigh <= 16 : "Should not exceed maximum limit"
        
        // Test with different base values
        def memoryAttempt1 = calculateResourceWithRetry(8, 1, 64)
        def memoryAttempt2 = calculateResourceWithRetry(8, 2, 64)
        
        assert memoryAttempt2 == memoryAttempt1 * 2 : "Should scale memory resources correctly"
        
        // Test edge case with attempt 0
        def attempt0 = calculateResourceWithRetry(4, 0, 16)
        assert attempt0 == 0 : "Should handle zero attempts correctly"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testProfileSpecificAllocation() {
    def testName = "Profile-Specific Resource Allocation"
    
    try {
        // Test local profile constraints
        def localResources = calculateProfileResources('local', 'process_high')
        assert localResources.cpus <= Runtime.runtime.availableProcessors() : "Local profile should respect system CPU limits"
        assert localResources.memory <= getSystemMemoryGB() : "Local profile should respect system memory limits"
        
        // Test SLURM profile resources
        def slurmResources = calculateProfileResources('slurm', 'process_high')
        assert slurmResources.cpus >= localResources.cpus : "SLURM profile should allow more CPUs"
        assert slurmResources.memory >= localResources.memory : "SLURM profile should allow more memory"
        
        // Test memory-intensive process on different profiles
        def localMemoryIntensive = calculateProfileResources('local', 'process_memory_intensive')
        def slurmMemoryIntensive = calculateProfileResources('slurm', 'process_memory_intensive')
        
        assert slurmMemoryIntensive.memory > localMemoryIntensive.memory : "SLURM should allow more memory for intensive processes"
        
        // Test quick process optimization
        def quickResources = calculateProfileResources('slurm', 'process_quick')
        assert quickResources.cpus <= 4 : "Quick processes should use limited CPUs"
        assert quickResources.memory <= 16 : "Quick processes should use limited memory"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

// Helper functions for testing

def check_max(obj, max_val) {
    if (obj instanceof nextflow.util.MemoryUnit) {
        def max_memory = max_val instanceof String ? max_val.toMemory() : max_val
        return obj > max_memory ? max_memory : obj
    } else if (obj instanceof nextflow.util.Duration) {
        def max_time = max_val instanceof String ? max_val.toDuration() : max_val
        return obj > max_time ? max_time : obj
    } else {
        return obj > max_val ? max_val : obj
    }
}

def validateResourceLimits(limits) {
    try {
        if (limits.max_cpus != null && limits.max_cpus <= 0) return false
        if (limits.max_memory != null) {
            def memory = limits.max_memory instanceof String ? limits.max_memory.toMemory() : limits.max_memory
            if (memory.toBytes() <= 0) return false
        }
        if (limits.max_time != null) {
            def time = limits.max_time instanceof String ? limits.max_time.toDuration() : limits.max_time
            if (time.toMillis() <= 0) return false
        }
        return true
    } catch (Exception e) {
        return false
    }
}

def convertMemoryToMB(memory) {
    if (memory instanceof String) {
        return memory.toMemory().toMega()
    } else if (memory instanceof nextflow.util.MemoryUnit) {
        return memory.toMega()
    } else {
        return memory
    }
}

def convertMemoryToGB(memory) {
    if (memory instanceof String) {
        return memory.toMemory().toGiga()
    } else if (memory instanceof nextflow.util.MemoryUnit) {
        return memory.toGiga()
    } else {
        return memory
    }
}

def convertTimeToHours(time) {
    if (time instanceof String) {
        return time.toDuration().toHours()
    } else if (time instanceof nextflow.util.Duration) {
        return time.toHours()
    } else {
        return time
    }
}

def calculateCpuAllocation(processLabel, attempt, maxCpus) {
    def baseCpus = 2
    
    switch (processLabel) {
        case 'process_low':
            baseCpus = 2
            break
        case 'process_medium':
            baseCpus = 4
            break
        case 'process_high':
            baseCpus = 8
            break
        case 'process_memory_intensive':
            baseCpus = 4
            break
        case 'process_quick':
            baseCpus = 1
            break
    }
    
    def scaledCpus = baseCpus * attempt
    return Math.min(scaledCpus, maxCpus)
}

def calculateResourceWithRetry(baseValue, attempt, maxValue) {
    def scaled = baseValue * attempt
    return Math.min(scaled, maxValue)
}

def calculateProfileResources(profile, processLabel) {
    def resources = [:]
    
    switch (profile) {
        case 'local':
            resources.cpus = Math.min(calculateCpuAllocation(processLabel, 1, Runtime.runtime.availableProcessors()), 8)
            resources.memory = Math.min(getProcessMemoryGB(processLabel), getSystemMemoryGB() * 0.8)
            break
        case 'slurm':
            resources.cpus = calculateCpuAllocation(processLabel, 1, 128)
            resources.memory = getProcessMemoryGB(processLabel)
            break
        default:
            resources.cpus = calculateCpuAllocation(processLabel, 1, 16)
            resources.memory = getProcessMemoryGB(processLabel)
    }
    
    return resources
}

def getProcessMemoryGB(processLabel) {
    switch (processLabel) {
        case 'process_low':
            return 4
        case 'process_medium':
            return 8
        case 'process_high':
            return 16
        case 'process_memory_intensive':
            return 32
        case 'process_quick':
            return 2
        default:
            return 8
    }
}

def getSystemMemoryGB() {
    return Runtime.runtime.maxMemory() / (1024 * 1024 * 1024)
}