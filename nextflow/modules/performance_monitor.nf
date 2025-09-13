/*
 * Performance Monitoring Module
 * Collects resource usage statistics and performance metrics during pipeline execution
 */

process performance_monitor {
    tag "$sample_id"
    label 'process_quick'
    
    publishDir "${params.outdir}/performance", mode: 'copy'
    
    input:
    tuple val(sample_id), path(input_files)
    val process_name
    val start_time
    
    output:
    tuple val(sample_id), path("${sample_id}_${process_name}_performance.json"), emit: performance_stats
    tuple val(sample_id), path("${sample_id}_${process_name}_resources.log"), emit: resource_log
    
    script:
    """
    #!/bin/bash
    
    # Initialize performance monitoring
    MONITOR_PID=\$\$
    PROCESS_NAME="${process_name}"
    SAMPLE_ID="${sample_id}"
    START_TIME="${start_time}"
    END_TIME=\$(date +%s)
    
    # Create performance statistics file
    cat > ${sample_id}_${process_name}_performance.json << EOF
{
    "sample_id": "\${SAMPLE_ID}",
    "process_name": "\${PROCESS_NAME}",
    "start_time": \${START_TIME},
    "end_time": \${END_TIME},
    "duration": \$((END_TIME - START_TIME)),
    "input_files": [
EOF
    
    # Add input file information
    first_file=true
    for file in ${input_files}; do
        if [ "\$first_file" = true ]; then
            first_file=false
        else
            echo "," >> ${sample_id}_${process_name}_performance.json
        fi
        
        if [ -f "\$file" ]; then
            file_size=\$(stat -f%z "\$file" 2>/dev/null || stat -c%s "\$file" 2>/dev/null || echo "0")
            echo "        {\"path\": \"\$file\", \"size\": \$file_size}" >> ${sample_id}_${process_name}_performance.json
        fi
    done
    
    cat >> ${sample_id}_${process_name}_performance.json << EOF
    ],
    "system_info": {
        "hostname": "\$(hostname)",
        "cpu_count": \$(nproc),
        "memory_total": \$(free -b | awk '/^Mem:/{print \$2}'),
        "load_average": "\$(uptime | awk -F'load average:' '{print \$2}')"
    },
    "resource_usage": {
        "max_memory_kb": \$(cat /proc/\$\$/status | grep VmHWM | awk '{print \$2}'),
        "cpu_time": \$(ps -o cputime= -p \$\$ | tr -d ' '),
        "io_read": \$(cat /proc/\$\$/io 2>/dev/null | grep read_bytes | awk '{print \$2}' || echo "0"),
        "io_write": \$(cat /proc/\$\$/io 2>/dev/null | grep write_bytes | awk '{print \$2}' || echo "0")
    }
}
EOF
    
    # Create detailed resource log
    cat > ${sample_id}_${process_name}_resources.log << EOF
# Performance monitoring log for \${SAMPLE_ID} - \${PROCESS_NAME}
# Generated at: \$(date)
# Duration: \$((END_TIME - START_TIME)) seconds

## System Information
Hostname: \$(hostname)
CPU Count: \$(nproc)
Memory Total: \$(free -h | awk '/^Mem:/{print \$2}')
Load Average: \$(uptime | awk -F'load average:' '{print \$2}')

## Process Resource Usage
Max Memory (RSS): \$(cat /proc/\$\$/status | grep VmHWM | awk '{print \$2 " " \$3}')
CPU Time: \$(ps -o cputime= -p \$\$ | tr -d ' ')
I/O Read: \$(cat /proc/\$\$/io 2>/dev/null | grep read_bytes | awk '{print \$2}' || echo "0") bytes
I/O Write: \$(cat /proc/\$\$/io 2>/dev/null | grep write_bytes | awk '{print \$2}' || echo "0") bytes

## Input File Statistics
EOF
    
    for file in ${input_files}; do
        if [ -f "\$file" ]; then
            echo "File: \$file" >> ${sample_id}_${process_name}_resources.log
            echo "  Size: \$(ls -lh "\$file" | awk '{print \$5}')" >> ${sample_id}_${process_name}_resources.log
            echo "  Modified: \$(ls -l "\$file" | awk '{print \$6, \$7, \$8}')" >> ${sample_id}_${process_name}_resources.log
            echo "" >> ${sample_id}_${process_name}_resources.log
        fi
    done
    
    # Add disk usage information
    echo "## Disk Usage" >> ${sample_id}_${process_name}_resources.log
    df -h . >> ${sample_id}_${process_name}_resources.log
    
    echo "Performance monitoring completed for \${SAMPLE_ID} - \${PROCESS_NAME}"
    """
}

