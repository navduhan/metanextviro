/**
 * Error Tracking and Recovery Subworkflow
 * 
 * This subworkflow provides centralized error tracking, recovery strategies,
 * and graceful degradation for the MetaNextViro pipeline.
 */

include { enhanced_final_report } from '../modules/enhanced_final_report'

/**
 * Error tracking and recovery workflow
 */
workflow ERROR_TRACKING {
    take:
        process_outputs    // Channel of all process outputs
        process_failures   // Channel of process failure information
        
    main:
        // Initialize error handler
        error_handler = new EnhancedErrorHandler()
        
        // Collect process status information
        process_status = process_outputs
            .map { output ->
                [
                    process: output.process_name ?: 'unknown',
                    status: output.status ?: 'completed',
                    timestamp: new Date(),
                    outputs: output.files ?: [],
                    metadata: output.metadata ?: [:]
                ]
            }
            .collect()
        
        // Collect failure information
        failure_data = process_failures
            .map { failure ->
                [
                    process: failure.process_name,
                    error: failure.error_message,
                    severity: failure.severity ?: 'ERROR',
                    timestamp: failure.timestamp ?: new Date(),
                    context: failure.context ?: [:],
                    recoverable: failure.recoverable ?: false
                ]
            }
            .collect()
        
        // Generate error tracking report
        error_report = generateErrorReport(process_status, failure_data)
        
    emit:
        error_report
        process_status
        failure_data
}

/**
 * Enhanced error handling for individual processes
 */
workflow PROCESS_ERROR_HANDLER {
    take:
        process_name
        process_output
        error_info
        
    main:
        // Handle process-specific errors
        handled_error = handleProcessError(process_name, process_output, error_info)
        
        // Determine recovery action
        recovery_action = determineRecoveryAction(handled_error)
        
        // Apply graceful degradation if needed
        degraded_output = applyGracefulDegradation(process_name, process_output, handled_error)
        
    emit:
        handled_error
        recovery_action
        degraded_output
}

/**
 * Graceful degradation for optional processes
 */
workflow GRACEFUL_DEGRADATION {
    take:
        all_outputs
        failed_processes
        
    main:
        // Define optional processes that can be skipped
        optional_processes = Channel.of([
            'CHECKV', 'VIRFINDER', 'COVERAGE_PLOT', 'HEATMAP', 
            'KRONA', 'HTML_REPORT', 'MULTIQC'
        ])
        
        // Filter outputs to exclude failed optional processes
        filtered_outputs = all_outputs
            .filter { output ->
                def process_name = output.process_name
                def is_failed = failed_processes.any { it.process_name == process_name }
                def is_optional = optional_processes.any { it == process_name }
                
                // Include if not failed, or if failed but not optional
                return !is_failed || !is_optional
            }
        
        // Generate placeholder outputs for skipped optional processes
        placeholder_outputs = failed_processes
            .filter { failure ->
                optional_processes.any { it == failure.process_name }
            }
            .map { failure ->
                [
                    process_name: failure.process_name,
                    status: 'skipped',
                    reason: 'Optional process failed and was skipped',
                    files: [],
                    metadata: [skipped: true, reason: failure.error_message]
                ]
            }
        
        // Combine filtered outputs with placeholders
        final_outputs = filtered_outputs.mix(placeholder_outputs)
        
    emit:
        final_outputs
}

/**
 * Process for generating error tracking report
 */
process generateErrorReport {
    label 'process_low'
    publishDir "${params.outdir}/error_tracking", mode: 'copy'
    
    input:
        val process_status
        val failure_data
        
    output:
        path "error_report.json", emit: json
        path "error_summary.txt", emit: summary
        
    script:
    """
    #!/usr/bin/env python3
    
    import json
    import datetime
    
    # Process status data
    process_status = ${process_status}
    failure_data = ${failure_data}
    
    # Generate error report
    error_report = {
        'metadata': {
            'generated_at': datetime.datetime.now().isoformat(),
            'pipeline': 'MetaNextViro',
            'report_type': 'Error Tracking Report'
        },
        'summary': {
            'total_processes': len(process_status),
            'successful_processes': len([p for p in process_status if p['status'] == 'completed']),
            'failed_processes': len(failure_data),
            'success_rate': 0
        },
        'process_status': process_status,
        'failures': failure_data,
        'recommendations': []
    }
    
    # Calculate success rate
    if error_report['summary']['total_processes'] > 0:
        error_report['summary']['success_rate'] = (
            error_report['summary']['successful_processes'] / 
            error_report['summary']['total_processes'] * 100
        )
    
    # Generate recommendations based on failures
    recommendations = []
    
    for failure in failure_data:
        if 'memory' in failure['error'].lower():
            recommendations.append({
                'type': 'resource',
                'message': f"Consider increasing memory allocation for {failure['process']}",
                'action': 'Modify resource configuration in nextflow.config'
            })
        elif 'time' in failure['error'].lower():
            recommendations.append({
                'type': 'resource',
                'message': f"Consider increasing time limit for {failure['process']}",
                'action': 'Modify time configuration in nextflow.config'
            })
        elif 'database' in failure['error'].lower():
            recommendations.append({
                'type': 'database',
                'message': f"Check database configuration for {failure['process']}",
                'action': 'Verify database paths and accessibility'
            })
    
    error_report['recommendations'] = recommendations
    
    # Write JSON report
    with open('error_report.json', 'w') as f:
        json.dump(error_report, f, indent=2)
    
    # Write text summary
    with open('error_summary.txt', 'w') as f:
        f.write("MetaNextViro Pipeline Error Summary\\n")
        f.write("=" * 40 + "\\n\\n")
        f.write(f"Generated: {error_report['metadata']['generated_at']}\\n")
        f.write(f"Total Processes: {error_report['summary']['total_processes']}\\n")
        f.write(f"Successful: {error_report['summary']['successful_processes']}\\n")
        f.write(f"Failed: {error_report['summary']['failed_processes']}\\n")
        f.write(f"Success Rate: {error_report['summary']['success_rate']:.1f}%\\n\\n")
        
        if failure_data:
            f.write("FAILURES:\\n")
            f.write("-" * 20 + "\\n")
            for failure in failure_data:
                f.write(f"Process: {failure['process']}\\n")
                f.write(f"Error: {failure['error']}\\n")
                f.write(f"Severity: {failure['severity']}\\n")
                f.write(f"Timestamp: {failure['timestamp']}\\n")
                if failure.get('recoverable'):
                    f.write("Status: Potentially recoverable\\n")
                f.write("\\n")
        
        if recommendations:
            f.write("RECOMMENDATIONS:\\n")
            f.write("-" * 20 + "\\n")
            for rec in recommendations:
                f.write(f"Type: {rec['type']}\\n")
                f.write(f"Message: {rec['message']}\\n")
                f.write(f"Action: {rec['action']}\\n\\n")
    
    print("✅ Error tracking report generated")
    """
}

