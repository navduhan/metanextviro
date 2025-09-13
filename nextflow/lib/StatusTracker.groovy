/**
 * Status Tracking System for MetaNextViro Pipeline
 * 
 * This module provides comprehensive status tracking for pipeline components,
 * process completion monitoring, and report generation status management.
 */

/**
 * Pipeline component status enumeration
 */
enum ComponentStatus {
    PENDING('⏳', 'Pending', 'Component is waiting to start'),
    RUNNING('🔄', 'Running', 'Component is currently executing'),
    COMPLETED('✅', 'Completed', 'Component completed successfully'),
    FAILED('❌', 'Failed', 'Component failed with errors'),
    SKIPPED('⏭️', 'Skipped', 'Component was skipped'),
    TIMEOUT('⏰', 'Timeout', 'Component exceeded time limit'),
    CANCELLED('🚫', 'Cancelled', 'Component was cancelled'),
    RETRY('🔁', 'Retry', 'Component is being retried')
    
    final String icon
    final String label
    final String description
    
    ComponentStatus(String icon, String label, String description) {
        this.icon = icon
        this.label = label
        this.description = description
    }
}

/**
 * Pipeline component types
 */
enum ComponentType {
    INPUT_VALIDATION('Input Validation', true),
    QUALITY_CONTROL('Quality Control', true),
    TRIMMING('Read Trimming', false),
    TAXONOMIC_CLASSIFICATION('Taxonomic Classification', true),
    ASSEMBLY('Genome Assembly', true),
    ASSEMBLY_QUALITY('Assembly Quality Assessment', false),
    VIRAL_ANALYSIS('Viral Analysis', false),
    FUNCTIONAL_ANNOTATION('Functional Annotation', false),
    COVERAGE_ANALYSIS('Coverage Analysis', false),
    VISUALIZATION('Visualization', false),
    REPORT_GENERATION('Report Generation', true)
    
    final String displayName
    final boolean required
    
    ComponentType(String displayName, boolean required) {
        this.displayName = displayName
        this.required = required
    }
}

/**
 * Individual component tracking information
 */
class ComponentTracker {
    ComponentType type
    String processName
    ComponentStatus status
    Date startTime
    Date endTime
    Long duration
    Map<String, Object> metadata = [:]
    List<String> outputs = []
    String errorMessage
    int retryCount = 0
    int maxRetries = 3
    
    ComponentTracker(ComponentType type, String processName) {
        this.type = type
        this.processName = processName
        this.status = ComponentStatus.PENDING
    }
    
    void start() {
        this.status = ComponentStatus.RUNNING
        this.startTime = new Date()
    }
    
    void complete(List<String> outputs = []) {
        this.status = ComponentStatus.COMPLETED
        this.endTime = new Date()
        this.outputs = outputs
        calculateDuration()
    }
    
    void fail(String errorMessage) {
        this.status = ComponentStatus.FAILED
        this.endTime = new Date()
        this.errorMessage = errorMessage
        calculateDuration()
    }
    
    void skip(String reason) {
        this.status = ComponentStatus.SKIPPED
        this.endTime = new Date()
        this.errorMessage = reason
        calculateDuration()
    }
    
    void timeout() {
        this.status = ComponentStatus.TIMEOUT
        this.endTime = new Date()
        calculateDuration()
    }
    
    void cancel() {
        this.status = ComponentStatus.CANCELLED
        this.endTime = new Date()
        calculateDuration()
    }
    
    void retry() {
        this.retryCount++
        this.status = ComponentStatus.RETRY
        this.startTime = new Date()
        this.endTime = null
        this.duration = null
    }
    
    boolean canRetry() {
        return retryCount < maxRetries && status in [ComponentStatus.FAILED, ComponentStatus.TIMEOUT]
    }
    
    void addMetadata(String key, Object value) {
        this.metadata[key] = value
    }
    
    void addMetadata(Map<String, Object> data) {
        this.metadata.putAll(data)
    }
    
    private void calculateDuration() {
        if (startTime && endTime) {
            this.duration = endTime.time - startTime.time
        }
    }
    
