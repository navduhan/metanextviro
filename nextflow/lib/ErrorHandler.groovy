/**
 * Enhanced Error Handling System for MetaNextViro Pipeline
 * 
 * This module provides structured error handling with actionable messages,
 * error recovery strategies, and process failure tracking.
 */

/**
 * Base class for all pipeline errors with structured information
 */
abstract class PipelineError extends Exception {
    String component
    String errorCode
    String suggestion
    Map<String, Object> context = [:]
    ErrorSeverity severity
    boolean recoverable = false
    
    PipelineError(String message, String component, String errorCode, ErrorSeverity severity = ErrorSeverity.ERROR) {
        super(message)
        this.component = component
        this.errorCode = errorCode
        this.severity = severity
    }
    
    PipelineError withSuggestion(String suggestion) {
        this.suggestion = suggestion
        return this
    }
    
    PipelineError withContext(String key, Object value) {
        this.context[key] = value
        return this
    }
    
    PipelineError withContext(Map<String, Object> contextMap) {
        this.context.putAll(contextMap)
        return this
    }
    
    PipelineError asRecoverable() {
        this.recoverable = true
        return this
    }
    
    String getFormattedMessage() {
        def sb = new StringBuilder()
        sb.append("${severity.icon} [${component}:${errorCode}] ${message}")
        
        if (suggestion) {
            sb.append("\n💡 Suggestion: ${suggestion}")
        }
        
        if (context) {
            sb.append("\n📋 Context:")
            context.each { key, value ->
                sb.append("\n   ${key}: ${value}")
            }
        }
        
        return sb.toString()
    }
}

/**
 * Error severity levels with visual indicators
 */
enum ErrorSeverity {
    CRITICAL("🔴", "CRITICAL", 4),
    ERROR("❌", "ERROR", 3),
    WARNING("⚠️", "WARNING", 2),
    INFO("ℹ️", "INFO", 1)
    
    final String icon
    final String label
    final int level
    
    ErrorSeverity(String icon, String label, int level) {
        this.icon = icon
        this.label = label
        this.level = level
    }
}

/**
 * Input validation errors
 */
class InputValidationError extends PipelineError {
    InputValidationError(String message, String errorCode = "INPUT_VALIDATION") {
        super(message, "INPUT_VALIDATION", errorCode, ErrorSeverity.ERROR)
    }
}

/**
 * Configuration errors
 */
class ConfigurationError extends PipelineError {
    ConfigurationError(String message, String errorCode = "CONFIG_ERROR") {
        super(message, "CONFIGURATION", errorCode, ErrorSeverity.ERROR)
    }
}

/**
 * Resource allocation errors
 */
class ResourceError extends PipelineError {
    ResourceError(String message, String errorCode = "RESOURCE_ERROR") {
        super(message, "RESOURCE", errorCode, ErrorSeverity.ERROR)
        this.recoverable = true // Resource errors are often recoverable
    }
}

/**
 * Process execution errors
 */
class ProcessExecutionError extends PipelineError {
    String processName
    int exitCode
    String workDir
    
    ProcessExecutionError(String message, String processName, int exitCode = -1, String errorCode = "PROCESS_FAILED") {
        super(message, "PROCESS", errorCode, ErrorSeverity.ERROR)
        this.processName = processName
        this.exitCode = exitCode
    }
    
    ProcessExecutionError withWorkDir(String workDir) {
        this.workDir = workDir
        return this
    }
}

/**
 * Database access errors
 */
class DatabaseError extends PipelineError {
    String databasePath
    String databaseType
    
    DatabaseError(String message, String databasePath, String databaseType, String errorCode = "DATABASE_ERROR") {
        super(message, "DATABASE", errorCode, ErrorSeverity.ERROR)
        this.databasePath = databasePath
        this.databaseType = databaseType
    }
}

/**
 * Environment setup errors
 */
class EnvironmentError extends PipelineError {
    String environmentName
    List<String> missingDependencies = []
    
    EnvironmentError(String message, String environmentName, String errorCode = "ENV_ERROR") {
        super(message, "ENVIRONMENT", errorCode, ErrorSeverity.ERROR)
        this.environmentName = environmentName
    }
    
    EnvironmentError withMissingDependencies(List<String> dependencies) {
        this.missingDependencies = dependencies
        return this
    }
}

/**
 * Error recovery strategies
 */
class ErrorRecoveryStrategy {
    String strategyName
    String description
    Closure<Boolean> canRecover
    Closure<Map> recover
    int maxAttempts = 3
    
    ErrorRecoveryStrategy(String name, String description) {
        this.strategyName = name
        this.description = description
    }
    
    ErrorRecoveryStrategy withRecoveryCheck(Closure<Boolean> check) {
        this.canRecover = check
        return this
    }
    
    ErrorRecoveryStrategy withRecoveryAction(Closure<Map> action) {
        this.recover = action
        return this
    }
    