/**
 * Process for handling individual process errors
 */
process handleProcessError {
    label 'process_low'
    
    input:
        val process_name
        val process_output
        val error_info
        
    output:
        val handled_error
        
    script:
    """
    #!/usr/bin/env python3
    
    import json
    
    process_name = "${process_name}"
    error_info = ${error_info}
    
    # Initialize error handler response
    handled_error = {
        'process': process_name,
        'original_error': error_info,
        'handled': False,
        'recovery_attempted': False,
        'recovery_successful': False,
        'degraded': False,
        'action': 'none',
        'message': ''
    }
    
    # Check if error is recoverable
    error_message = error_info.get('message', '').lower()
    
    if 'memory' in error_message or 'out of memory' in error_message:
        handled_error.update({
            'handled': True,
            'recovery_attempted': True,
            'action': 'increase_memory',
            'message': 'Memory error detected - recommend increasing memory allocation'
        })
    elif 'time' in error_message or 'timeout' in error_message:
        handled_error.update({
            'handled': True,
            'recovery_attempted': True,
            'action': 'increase_time',
            'message': 'Time limit error detected - recommend increasing time allocation'
        })
    elif 'database' in error_message or 'not found' in error_message:
        handled_error.update({
            'handled': True,
            'recovery_attempted': True,
            'action': 'check_database',
            'message': 'Database access error detected - check database configuration'
        })
    else:
        # Check if process can be gracefully degraded
        optional_processes = ['CHECKV', 'VIRFINDER', 'COVERAGE_PLOT', 'HEATMAP', 'KRONA']
        if process_name in optional_processes:
            handled_error.update({
                'handled': True,
                'degraded': True,
                'action': 'skip_optional',
                'message': f'Optional process {process_name} failed - continuing without it'
            })
    
    # Output the handled error information
    print(json.dumps(handled_error))
    """
}

/**
 * Process for determining recovery actions
 */
process determineRecoveryAction {
    label 'process_low'
    
    input:
        val handled_error
        
    output:
        val recovery_action
        
    script:
    """
    #!/usr/bin/env python3
    
    import json
    
    handled_error = ${handled_error}
    
    recovery_action = {
        'process': handled_error['process'],
        'recommended_action': 'none',
        'parameters': {},
        'retry_suggested': False,
        'manual_intervention': False
    }
    
    action = handled_error.get('action', 'none')
    
    if action == 'increase_memory':
        recovery_action.update({
            'recommended_action': 'retry_with_more_memory',
            'parameters': {'memory_multiplier': 2},
            'retry_suggested': True
        })
    elif action == 'increase_time':
        recovery_action.update({
            'recommended_action': 'retry_with_more_time',
            'parameters': {'time_multiplier': 2},
            'retry_suggested': True
        })
    elif action == 'check_database':
        recovery_action.update({
            'recommended_action': 'verify_database_config',
            'manual_intervention': True
        })
    elif action == 'skip_optional':
        recovery_action.update({
            'recommended_action': 'continue_without_process',
            'retry_suggested': False
        })
    
    print(json.dumps(recovery_action))
    """
}

/**
 * Process for applying graceful degradation
 */
process applyGracefulDegradation {
    label 'process_low'
    
    input:
        val process_name
        val process_output
        val handled_error
        
    output:
        val degraded_output
        
    script:
    """
    #!/usr/bin/env python3
    
    import json
    
    process_name = "${process_name}"
    handled_error = ${handled_error}
    
    degraded_output = {
        'process': process_name,
        'status': 'completed',
        'files': [],
        'metadata': {}
    }
    
    if handled_error.get('degraded', False):
        degraded_output.update({
            'status': 'skipped',
            'reason': 'Process failed and was gracefully degraded',
            'original_error': handled_error['original_error'],
            'metadata': {
                'degraded': True,
                'optional': True,
                'error_handled': True
            }
        })
    else:
        # Process completed normally or needs manual intervention
        degraded_output.update({
            'status': 'failed' if not handled_error['handled'] else 'needs_retry',
            'metadata': {
                'error_handled': handled_error['handled'],
                'recovery_suggested': handled_error.get('recovery_attempted', False)
            }
        })
    
    print(json.dumps(degraded_output))
    """
}