    String getFormattedDuration() {
        if (!duration) return "N/A"
        
        long seconds = duration / 1000
        long minutes = seconds / 60
        long hours = minutes / 60
        
        if (hours > 0) {
            return "${hours}h ${minutes % 60}m ${seconds % 60}s"
        } else if (minutes > 0) {
            return "${minutes}m ${seconds % 60}s"
        } else {
            return "${seconds}s"
        }
    }
    
    Map toMap() {
        return [
            type: type.name(),
            displayName: type.displayName,
            processName: processName,
            status: status.name(),
            statusIcon: status.icon,
            statusLabel: status.label,
            required: type.required,
            startTime: startTime?.format('yyyy-MM-dd HH:mm:ss'),
            endTime: endTime?.format('yyyy-MM-dd HH:mm:ss'),
            duration: getFormattedDuration(),
            durationMs: duration,
            outputs: outputs,
            errorMessage: errorMessage,
            retryCount: retryCount,
            maxRetries: maxRetries,
            metadata: metadata
        ]
    }
}

/**
 * Pipeline status tracker with comprehensive monitoring
 */
class PipelineStatusTracker {
    private Map<String, ComponentTracker> components = [:]
    private Date pipelineStartTime
    private Date pipelineEndTime
    private String pipelineId
    private Map<String, Object> pipelineMetadata = [:]
    
    PipelineStatusTracker(String pipelineId = null) {
        this.pipelineId = pipelineId ?: UUID.randomUUID().toString()
        this.pipelineStartTime = new Date()
        initializeComponents()
    }
    
    /**
     * Initialize all pipeline components
     */
    private void initializeComponents() {
        ComponentType.values().each { type ->
            def componentId = type.name().toLowerCase()
            components[componentId] = new ComponentTracker(type, componentId)
        }
    }
    
    /**
     * Register a custom component
     */
    void registerComponent(String componentId, ComponentType type, String processName) {
        components[componentId] = new ComponentTracker(type, processName)
    }
    
    /**
     * Start tracking a component
     */
    void startComponent(String componentId) {
        def component = components[componentId]
        if (component) {
            component.start()
            log.info "${component.type.displayName} started"
        }
    }
    
    /**
     * Mark component as completed
     */
    void completeComponent(String componentId, List<String> outputs = []) {
        def component = components[componentId]
        if (component) {
            component.complete(outputs)
            log.info "${component.type.displayName} completed in ${component.getFormattedDuration()}"
        }
    }
    
    /**
     * Mark component as failed
     */
    void failComponent(String componentId, String errorMessage) {
        def component = components[componentId]
        if (component) {
            component.fail(errorMessage)
            log.error "${component.type.displayName} failed: ${errorMessage}"
        }
    }
    
    /**
     * Mark component as skipped
     */
    void skipComponent(String componentId, String reason) {
        def component = components[componentId]
        if (component) {
            component.skip(reason)
            log.info "${component.type.displayName} skipped: ${reason}"
        }
    }
    
    /**
     * Mark component as timed out
     */
    void timeoutComponent(String componentId) {
        def component = components[componentId]
        if (component) {
            component.timeout()
            log.warn "${component.type.displayName} timed out"
        }
    }
    
    /**
     * Cancel a component
     */
    void cancelComponent(String componentId) {
        def component = components[componentId]
        if (component) {
            component.cancel()
            log.info "${component.type.displayName} cancelled"
        }
    }
    
    /**
     * Retry a component
     */
    void retryComponent(String componentId) {
        def component = components[componentId]
        if (component && component.canRetry()) {
            component.retry()
            log.info "${component.type.displayName} retrying (attempt ${component.retryCount})"
        }
    }
    
    /**
     * Add metadata to a component
     */
    void addComponentMetadata(String componentId, String key, Object value) {
        def component = components[componentId]
        if (component) {
            component.addMetadata(key, value)
        }
    }
    
    /**
     * Add metadata to a component
     */
    void addComponentMetadata(String componentId, Map<String, Object> metadata) {
        def component = components[componentId]
        if (component) {
            component.addMetadata(metadata)
        }
    }
    
    /**
     * Get component status
     */
    ComponentStatus getComponentStatus(String componentId) {
        return components[componentId]?.status
    }
    
    /**
     * Get component tracker
     */
    ComponentTracker getComponent(String componentId) {
        return components[componentId]
    }
    
    /**
     * Get all components
     */
    Map<String, ComponentTracker> getAllComponents() {
        return components.clone()
    }
    