process collect_performance_stats {
    label 'process_low'
    
    publishDir "${params.outdir}/performance", mode: 'copy'
    
    input:
    path performance_files
    
    output:
    path "pipeline_performance_summary.json", emit: summary
    path "performance_analysis.html", emit: report
    
    script:
    """
    #!/usr/bin/env python3
    
    import json
    import os
    import glob
    from datetime import datetime
    import statistics
    
    # Collect all performance files
    performance_files = glob.glob("*_performance.json")
    
    all_stats = []
    for file in performance_files:
        try:
            with open(file, 'r') as f:
                stats = json.load(f)
                all_stats.append(stats)
        except Exception as e:
            print(f"Error reading {file}: {e}")
    
    # Calculate summary statistics
    summary = {
        "pipeline_summary": {
            "total_processes": len(all_stats),
            "total_samples": len(set(stat["sample_id"] for stat in all_stats)),
            "total_duration": sum(stat["duration"] for stat in all_stats),
            "start_time": min(stat["start_time"] for stat in all_stats) if all_stats else 0,
            "end_time": max(stat["end_time"] for stat in all_stats) if all_stats else 0
        },
        "resource_summary": {
            "total_memory_usage": sum(stat["resource_usage"]["max_memory_kb"] for stat in all_stats),
            "avg_memory_per_process": statistics.mean(stat["resource_usage"]["max_memory_kb"] for stat in all_stats) if all_stats else 0,
            "total_io_read": sum(int(stat["resource_usage"]["io_read"]) for stat in all_stats),
            "total_io_write": sum(int(stat["resource_usage"]["io_write"]) for stat in all_stats)
        },
        "process_breakdown": {}
    }
    
    # Process-specific statistics
    process_groups = {}
    for stat in all_stats:
        process_name = stat["process_name"]
        if process_name not in process_groups:
            process_groups[process_name] = []
        process_groups[process_name].append(stat)
    
    for process_name, process_stats in process_groups.items():
        summary["process_breakdown"][process_name] = {
            "count": len(process_stats),
            "avg_duration": statistics.mean(stat["duration"] for stat in process_stats),
            "max_duration": max(stat["duration"] for stat in process_stats),
            "min_duration": min(stat["duration"] for stat in process_stats),
            "avg_memory": statistics.mean(stat["resource_usage"]["max_memory_kb"] for stat in process_stats),
            "max_memory": max(stat["resource_usage"]["max_memory_kb"] for stat in process_stats)
        }
    
    # Save summary
    with open("pipeline_performance_summary.json", "w") as f:
        json.dump(summary, f, indent=2)
    
    # Generate HTML report
    html_content = f'''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Pipeline Performance Analysis</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 20px; }}
            .summary {{ background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 10px 0; }}
            .process {{ margin: 10px 0; padding: 10px; border: 1px solid #ddd; }}
            .metric {{ display: inline-block; margin: 5px 10px; }}
            table {{ border-collapse: collapse; width: 100%; }}
            th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
            th {{ background-color: #f2f2f2; }}
        </style>
    </head>
    <body>
        <h1>Pipeline Performance Analysis</h1>
        <p>Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
        
        <div class="summary">
            <h2>Pipeline Summary</h2>
            <div class="metric"><strong>Total Processes:</strong> {summary["pipeline_summary"]["total_processes"]}</div>
            <div class="metric"><strong>Total Samples:</strong> {summary["pipeline_summary"]["total_samples"]}</div>
            <div class="metric"><strong>Total Duration:</strong> {summary["pipeline_summary"]["total_duration"]} seconds</div>
            <div class="metric"><strong>Avg Memory per Process:</strong> {summary["resource_summary"]["avg_memory_per_process"]:.1f} KB</div>
        </div>
        
        <h2>Process Performance Breakdown</h2>
        <table>
            <tr>
                <th>Process Name</th>
                <th>Count</th>
                <th>Avg Duration (s)</th>
                <th>Max Duration (s)</th>
                <th>Avg Memory (KB)</th>
                <th>Max Memory (KB)</th>
            </tr>
    '''
    
    for process_name, stats in summary["process_breakdown"].items():
        html_content += f'''
            <tr>
                <td>{process_name}</td>
                <td>{stats["count"]}</td>
                <td>{stats["avg_duration"]:.1f}</td>
                <td>{stats["max_duration"]}</td>
                <td>{stats["avg_memory"]:.1f}</td>
                <td>{stats["max_memory"]}</td>
            </tr>
        '''
    
    html_content += '''
        </table>
        
        <h2>Resource Usage Details</h2>
        <div class="summary">
    '''
    
    html_content += f'''
            <div class="metric"><strong>Total Memory Usage:</strong> {summary["resource_summary"]["total_memory_usage"]} KB</div>
            <div class="metric"><strong>Total I/O Read:</strong> {summary["resource_summary"]["total_io_read"]} bytes</div>
            <div class="metric"><strong>Total I/O Write:</strong> {summary["resource_summary"]["total_io_write"]} bytes</div>
        </div>
    </body>
    </html>
    '''
    
    with open("performance_analysis.html", "w") as f:
        f.write(html_content)
    
    print("Performance analysis completed")
    """
}