    ErrorRecoveryStrategy withMaxAttempts(int attempts) {
        this.maxAttempts = attempts
        return this
    }
    
    boolean canRecoverFrom(PipelineError error) {
        return error.recoverable && canRecover?.call(error)
    }
    
    Map attemptRecovery(PipelineError error, Map context = [:]) {
        if (!canRecoverFrom(error)) {
            return [success: false, message: "Recovery strategy not applicable"]
        }
        
        try {
            return recover?.call(error, context) ?: [success: false, message: "No recovery action defined"]
        } catch (Exception e) {
            return [success: false, message: "Recovery failed: ${e.message}", exception: e]
        }
    }
}

/**
 * Process failure tracker for reporting
 */
class ProcessFailureTracker {
    private Map<String, List<ProcessFailure>> failures = [:]
    private Map<String, ProcessStatus> processStatus = [:]
    
    void recordFailure(String processName, PipelineError error, Map context = [:]) {
        def failure = new ProcessFailure(
            processName: processName,
            error: error,
            timestamp: new Date(),
            context: context
        )
        
        if (!failures[processName]) {
            failures[processName] = []
        }
        failures[processName] << failure
        
        processStatus[processName] = ProcessStatus.FAILED
    }
    
    void recordSuccess(String processName, Map context = [:]) {
        processStatus[processName] = ProcessStatus.COMPLETED
    }
    
    void recordSkipped(String processName, String reason, Map context = [:]) {
        processStatus[processName] = ProcessStatus.SKIPPED
        
        if (!failures[processName]) {
            failures[processName] = []
        }
        failures[processName] << new ProcessFailure(
            processName: processName,
            error: new PipelineError("Process skipped: ${reason}", "PROCESS", "SKIPPED", ErrorSeverity.INFO),
            timestamp: new Date(),
            context: context
        )
    }
    
    List<ProcessFailure> getFailures(String processName = null) {
        if (processName) {
            return failures[processName] ?: []
        }
        return failures.values().flatten()
    }
    
    Map<String, ProcessStatus> getProcessStatuses() {
        return processStatus.clone()
    }
    
    boolean hasFailures() {
        return failures.any { key, value -> value.any { it.error.severity in [ErrorSeverity.ERROR, ErrorSeverity.CRITICAL] } }
    }
    
    boolean hasCriticalFailures() {
        return failures.any { key, value -> value.any { it.error.severity == ErrorSeverity.CRITICAL } }
    }
    
    Map generateFailureReport() {
        def report = [
            summary: [
                totalProcesses: processStatus.size(),
                completed: processStatus.count { it.value == ProcessStatus.COMPLETED },
                failed: processStatus.count { it.value == ProcessStatus.FAILED },
                skipped: processStatus.count { it.value == ProcessStatus.SKIPPED }
            ],
            failures: [],
            processStatuses: processStatus
        ]
        
        failures.each { processName, processFailures ->
            processFailures.each { failure ->
                report.failures << [
                    process: processName,
                    timestamp: failure.timestamp,
                    severity: failure.error.severity.label,
                    component: failure.error.component,
                    errorCode: failure.error.errorCode,
                    message: failure.error.message,
                    suggestion: failure.error.suggestion,
                    context: failure.context,
                    recoverable: failure.error.recoverable
                ]
            }
        }
        
        return report
    }
}

/**
 * Individual process failure record
 */
class ProcessFailure {
    String processName
    PipelineError error
    Date timestamp
    Map context
}

/**
 * Process execution status
 */
enum ProcessStatus {
    PENDING,
    RUNNING,
    COMPLETED,
    FAILED,
    SKIPPED
}

/**
 * Enhanced error handler with recovery capabilities
 */
class EnhancedErrorHandler {
    private ProcessFailureTracker failureTracker = new ProcessFailureTracker()
    private List<ErrorRecoveryStrategy> recoveryStrategies = []
    private boolean gracefulDegradation = true
    
    EnhancedErrorHandler() {
        initializeDefaultRecoveryStrategies()
    }
    
    void addRecoveryStrategy(ErrorRecoveryStrategy strategy) {
        recoveryStrategies << strategy
    }
    
    void enableGracefulDegradation(boolean enable = true) {
        this.gracefulDegradation = enable
    }
    
    /**
     * Handle a pipeline error with recovery attempts
     */
    Map handleError(PipelineError error, String processName = null, Map context = [:]) {
        // Record the failure
        if (processName) {
            failureTracker.recordFailure(processName, error, context)
        }
        
        // Attempt recovery if error is recoverable
        if (error.recoverable) {
            def recoveryResult = attemptRecovery(error, context)
            if (recoveryResult.success) {
                return [
                    handled: true,
                    recovered: true,
                    message: "Error recovered: ${recoveryResult.message}",
                    action: recoveryResult.action
                ]
            }
        }
        
        // Check if graceful degradation is possible
        if (gracefulDegradation && canDegrade(error, processName)) {
            return [
                handled: true,
                degraded: true,
                message: "Process degraded gracefully: ${error.message}",
                action: "continue_without_${processName}"
            ]
        }
        
        // Error cannot be recovered or degraded
        return [
            handled: false,
            message: error.getFormattedMessage(),
            critical: error.severity == ErrorSeverity.CRITICAL
        ]
    }
    