    /**
     * Get components by status
     */
    List<ComponentTracker> getComponentsByStatus(ComponentStatus status) {
        return components.values().findAll { it.status == status }
    }
    
    /**
     * Get required components
     */
    List<ComponentTracker> getRequiredComponents() {
        return components.values().findAll { it.type.required }
    }
    
    /**
     * Get optional components
     */
    List<ComponentTracker> getOptionalComponents() {
        return components.values().findAll { !it.type.required }
    }
    
    /**
     * Check if pipeline is complete
     */
    boolean isPipelineComplete() {
        def requiredComponents = getRequiredComponents()
        return requiredComponents.every { it.status in [ComponentStatus.COMPLETED, ComponentStatus.SKIPPED] }
    }
    
    /**
     * Check if pipeline has failed
     */
    boolean isPipelineFailed() {
        def requiredComponents = getRequiredComponents()
        return requiredComponents.any { it.status == ComponentStatus.FAILED }
    }
    
    /**
     * Get pipeline success rate
     */
    double getSuccessRate() {
        def totalComponents = components.size()
        def successfulComponents = components.values().count { it.status == ComponentStatus.COMPLETED }
        return totalComponents > 0 ? (successfulComponents / totalComponents * 100).round(1) : 0
    }
    
    /**
     * Get required components success rate
     */
    double getRequiredSuccessRate() {
        def requiredComponents = getRequiredComponents()
        def successfulRequired = requiredComponents.count { it.status == ComponentStatus.COMPLETED }
        return requiredComponents.size() > 0 ? (successfulRequired / requiredComponents.size() * 100).round(1) : 0
    }
    
    /**
     * Finalize pipeline tracking
     */
    void finalizePipeline() {
        this.pipelineEndTime = new Date()
    }
    
    /**
     * Get pipeline duration
     */
    String getPipelineDuration() {
        if (!pipelineStartTime) return "N/A"
        
        def endTime = pipelineEndTime ?: new Date()
        def duration = endTime.time - pipelineStartTime.time
        
        long seconds = duration / 1000
        long minutes = seconds / 60
        long hours = minutes / 60
        
        if (hours > 0) {
            return "${hours}h ${minutes % 60}m ${seconds % 60}s"
        } else if (minutes > 0) {
            return "${minutes}m ${seconds % 60}s"
        } else {
            return "${seconds}s"
        }
    }
    
    /**
     * Add pipeline metadata
     */
    void addPipelineMetadata(String key, Object value) {
        this.pipelineMetadata[key] = value
    }
    
    /**
     * Add pipeline metadata
     */
    void addPipelineMetadata(Map<String, Object> metadata) {
        this.pipelineMetadata.putAll(metadata)
    }
    
    /**
     * Generate status summary
     */
    Map generateStatusSummary() {
        def summary = [
            pipelineId: pipelineId,
            startTime: pipelineStartTime?.format('yyyy-MM-dd HH:mm:ss'),
            endTime: pipelineEndTime?.format('yyyy-MM-dd HH:mm:ss'),
            duration: getPipelineDuration(),
            isComplete: isPipelineComplete(),
            isFailed: isPipelineFailed(),
            successRate: getSuccessRate(),
            requiredSuccessRate: getRequiredSuccessRate(),
            metadata: pipelineMetadata
        ]
        
        // Component statistics
        def statusCounts = [:]
        ComponentStatus.values().each { status ->
            statusCounts[status.name()] = components.values().count { it.status == status }
        }
        summary.statusCounts = statusCounts
        
        // Required vs optional breakdown
        def requiredComponents = getRequiredComponents()
        def optionalComponents = getOptionalComponents()
        
        summary.requiredComponents = [
            total: requiredComponents.size(),
            completed: requiredComponents.count { it.status == ComponentStatus.COMPLETED },
            failed: requiredComponents.count { it.status == ComponentStatus.FAILED },
            skipped: requiredComponents.count { it.status == ComponentStatus.SKIPPED }
        ]
        
        summary.optionalComponents = [
            total: optionalComponents.size(),
            completed: optionalComponents.count { it.status == ComponentStatus.COMPLETED },
            failed: optionalComponents.count { it.status == ComponentStatus.FAILED },
            skipped: optionalComponents.count { it.status == ComponentStatus.SKIPPED }
        ]
        
        return summary
    }
    