process generate_optimization_report {
    label 'process_low'
    
    publishDir "${params.outdir}/performance", mode: 'copy'
    
    input:
    path performance_summary
    path input_characteristics
    
    output:
    path "optimization_recommendations.json", emit: recommendations
    path "optimization_report.html", emit: report
    
    script:
    """
    #!/usr/bin/env python3
    
    import json
    import os
    from datetime import datetime
    
    # Load performance data
    with open("${performance_summary}", "r") as f:
        performance_data = json.load(f)
    
    # Generate optimization recommendations
    recommendations = {
        "analysis_date": datetime.now().isoformat(),
        "pipeline_efficiency": {},
        "resource_recommendations": [],
        "parallelization_recommendations": [],
        "configuration_recommendations": []
    }
    
    # Analyze pipeline efficiency
    total_duration = performance_data["pipeline_summary"]["total_duration"]
    total_processes = performance_data["pipeline_summary"]["total_processes"]
    
    if total_processes > 0:
        avg_process_time = total_duration / total_processes
        recommendations["pipeline_efficiency"] = {
            "avg_process_duration": avg_process_time,
            "efficiency_score": min(100, max(0, 100 - (avg_process_time / 60) * 10)),
            "bottleneck_processes": []
        }
    
    # Identify bottleneck processes
    for process_name, stats in performance_data["process_breakdown"].items():
        if stats["max_duration"] > avg_process_time * 2:
            recommendations["pipeline_efficiency"]["bottleneck_processes"].append({
                "process": process_name,
                "max_duration": stats["max_duration"],
                "avg_duration": stats["avg_duration"],
                "impact": "high" if stats["max_duration"] > avg_process_time * 3 else "medium"
            })
    
    # Resource optimization recommendations
    for process_name, stats in performance_data["process_breakdown"].items():
        # Memory recommendations
        if stats["max_memory"] > stats["avg_memory"] * 2:
            recommendations["resource_recommendations"].append({
                "type": "memory",
                "process": process_name,
                "issue": "High memory variance detected",
                "recommendation": f"Consider increasing base memory allocation to {stats['max_memory'] * 1.1:.0f} KB",
                "priority": "medium"
            })
        
        # Duration recommendations
        if stats["max_duration"] > stats["avg_duration"] * 3:
            recommendations["resource_recommendations"].append({
                "type": "time",
                "process": process_name,
                "issue": "High execution time variance",
                "recommendation": f"Consider increasing time limit or optimizing process",
                "priority": "high" if stats["max_duration"] > 3600 else "medium"
            })
    
    # Parallelization recommendations
    sample_count = performance_data["pipeline_summary"]["total_samples"]
    if sample_count > 1:
        for process_name, stats in performance_data["process_breakdown"].items():
            if stats["count"] == sample_count and stats["avg_duration"] > 300:  # 5 minutes
                recommendations["parallelization_recommendations"].append({
                    "process": process_name,
                    "current_parallelization": "sequential",
                    "recommendation": "Enable parallel processing for multiple samples",
                    "estimated_improvement": f"{min(50, sample_count * 10)}% time reduction",
                    "priority": "high"
                })
    
    # Configuration recommendations
    total_memory = performance_data["resource_summary"]["total_memory_usage"]
    if total_memory > 100 * 1024 * 1024:  # > 100GB
        recommendations["configuration_recommendations"].append({
            "type": "profile",
            "recommendation": "Consider using 'large_hpc' profile for better resource allocation",
            "reason": f"High total memory usage detected: {total_memory / (1024*1024):.1f} GB",
            "priority": "medium"
        })
    
    # Save recommendations
    with open("optimization_recommendations.json", "w") as f:
        json.dump(recommendations, f, indent=2)
    
    # Generate HTML report
    html_content = f'''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Pipeline Optimization Report</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 20px; }}
            .recommendation {{ margin: 10px 0; padding: 15px; border-left: 4px solid #007cba; background: #f9f9f9; }}
            .high-priority {{ border-left-color: #d32f2f; }}
            .medium-priority {{ border-left-color: #f57c00; }}
            .low-priority {{ border-left-color: #388e3c; }}
            .efficiency-score {{ font-size: 24px; font-weight: bold; color: #007cba; }}
            table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
            th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
            th {{ background-color: #f2f2f2; }}
        </style>
    </head>
    <body>
        <h1>Pipeline Optimization Report</h1>
        <p>Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
        
        <h2>Pipeline Efficiency Analysis</h2>
        <div class="recommendation">
            <div class="efficiency-score">Efficiency Score: {recommendations["pipeline_efficiency"].get("efficiency_score", 0):.1f}/100</div>
            <p>Average Process Duration: {recommendations["pipeline_efficiency"].get("avg_process_duration", 0):.1f} seconds</p>
        </div>
    '''
    
    # Bottleneck processes
    if recommendations["pipeline_efficiency"].get("bottleneck_processes"):
        html_content += '''
        <h3>Bottleneck Processes</h3>
        <table>
            <tr><th>Process</th><th>Max Duration (s)</th><th>Avg Duration (s)</th><th>Impact</th></tr>
        '''
        for bottleneck in recommendations["pipeline_efficiency"]["bottleneck_processes"]:
            html_content += f'''
            <tr>
                <td>{bottleneck["process"]}</td>
                <td>{bottleneck["max_duration"]}</td>
                <td>{bottleneck["avg_duration"]:.1f}</td>
                <td>{bottleneck["impact"]}</td>
            </tr>
            '''
        html_content += '</table>'
    
    # Resource recommendations
    if recommendations["resource_recommendations"]:
        html_content += '<h2>Resource Optimization Recommendations</h2>'
        for rec in recommendations["resource_recommendations"]:
            priority_class = f"{rec['priority']}-priority"
            html_content += f'''
            <div class="recommendation {priority_class}">
                <h4>{rec["type"].title()} Optimization - {rec["process"]}</h4>
                <p><strong>Issue:</strong> {rec["issue"]}</p>
                <p><strong>Recommendation:</strong> {rec["recommendation"]}</p>
                <p><strong>Priority:</strong> {rec["priority"].title()}</p>
            </div>
            '''
    
    # Parallelization recommendations
    if recommendations["parallelization_recommendations"]:
        html_content += '<h2>Parallelization Recommendations</h2>'
        for rec in recommendations["parallelization_recommendations"]:
            priority_class = f"{rec['priority']}-priority"
            html_content += f'''
            <div class="recommendation {priority_class}">
                <h4>Parallelization - {rec["process"]}</h4>
                <p><strong>Current:</strong> {rec["current_parallelization"]}</p>
                <p><strong>Recommendation:</strong> {rec["recommendation"]}</p>
                <p><strong>Estimated Improvement:</strong> {rec["estimated_improvement"]}</p>
                <p><strong>Priority:</strong> {rec["priority"].title()}</p>
            </div>
            '''
    
    # Configuration recommendations
    if recommendations["configuration_recommendations"]:
        html_content += '<h2>Configuration Recommendations</h2>'
        for rec in recommendations["configuration_recommendations"]:
            priority_class = f"{rec['priority']}-priority"
            html_content += f'''
            <div class="recommendation {priority_class}">
                <h4>{rec["type"].title()} Configuration</h4>
                <p><strong>Recommendation:</strong> {rec["recommendation"]}</p>
                <p><strong>Reason:</strong> {rec["reason"]}</p>
                <p><strong>Priority:</strong> {rec["priority"].title()}</p>
            </div>
            '''
    
    html_content += '''
    </body>
    </html>
    '''
    
    with open("optimization_report.html", "w") as f:
        f.write(html_content)
    
    print("Optimization report generated successfully")
    """
}