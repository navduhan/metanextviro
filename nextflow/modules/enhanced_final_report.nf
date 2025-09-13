// Author: Naveen Duhan

// Enhanced final comprehensive HTML report with error handling and graceful degradation
process enhanced_final_report {
    label 'process_medium'  // Assign a label for resource management

    // Resource hints for partition selection
    ext.memory_intensive = false
    ext.gpu_accelerated = false
    ext.quick_job = false
    ext.preferred_partition = null

    publishDir "${params.outdir}/final_report", mode: 'copy', overwrite: true
    
    // Allow process to continue even if some inputs are missing
    errorStrategy 'ignore'

    input:
        path kraken2_reports, stageAs: 'kraken2/*'
        path fastqc_reports, stageAs: 'fastqc/*'
        path coverage_stats, stageAs: 'coverage/*'
        path checkv_results, stageAs: 'checkv/*'
        path virfinder_full, stageAs: 'virfinder_full/*'
        path virfinder_filtered, stageAs: 'virfinder_filtered/*'
        path blast_results, stageAs: 'blast/*'
        path assembly_results, stageAs: 'assembly/*'
        path megahit_logs, stageAs: 'megahit_logs/*'
        path megahit_params, stageAs: 'megahit_params/*'
        path megahit_raw_contigs, stageAs: 'megahit_contigs/*'
        path metaspades_logs, stageAs: 'metaspades_logs/*'
        path metaspades_params, stageAs: 'metaspades_params/*'
        path metaspades_raw_scaffolds, stageAs: 'metaspades_scaffolds/*'
        path hybrid_merged, stageAs: 'hybrid_merged/*'
        path hybrid_cdhit, stageAs: 'hybrid_cdhit/*'
        path hybrid_cdhit_clstr, stageAs: 'hybrid_clstr/*'
        path organized_dirs, stageAs: 'organized/*'
        path process_failures, stageAs: 'failures/*'

    output:
        path "enhanced_final_report.html", emit: report
        path "report_data.json", emit: data
        path "process_status.json", emit: status

    script:
    """
    #!/usr/bin/env python3
    
    import os
    import json
    import datetime
    from pathlib import Path
    import glob
    
    def collect_files(directory, extensions=None):
        \"\"\"Collect files from directory with optional extension filtering\"\"\"
        files = []
        if not os.path.exists(directory):
            return files
            
        for root, dirs, filenames in os.walk(directory):
            for filename in filenames:
                if extensions is None or any(filename.lower().endswith(ext.lower()) for ext in extensions):
                    filepath = os.path.join(root, filename)
                    try:
                        size = os.path.getsize(filepath)
                        files.append({
                            'name': filename,
                            'path': os.path.relpath(filepath),
                            'size': size,
                            'directory': os.path.basename(root)
                        })
                    except OSError:
                        # File might be inaccessible, skip it
                        continue
        return files
    
    def format_file_size(bytes_size):
        \"\"\"Format file size for human reading\"\"\"
        if bytes_size < 1024:
            return f"{bytes_size} B"
        elif bytes_size < 1024 * 1024:
            return f"{bytes_size / 1024:.1f} KB"
        elif bytes_size < 1024 * 1024 * 1024:
            return f"{bytes_size / (1024 * 1024):.1f} MB"
        else:
            return f"{bytes_size / (1024 * 1024 * 1024):.1f} GB"
    
    def generate_section(section_name, directory, extensions, required=True, description=""):
        \"\"\"Generate a report section with error handling\"\"\"
        section = {
            'name': section_name,
            'description': description,
            'required': required,
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'content': '',
            'error': None
        }
        
        try:
            files = collect_files(directory, extensions)
            section['files'] = files
            
            if not files and required:
                section['status'] = 'MISSING'
                section['error'] = f"No {section_name.lower()} files found"
                section['content'] = f"<div class='missing-section'><p>⚠️ No {section_name.lower()} results available.</p></div>"
            elif not files and not required:
                section['status'] = 'SKIPPED'
                section['content'] = f"<div class='skipped-section'><p>ℹ️ {section_name} analysis was not performed.</p><p>This is an optional analysis step.</p></div>"
            else:
                section['summary'] = {
                    'file_count': len(files),
                    'total_size': sum(f['size'] for f in files),
                    'directories': list(set(f['directory'] for f in files))
                }
                section['content'] = generate_section_html(section_name, files)
                
        except Exception as e:
            section['status'] = 'ERROR'
            section['error'] = str(e)
            if required:
                section['content'] = f"<div class='error-section'><h4>❌ Error in {section_name}</h4><p><strong>Error:</strong> {str(e)}</p><p><strong>Impact:</strong> This is a required section.</p></div>"
            else:
                section['status'] = 'SKIPPED'
                section['content'] = f"<div class='skipped-section'><h4>ℹ️ {section_name} - Skipped</h4><p><strong>Reason:</strong> {str(e)}</p><p>This is an optional analysis step.</p></div>"
        
        return section
    
    def generate_section_html(section_name, files):
        \"\"\"Generate HTML content for a section\"\"\"
        if not files:
            return "<p>No files available.</p>"
        
        html = f"<p><strong>Files generated:</strong> {len(files)}</p>"
        html += "<ul class='file-list'>"
        
        for file_info in files:
            size_str = format_file_size(file_info['size'])
            html += f"<li><a href='{file_info['path']}'>{file_info['name']}</a> <span class='file-size'>({size_str})</span></li>"
        
        html += "</ul>"
        return html
    
    def load_process_failures():
        \"\"\"Load process failure information if available\"\"\"
        failures = []
        try:
            failure_files = glob.glob('failures/*.json')
            for failure_file in failure_files:
                with open(failure_file, 'r') as f:
                    failure_data = json.load(f)
                    failures.extend(failure_data.get('failures', []))
        except Exception as e:
            print(f"Warning: Could not load failure data: {e}")
        
        return failures
    
    # Generate report data
    report_data = {
        'metadata': {
            'generated_at': datetime.datetime.now().isoformat(),
            'pipeline': 'MetaNextViro',
            'version': '1.0.0',
            'report_type': 'Enhanced Final Report'
        },
        'sections': {},
        'failures': load_process_failures(),
        'status': 'COMPLETED'
    }
    
    # Generate sections with error handling
    sections_config = [
        ('Quality Control', 'fastqc', ['html', 'zip'], True, 'FastQC quality assessment results'),
        ('Taxonomic Classification', 'kraken2', ['report', 'txt', 'kraken'], True, 'Kraken2 taxonomic profiling results'),
        ('Assembly Results', 'assembly', ['fa', 'fasta', 'log'], True, 'Genome assembly statistics and contigs'),
        ('Assembly Logs - MEGAHIT', 'megahit_logs', ['log', 'txt'], False, 'MEGAHIT assembler logs and statistics'),
        ('Assembly Logs - MetaSPAdes', 'metaspades_logs', ['log', 'txt'], False, 'MetaSPAdes assembler logs and statistics'),
        ('Viral Analysis - CheckV', 'checkv', ['tsv', 'txt'], False, 'CheckV viral genome quality assessment'),
        ('Viral Analysis - VirFinder', 'virfinder_full', ['tsv', 'txt', 'csv'], False, 'VirFinder viral sequence identification'),
        ('Viral Analysis - High Confidence', 'virfinder_filtered', ['tsv', 'txt', 'csv'], False, 'High-confidence viral sequences'),
        ('Functional Annotation', 'blast', ['txt', 'tsv', 'xml'], False, 'BLAST functional annotation results'),
        ('Coverage Analysis', 'coverage', ['txt', 'tsv', 'png', 'pdf'], False, 'Read coverage and depth analysis'),
        ('Organized Contigs', 'organized', ['fa', 'fasta'], False, 'Taxonomically organized contigs')
    ]
    
    for section_name, directory, extensions, required, description in sections_config:
        section_key = section_name.lower().replace(' ', '_').replace('-', '_')
        report_data['sections'][section_key] = generate_section(section_name, directory, extensions, required, description)
        
        # Update overall status based on section status
        if report_data['sections'][section_key]['status'] == 'ERROR' and required:
            report_data['status'] = 'PARTIAL'
        elif report_data['sections'][section_key]['status'] == 'MISSING' and required:
            report_data['status'] = 'PARTIAL'
    
    # Calculate summary statistics
    total_sections = len(report_data['sections'])
    successful_sections = sum(1 for s in report_data['sections'].values() if s['status'] == 'SUCCESS')
    failed_sections = sum(1 for s in report_data['sections'].values() if s['status'] == 'ERROR')
    missing_sections = sum(1 for s in report_data['sections'].values() if s['status'] == 'MISSING')
    skipped_sections = sum(1 for s in report_data['sections'].values() if s['status'] == 'SKIPPED')
    
    report_data['summary'] = {
        'total_sections': total_sections,
        'successful_sections': successful_sections,
        'failed_sections': failed_sections,
        'missing_sections': missing_sections,
        'skipped_sections': skipped_sections,
        'success_rate': round((successful_sections / total_sections * 100), 1) if total_sections > 0 else 0
    }
    
    # Determine final status
    if report_data['failures'] or failed_sections > 0:
        if successful_sections == 0:
            report_data['status'] = 'FAILED'
        else:
            report_data['status'] = 'PARTIAL'
    
    # Save report data as JSON
    with open('report_data.json', 'w') as f:
        json.dump(report_data, f, indent=2)
    
    # Generate process status summary
    process_status = {
        'summary': report_data['summary'],
        'section_statuses': {k: v['status'] for k, v in report_data['sections'].items()},
        'failures': report_data['failures'],
        'overall_status': report_data['status']
    }
    
    with open('process_status.json', 'w') as f:
        json.dump(process_status, f, indent=2)
    
    # Generate HTML report
    html_content = f'''<!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>MetaNextViro Enhanced Report</title>
        <style>
            body {{ 
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
                margin: 0; 
                padding: 20px; 
                line-height: 1.6; 
                background-color: #f5f7fa;
            }}
            .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
            h1 {{ color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 15px; margin-bottom: 30px; }}
            h2 {{ color: #34495e; margin-top: 40px; border-left: 4px solid #3498db; padding-left: 15px; }}
            h3 {{ color: #2c3e50; margin-top: 25px; }}
            .summary-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }}
            .summary-card {{ background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #3498db; }}
            .summary-card h4 {{ margin: 0 0 10px 0; color: #2c3e50; }}
            .summary-card .value {{ font-size: 2em; font-weight: bold; color: #3498db; }}
            .section {{ background: #f8f9fa; padding: 20px; margin: 20px 0; border-radius: 8px; }}
            .section.error {{ border-left: 4px solid #e74c3c; background: #fdf2f2; }}
            .section.warning {{ border-left: 4px solid #f39c12; background: #fef9e7; }}
            .section.success {{ border-left: 4px solid #27ae60; background: #f0f9f4; }}
            .section.skipped {{ border-left: 4px solid #95a5a6; background: #f8f9fa; }}
            .section.missing {{ border-left: 4px solid #f39c12; background: #fef9e7; }}
            .file-list {{ list-style: none; padding: 0; }}
            .file-list li {{ 
                background: white; 
                margin: 8px 0; 
                padding: 12px; 
                border-radius: 5px; 
                border-left: 3px solid #3498db;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }}
            .file-list a {{ color: #2980b9; text-decoration: none; font-weight: 500; }}
            .file-list a:hover {{ text-decoration: underline; }}
            .file-size {{ color: #7f8c8d; font-size: 0.9em; }}
            .status-badge {{ 
                padding: 4px 12px; 
                border-radius: 20px; 
                font-size: 0.8em; 
                font-weight: bold; 
                text-transform: uppercase;
                display: inline-block;
                margin-left: 10px;
            }}
            .status-success {{ background: #d4edda; color: #155724; }}
            .status-error {{ background: #f8d7da; color: #721c24; }}
            .status-warning {{ background: #fff3cd; color: #856404; }}
            .status-skipped {{ background: #e2e3e5; color: #383d41; }}
            .status-missing {{ background: #fff3cd; color: #856404; }}
            .status-partial {{ background: #fff3cd; color: #856404; }}
            .status-failed {{ background: #f8d7da; color: #721c24; }}
            .status-completed {{ background: #d4edda; color: #155724; }}
            .failure-summary {{ background: #fdf2f2; border: 1px solid #f5c6cb; border-radius: 8px; padding: 20px; margin: 20px 0; }}
            .failure-item {{ background: white; margin: 10px 0; padding: 15px; border-radius: 5px; border-left: 3px solid #e74c3c; }}
            .timestamp {{ color: #7f8c8d; font-style: italic; font-size: 0.9em; }}
            .error-section, .missing-section, .skipped-section {{ 
                padding: 20px; 
                border-radius: 8px; 
                margin: 15px 0; 
            }}
            .error-section {{ background: #fdf2f2; border: 1px solid #f5c6cb; }}
            .missing-section {{ background: #fff3cd; border: 1px solid #ffeaa7; }}
            .skipped-section {{ background: #e2e3e5; border: 1px solid #ced4da; }}
            .progress-bar {{ 
                width: 100%; 
                height: 20px; 
                background: #ecf0f1; 
                border-radius: 10px; 
                overflow: hidden; 
                margin: 10px 0;
            }}
            .progress-fill {{ 
                height: 100%; 
                background: linear-gradient(90deg, #3498db, #2ecc71); 
                transition: width 0.3s ease;
            }}
        </style>
    </head>
    <body>
    <div class="container">
        <h1>🧬 MetaNextViro Enhanced Analysis Report</h1>
        
        <div class="section {report_data['status'].lower()}">
            <h2>📊 Pipeline Summary</h2>
            <span class="status-badge status-{report_data['status'].lower()}">{report_data['status']}</span>
            <div class="summary-grid">
                <div class="summary-card">
                    <h4>Pipeline Status</h4>
                    <div class="value">{report_data['status']}</div>
                </div>
                <div class="summary-card">
                    <h4>Success Rate</h4>
                    <div class="value">{report_data['summary']['success_rate']}%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: {report_data['summary']['success_rate']}%"></div>
                    </div>
                </div>
                <div class="summary-card">
                    <h4>Successful Sections</h4>
                    <div class="value">{report_data['summary']['successful_sections']}</div>
                    <small>out of {report_data['summary']['total_sections']} total</small>
                </div>
                <div class="summary-card">
                    <h4>Issues</h4>
                    <div class="value">{report_data['summary']['failed_sections'] + report_data['summary']['missing_sections']}</div>
                    <small>{report_data['summary']['skipped_sections']} skipped</small>
                </div>
            </div>
            <p class="timestamp">Generated on: {report_data['metadata']['generated_at']}</p>
        </div>
    '''
    
    # Add failure summary if there are failures
    if report_data['failures']:
        html_content += '''
        <div class="failure-summary">
            <h2>⚠️ Process Failures and Issues</h2>
            <p>The following processes encountered issues during execution:</p>
        '''
        for failure in report_data['failures']:
            html_content += f'''
            <div class="failure-item">
                <h4>❌ {failure.get('process', 'Unknown Process')}</h4>
                <p><strong>Error:</strong> {failure.get('message', 'No message available')}</p>
                {f"<p><strong>Suggestion:</strong> {failure['suggestion']}</p>" if failure.get('suggestion') else ""}
                <p class="timestamp">Occurred at: {failure.get('timestamp', 'Unknown time')}</p>
            </div>
            '''
        html_content += '</div>'
    
    # Add sections
    for section_key, section_data in report_data['sections'].items():
        status_class = section_data['status'].lower()
        html_content += f'''
        <div class="section {status_class}">
            <h2>📄 {section_data['name']}</h2>
            <span class="status-badge status-{status_class}">{section_data['status']}</span>
            <p><em>{section_data['description']}</em></p>
            {section_data['content']}
        </div>
        '''
    
    # Footer
    html_content += f'''
        <hr style="margin: 40px 0; border: none; border-top: 2px solid #ecf0f1;">
        <div class="section">
            <p><em>📋 Report generated by MetaNextViro Enhanced Pipeline</em></p>
            <p><em>🔗 For more information, visit: <a href="https://github.com/navduhan/metanextviro">https://github.com/navduhan/metanextviro</a></em></p>
            <p class="timestamp">Report generated at: {report_data['metadata']['generated_at']}</p>
        </div>
    </div>
    </body>
    </html>
    '''
    
    # Write HTML report
    with open('enhanced_final_report.html', 'w') as f:
        f.write(html_content)
    
    print("✅ Enhanced final report generated successfully")
    print(f"📊 Status: {report_data['status']}")
    print(f"📈 Success Rate: {report_data['summary']['success_rate']}%")
    print(f"📁 Sections: {report_data['summary']['successful_sections']}/{report_data['summary']['total_sections']} successful")
    """
}