    /**
     * Generate detailed status report
     */
    Map generateDetailedReport() {
        def report = generateStatusSummary()
        
        // Add detailed component information
        report.components = [:]
        components.each { componentId, component ->
            report.components[componentId] = component.toMap()
        }
        
        // Add timeline information
        report.timeline = generateTimeline()
        
        // Add performance metrics
        report.performance = generatePerformanceMetrics()
        
        return report
    }
    
    /**
     * Generate execution timeline
     */
    List generateTimeline() {
        def timeline = []
        
        components.values().each { component ->
            if (component.startTime) {
                timeline << [
                    timestamp: component.startTime.format('yyyy-MM-dd HH:mm:ss'),
                    event: 'started',
                    component: component.type.displayName,
                    componentId: component.processName
                ]
            }
            
            if (component.endTime) {
                timeline << [
                    timestamp: component.endTime.format('yyyy-MM-dd HH:mm:ss'),
                    event: component.status.label.toLowerCase(),
                    component: component.type.displayName,
                    componentId: component.processName,
                    duration: component.getFormattedDuration()
                ]
            }
        }
        
        return timeline.sort { it.timestamp }
    }
    
    /**
     * Generate performance metrics
     */
    Map generatePerformanceMetrics() {
        def completedComponents = components.values().findAll { 
            it.status == ComponentStatus.COMPLETED && it.duration != null 
        }
        
        if (completedComponents.isEmpty()) {
            return [
                averageDuration: 0,
                totalDuration: 0,
                fastestComponent: null,
                slowestComponent: null
            ]
        }
        
        def durations = completedComponents.collect { it.duration }
        def totalDuration = durations.sum()
        def averageDuration = totalDuration / durations.size()
        
        def fastestComponent = completedComponents.min { it.duration }
        def slowestComponent = completedComponents.max { it.duration }
        
        return [
            averageDuration: (averageDuration / 1000).round(1), // in seconds
            totalDuration: (totalDuration / 1000).round(1), // in seconds
            fastestComponent: [
                name: fastestComponent.type.displayName,
                duration: fastestComponent.getFormattedDuration()
            ],
            slowestComponent: [
                name: slowestComponent.type.displayName,
                duration: slowestComponent.getFormattedDuration()
            ]
        ]
    }
    
    /**
     * Export status to JSON file
     */
    void exportToJson(String filePath) {
        def report = generateDetailedReport()
        def json = new groovy.json.JsonBuilder(report)
        
        new File(filePath).text = json.toPrettyString()
    }
    
    /**
     * Export summary to text file
     */
    void exportSummaryToText(String filePath) {
        def summary = generateStatusSummary()
        def text = new StringBuilder()
        
        text << "MetaNextViro Pipeline Status Summary\n"
        text << "===================================\n\n"
        text << "Pipeline ID: ${summary.pipelineId}\n"
        text << "Start Time: ${summary.startTime}\n"
        text << "End Time: ${summary.endTime ?: 'Running'}\n"
        text << "Duration: ${summary.duration}\n"
        text << "Status: ${summary.isComplete ? 'Complete' : summary.isFailed ? 'Failed' : 'Running'}\n"
        text << "Success Rate: ${summary.successRate}%\n"
        text << "Required Success Rate: ${summary.requiredSuccessRate}%\n\n"
        
        text << "Component Status Counts:\n"
        summary.statusCounts.each { status, count ->
            if (count > 0) {
                text << "  ${status}: ${count}\n"
            }
        }
        
        text << "\nRequired Components: ${summary.requiredComponents.completed}/${summary.requiredComponents.total} completed\n"
        text << "Optional Components: ${summary.optionalComponents.completed}/${summary.optionalComponents.total} completed\n"
        
        new File(filePath).text = text.toString()
    }
}

/**
 * Global status tracker instance
 */
class StatusTrackerManager {
    private static PipelineStatusTracker instance
    
    static PipelineStatusTracker getInstance(String pipelineId = null) {
        if (!instance) {
            instance = new PipelineStatusTracker(pipelineId)
        }
        return instance
    }
    
    static void reset(String pipelineId = null) {
        instance = new PipelineStatusTracker(pipelineId)
    }
}