    /**
     * Attempt error recovery using available strategies
     */
    private Map attemptRecovery(PipelineError error, Map context) {
        for (strategy in recoveryStrategies) {
            if (strategy.canRecoverFrom(error)) {
                def result = strategy.attemptRecovery(error, context)
                if (result.success) {
                    return result
                }
            }
        }
        return [success: false, message: "No applicable recovery strategy found"]
    }
    
    /**
     * Check if graceful degradation is possible for a process
     */
    private boolean canDegrade(PipelineError error, String processName) {
        // Define optional processes that can be skipped
        def optionalProcesses = [
            'CHECKV', 'VIRFINDER', 'COVERAGE_PLOT', 'HEATMAP', 
            'KRONA', 'HTML_REPORT', 'MULTIQC'
        ]
        
        return processName in optionalProcesses && 
               error.severity != ErrorSeverity.CRITICAL
    }
    
    /**
     * Initialize default recovery strategies
     */
    private void initializeDefaultRecoveryStrategies() {
        // Memory retry strategy
        addRecoveryStrategy(
            new ErrorRecoveryStrategy("memory_retry", "Retry with increased memory allocation")
                .withRecoveryCheck { error -> 
                    error instanceof ResourceError && 
                    error.message.toLowerCase().contains("memory")
                }
                .withRecoveryAction { error, context ->
                    def currentMemory = context.memory ?: "4.GB"
                    def newMemory = increaseMemory(currentMemory)
                    return [
                        success: true, 
                        message: "Increased memory from ${currentMemory} to ${newMemory}",
                        action: "retry_with_memory",
                        newMemory: newMemory
                    ]
                }
        )
        
        // Time retry strategy
        addRecoveryStrategy(
            new ErrorRecoveryStrategy("time_retry", "Retry with increased time allocation")
                .withRecoveryCheck { error ->
                    error instanceof ResourceError && 
                    error.message.toLowerCase().contains("time")
                }
                .withRecoveryAction { error, context ->
                    def currentTime = context.time ?: "2h"
                    def newTime = increaseTime(currentTime)
                    return [
                        success: true,
                        message: "Increased time from ${currentTime} to ${newTime}",
                        action: "retry_with_time",
                        newTime: newTime
                    ]
                }
        )
        
        // Database fallback strategy
        addRecoveryStrategy(
            new ErrorRecoveryStrategy("database_fallback", "Use alternative database")
                .withRecoveryCheck { error ->
                    error instanceof DatabaseError
                }
                .withRecoveryAction { error, context ->
                    def fallbackDb = getFallbackDatabase(error.databaseType)
                    if (fallbackDb) {
                        return [
                            success: true,
                            message: "Using fallback database: ${fallbackDb}",
                            action: "use_fallback_database",
                            fallbackDatabase: fallbackDb
                        ]
                    }
                    return [success: false, message: "No fallback database available"]
                }
        )
    }
    
    /**
     * Increase memory allocation for retry
     */
    private String increaseMemory(String currentMemory) {
        def memoryValue = currentMemory.replaceAll(/[^\d.]/, '') as Double
        def unit = currentMemory.replaceAll(/[\d.]/, '')
        
        def newValue = memoryValue * 2
        return "${newValue}${unit}"
    }
    
    /**
     * Increase time allocation for retry
     */
    private String increaseTime(String currentTime) {
        def timeValue = currentTime.replaceAll(/[^\d]/, '') as Integer
        def unit = currentTime.replaceAll(/\d/, '')
        
        def newValue = timeValue * 2
        return "${newValue}${unit}"
    }
    
    /**
     * Get fallback database for a given database type
     */
    private String getFallbackDatabase(String databaseType) {
        def fallbacks = [
            'kraken2': 'minikraken2_v2_8GB',
            'blast_nt': 'blast_nr',
            'blast_nr': 'blast_nt'
        ]
        return fallbacks[databaseType]
    }
    
    /**
     * Get failure tracker for reporting
     */
    ProcessFailureTracker getFailureTracker() {
        return failureTracker
    }
    
    /**
     * Record successful process completion
     */
    void recordSuccess(String processName, Map context = [:]) {
        failureTracker.recordSuccess(processName, context)
    }
    
    /**
     * Record skipped process
     */
    void recordSkipped(String processName, String reason, Map context = [:]) {
        failureTracker.recordSkipped(processName, reason, context)
    }
}