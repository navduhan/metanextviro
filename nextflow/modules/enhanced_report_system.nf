// Author: Naveen Duhan

// Enhanced Report Generation System with robust error handling and graceful degradation
process enhanced_report_system {
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
        path quast_results, stageAs: 'quast/*'
        path multiqc_results, stageAs: 'multiqc/*'

    output:
        path "enhanced_report.html", emit: report
        path "report_data.json", emit: data
        path "process_status.json", emit: status
        path "section_validation.json", emit: validation
        path "report_summary.txt", emit: summary

    script:
    """
    #!/usr/bin/env python3
    
    import os
    import json
    import datetime
    from pathlib import Path
    import glob
    import hashlib
    import traceback
    from collections import defaultdict
    
    class ReportSection:
        def __init__(self, name, description, required=True, icon="📄"):
            self.name = name
            self.description = description
            self.required = required
            self.icon = icon
            self.status = 'PENDING'
            self.files = []
            self.summary = {}
            self.content = ''
            self.error = None
            self.validation_results = {}
            self.timestamp = datetime.datetime.now()
        
        def set_status(self, status, error=None):
            self.status = status
            self.error = error
            self.timestamp = datetime.datetime.now()
        
        def add_files(self, files):
            self.files.extend(files)
        
        def set_summary(self, summary):
            self.summary = summary
        
        def set_content(self, content):
            self.content = content
        
        def validate_content(self):
            \"\"\"Validate section content and files\"\"\"
            validation = {
                'files_exist': True,
                'content_valid': True,
                'summary_complete': True,
                'issues': []
            }
            
            # Check if files exist and are readable
            for file_info in self.files:
                if not os.path.exists(file_info.get('path', '')):
                    validation['files_exist'] = False
                    validation['issues'].append(f"File not found: {file_info.get('name', 'unknown')}")
                elif os.path.getsize(file_info.get('path', '')) == 0:
                    validation['issues'].append(f"Empty file: {file_info.get('name', 'unknown')}")
            
            # Check content validity
            if not self.content or len(self.content.strip()) == 0:
                validation['content_valid'] = False
                validation['issues'].append("Section content is empty")
            
            # Check summary completeness
            if self.required and not self.summary:
                validation['summary_complete'] = False
                validation['issues'].append("Required section missing summary data")
            
            self.validation_results = validation
            return validation
        
        def to_dict(self):
            return {
                'name': self.name,
                'description': self.description,
                'required': self.required,
                'icon': self.icon,
                'status': self.status,
                'files': self.files,
                'summary': self.summary,
                'content': self.content,
                'error': self.error,
                'validation_results': self.validation_results,
                'timestamp': self.timestamp.isoformat()
            }
    
    class EnhancedReportGenerator:
        def __init__(self):
            self.sections = {}
            self.process_status = {}
            self.failures = []
            self.metadata = {
                'generated_at': datetime.datetime.now().isoformat(),
                'pipeline': 'MetaNextViro',
                'version': '1.0.0',
                'report_type': 'Enhanced Report System'
            }
            self.initialize_sections()
        
        def initialize_sections(self):
            \"\"\"Initialize all report sections\"\"\"
            sections_config = [
                ('quality', 'Quality Control', 'FastQC quality assessment results', True, '📊'),
                ('taxonomy', 'Taxonomic Classification', 'Kraken2 taxonomic profiling results', True, '🦠'),
                ('assembly', 'Assembly Results', 'Genome assembly statistics and contigs', True, '🧩'),
                ('assembly_quality', 'Assembly Quality', 'QUAST assembly quality metrics', False, '📏'),
                ('viral_analysis', 'Viral Analysis', 'CheckV and VirFinder viral genome analysis', False, '🔍'),
                ('functional_annotation', 'Functional Annotation', 'BLAST functional annotation results', False, '🔬'),
                ('coverage_analysis', 'Coverage Analysis', 'Read coverage and depth analysis', False, '📈'),
                ('assembly_logs', 'Assembly Logs', 'Detailed assembly process logs and statistics', False, '📝'),
                ('organized_contigs', 'Organized Contigs', 'Taxonomically organized contigs', False, '📁'),
                ('multiqc_summary', 'MultiQC Summary', 'Comprehensive quality control summary', False, '📋')
            ]
            
            for section_id, name, description, required, icon in sections_config:
                self.sections[section_id] = ReportSection(name, description, required, icon)
        
        def collect_files_robust(self, directory, extensions=None, recursive=True):
            \"\"\"Robustly collect files with error handling\"\"\"
            files = []
            if not os.path.exists(directory):
                return files
            
            try:
                if recursive:
                    for root, dirs, filenames in os.walk(directory):
                        for filename in filenames:
                            if self.matches_extensions(filename, extensions):
                                filepath = os.path.join(root, filename)
                                try:
                                    file_info = self.get_file_info(filepath, root)
                                    if file_info:
                                        files.append(file_info)
                                except Exception as e:
                                    print(f"Warning: Could not process file {filepath}: {e}")
                else:
                    for filename in os.listdir(directory):
                        filepath = os.path.join(directory, filename)
                        if os.path.isfile(filepath) and self.matches_extensions(filename, extensions):
                            try:
                                file_info = self.get_file_info(filepath, directory)
                                if file_info:
                                    files.append(file_info)
                            except Exception as e:
                                print(f"Warning: Could not process file {filepath}: {e}")
            except Exception as e:
                print(f"Error accessing directory {directory}: {e}")
            
            return files
        
        def matches_extensions(self, filename, extensions):
            \"\"\"Check if filename matches any of the specified extensions\"\"\"
            if extensions is None:
                return True
            return any(filename.lower().endswith(ext.lower()) for ext in extensions)
        
        def get_file_info(self, filepath, base_dir):
            \"\"\"Get comprehensive file information\"\"\"
            try:
                stat = os.stat(filepath)
                return {
                    'name': os.path.basename(filepath),
                    'path': os.path.relpath(filepath),
                    'size': stat.st_size,
                    'modified': datetime.datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    'directory': os.path.basename(base_dir),
                    'checksum': self.calculate_checksum(filepath) if stat.st_size < 10*1024*1024 else None  # Only for files < 10MB
                }
            except Exception as e:
                print(f"Error getting file info for {filepath}: {e}")
                return None
        
        def calculate_checksum(self, filepath):
            \"\"\"Calculate MD5 checksum for file validation\"\"\"
            try:
                hash_md5 = hashlib.md5()
                with open(filepath, "rb") as f:
                    for chunk in iter(lambda: f.read(4096), b""):
                        hash_md5.update(chunk)
                return hash_md5.hexdigest()
            except Exception:
                return None
        
        def load_process_failures(self):
            \"\"\"Load process failure information\"\"\"
            failures = []
            try:
                failure_files = glob.glob('failures/*.json')
                for failure_file in failure_files:
                    try:
                        with open(failure_file, 'r') as f:
                            failure_data = json.load(f)
                            if isinstance(failure_data, dict):
                                failures.extend(failure_data.get('failures', []))
                            elif isinstance(failure_data, list):
                                failures.extend(failure_data)
                    except Exception as e:
                        print(f"Warning: Could not load failure file {failure_file}: {e}")
            except Exception as e:
                print(f"Warning: Could not load failure data: {e}")
            
            self.failures = failures
            return failures
        
        def generate_quality_section(self):
            \"\"\"Generate quality control section with error recovery\"\"\"
            section = self.sections['quality']
            
            try:
                # Collect FastQC files
                fastqc_files = self.collect_files_robust('fastqc', ['html', 'zip'])
                section.add_files(fastqc_files)
                
                if not fastqc_files:
                    if section.required:
                        section.set_status('MISSING', 'No FastQC reports found')
                        section.set_content(self.generate_missing_content('Quality Control', 'No FastQC reports available'))
                    else:
                        section.set_status('SKIPPED', 'FastQC analysis not performed')
                        section.set_content(self.generate_skipped_content('Quality Control', 'FastQC analysis was not performed'))
                    return
                
                # Generate summary
                html_files = [f for f in fastqc_files if f['name'].endswith('.html')]
                zip_files = [f for f in fastqc_files if f['name'].endswith('.zip')]
                
                section.set_summary({
                    'total_samples': len(html_files),
                    'html_reports': len(html_files),
                    'zip_archives': len(zip_files),
                    'total_size': sum(f['size'] for f in fastqc_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(fastqc_files, 'FastQC Reports')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Quality Control', e, section.required))
        
        def generate_taxonomy_section(self):
            \"\"\"Generate taxonomic classification section\"\"\"
            section = self.sections['taxonomy']
            
            try:
                # Collect Kraken2 files
                kraken_files = self.collect_files_robust('kraken2', ['report', 'txt', 'kraken', 'output'])
                section.add_files(kraken_files)
                
                if not kraken_files:
                    if section.required:
                        section.set_status('MISSING', 'No Kraken2 reports found')
                        section.set_content(self.generate_missing_content('Taxonomic Classification', 'No Kraken2 reports available'))
                    else:
                        section.set_status('SKIPPED', 'Taxonomic classification not performed')
                        section.set_content(self.generate_skipped_content('Taxonomic Classification', 'Taxonomic classification was not performed'))
                    return
                
                # Generate summary
                report_files = [f for f in kraken_files if 'report' in f['name']]
                output_files = [f for f in kraken_files if 'output' in f['name'] or 'kraken' in f['name']]
                
                section.set_summary({
                    'total_files': len(kraken_files),
                    'report_files': len(report_files),
                    'output_files': len(output_files),
                    'total_size': sum(f['size'] for f in kraken_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(kraken_files, 'Kraken2 Classification Results')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Taxonomic Classification', e, section.required))
        
        def generate_assembly_section(self):
            \"\"\"Generate assembly results section\"\"\"
            section = self.sections['assembly']
            
            try:
                # Collect assembly files
                assembly_files = self.collect_files_robust('assembly', ['fa', 'fasta', 'fna'])
                section.add_files(assembly_files)
                
                if not assembly_files:
                    if section.required:
                        section.set_status('MISSING', 'No assembly files found')
                        section.set_content(self.generate_missing_content('Assembly Results', 'No assembly files available'))
                    else:
                        section.set_status('SKIPPED', 'Assembly not performed')
                        section.set_content(self.generate_skipped_content('Assembly Results', 'Assembly was not performed'))
                    return
                
                # Generate summary with basic statistics
                total_contigs = 0
                total_size = sum(f['size'] for f in assembly_files)
                
                section.set_summary({
                    'assembly_files': len(assembly_files),
                    'total_size': total_size,
                    'estimated_contigs': total_contigs,  # Would need to parse files for actual count
                    'assemblers_used': self.detect_assemblers(assembly_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(assembly_files, 'Assembly Files')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Assembly Results', e, section.required))
        
        def generate_assembly_quality_section(self):
            \"\"\"Generate assembly quality section (QUAST results)\"\"\"
            section = self.sections['assembly_quality']
            
            try:
                # Collect QUAST files
                quast_files = self.collect_files_robust('quast', ['txt', 'tsv', 'html', 'pdf'])
                section.add_files(quast_files)
                
                if not quast_files:
                    section.set_status('SKIPPED', 'QUAST analysis not performed')
                    section.set_content(self.generate_skipped_content('Assembly Quality', 'QUAST quality assessment was not performed'))
                    return
                
                # Generate summary
                section.set_summary({
                    'quast_files': len(quast_files),
                    'reports': len([f for f in quast_files if f['name'].endswith('.html')]),
                    'data_files': len([f for f in quast_files if f['name'].endswith(('.txt', '.tsv'))]),
                    'total_size': sum(f['size'] for f in quast_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(quast_files, 'QUAST Quality Assessment')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Assembly Quality', e, section.required))
        
        def generate_viral_analysis_section(self):
            \"\"\"Generate viral analysis section\"\"\"
            section = self.sections['viral_analysis']
            
            try:
                # Collect viral analysis files
                checkv_files = self.collect_files_robust('checkv', ['tsv', 'txt', 'fasta'])
                virfinder_full_files = self.collect_files_robust('virfinder_full', ['tsv', 'txt', 'csv'])
                virfinder_filtered_files = self.collect_files_robust('virfinder_filtered', ['tsv', 'txt', 'csv'])
                
                all_viral_files = checkv_files + virfinder_full_files + virfinder_filtered_files
                section.add_files(all_viral_files)
                
                if not all_viral_files:
                    section.set_status('SKIPPED', 'Viral analysis not performed')
                    section.set_content(self.generate_skipped_content('Viral Analysis', 'Viral analysis was not performed or failed'))
                    return
                
                # Generate summary
                section.set_summary({
                    'checkv_files': len(checkv_files),
                    'virfinder_full_files': len(virfinder_full_files),
                    'virfinder_filtered_files': len(virfinder_filtered_files),
                    'total_files': len(all_viral_files),
                    'total_size': sum(f['size'] for f in all_viral_files)
                })
                
                # Generate content
                content = "<h3>CheckV Results</h3>"
                content += self.generate_file_list_html(checkv_files, 'CheckV Files')
                content += "<h3>VirFinder Results</h3>"
                content += self.generate_file_list_html(virfinder_full_files + virfinder_filtered_files, 'VirFinder Files')
                
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Viral Analysis', e, section.required))
        
        def generate_functional_annotation_section(self):
            \"\"\"Generate functional annotation section\"\"\"
            section = self.sections['functional_annotation']
            
            try:
                # Collect BLAST files
                blast_files = self.collect_files_robust('blast', ['txt', 'tsv', 'xml', 'out'])
                section.add_files(blast_files)
                
                if not blast_files:
                    section.set_status('SKIPPED', 'Functional annotation not performed')
                    section.set_content(self.generate_skipped_content('Functional Annotation', 'BLAST annotation was not performed or failed'))
                    return
                
                # Generate summary
                section.set_summary({
                    'blast_files': len(blast_files),
                    'total_size': sum(f['size'] for f in blast_files),
                    'databases_used': self.detect_blast_databases(blast_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(blast_files, 'BLAST Annotation Results')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Functional Annotation', e, section.required))
        
        def generate_coverage_analysis_section(self):
            \"\"\"Generate coverage analysis section\"\"\"
            section = self.sections['coverage_analysis']
            
            try:
                # Collect coverage files
                coverage_files = self.collect_files_robust('coverage', ['txt', 'tsv', 'png', 'pdf', 'cov'])
                section.add_files(coverage_files)
                
                if not coverage_files:
                    section.set_status('SKIPPED', 'Coverage analysis not performed')
                    section.set_content(self.generate_skipped_content('Coverage Analysis', 'Coverage analysis was not performed or failed'))
                    return
                
                # Generate summary
                data_files = [f for f in coverage_files if f['name'].endswith(('.txt', '.tsv', '.cov'))]
                plot_files = [f for f in coverage_files if f['name'].endswith(('.png', '.pdf'))]
                
                section.set_summary({
                    'coverage_files': len(coverage_files),
                    'data_files': len(data_files),
                    'plot_files': len(plot_files),
                    'total_size': sum(f['size'] for f in coverage_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(coverage_files, 'Coverage Analysis Results')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Coverage Analysis', e, section.required))
        
        def generate_assembly_logs_section(self):
            \"\"\"Generate assembly logs section\"\"\"
            section = self.sections['assembly_logs']
            
            try:
                # Collect all assembly log files
                megahit_logs = self.collect_files_robust('megahit_logs', ['log', 'txt'])
                megahit_params = self.collect_files_robust('megahit_params', ['txt', 'params'])
                megahit_contigs = self.collect_files_robust('megahit_contigs', ['fa', 'fasta'])
                
                metaspades_logs = self.collect_files_robust('metaspades_logs', ['log', 'txt'])
                metaspades_params = self.collect_files_robust('metaspades_params', ['txt', 'params'])
                metaspades_scaffolds = self.collect_files_robust('metaspades_scaffolds', ['fa', 'fasta'])
                
                hybrid_merged = self.collect_files_robust('hybrid_merged', ['fa', 'fasta'])
                hybrid_cdhit = self.collect_files_robust('hybrid_cdhit', ['fa', 'fasta'])
                hybrid_clstr = self.collect_files_robust('hybrid_clstr', ['clstr', 'txt'])
                
                all_log_files = (megahit_logs + megahit_params + megahit_contigs + 
                               metaspades_logs + metaspades_params + metaspades_scaffolds +
                               hybrid_merged + hybrid_cdhit + hybrid_clstr)
                
                section.add_files(all_log_files)
                
                if not all_log_files:
                    section.set_status('SKIPPED', 'Assembly logs not available')
                    section.set_content(self.generate_skipped_content('Assembly Logs', 'Assembly logs were not generated or are not available'))
                    return
                
                # Generate summary
                section.set_summary({
                    'megahit_files': len(megahit_logs + megahit_params + megahit_contigs),
                    'metaspades_files': len(metaspades_logs + metaspades_params + metaspades_scaffolds),
                    'hybrid_files': len(hybrid_merged + hybrid_cdhit + hybrid_clstr),
                    'total_files': len(all_log_files),
                    'total_size': sum(f['size'] for f in all_log_files)
                })
                
                # Generate content with organized sections
                content = "<h3>MEGAHIT Assembly</h3>"
                content += self.generate_file_list_html(megahit_logs + megahit_params + megahit_contigs, 'MEGAHIT Files')
                content += "<h3>MetaSPAdes Assembly</h3>"
                content += self.generate_file_list_html(metaspades_logs + metaspades_params + metaspades_scaffolds, 'MetaSPAdes Files')
                content += "<h3>Hybrid Assembly</h3>"
                content += self.generate_file_list_html(hybrid_merged + hybrid_cdhit + hybrid_clstr, 'Hybrid Assembly Files')
                
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Assembly Logs', e, section.required))
        
        def generate_organized_contigs_section(self):
            \"\"\"Generate organized contigs section\"\"\"
            section = self.sections['organized_contigs']
            
            try:
                # Collect organized contig files
                organized_files = self.collect_files_robust('organized', ['fa', 'fasta'])
                section.add_files(organized_files)
                
                if not organized_files:
                    section.set_status('SKIPPED', 'Contig organization not performed')
                    section.set_content(self.generate_skipped_content('Organized Contigs', 'Contig organization was not performed'))
                    return
                
                # Generate summary
                directories = set(f['directory'] for f in organized_files)
                
                section.set_summary({
                    'organized_files': len(organized_files),
                    'taxonomic_groups': len(directories),
                    'total_size': sum(f['size'] for f in organized_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(organized_files, 'Taxonomically Organized Contigs')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('Organized Contigs', e, section.required))
        
        def generate_multiqc_section(self):
            \"\"\"Generate MultiQC summary section\"\"\"
            section = self.sections['multiqc_summary']
            
            try:
                # Collect MultiQC files
                multiqc_files = self.collect_files_robust('multiqc', ['html', 'json', 'txt'])
                section.add_files(multiqc_files)
                
                if not multiqc_files:
                    section.set_status('SKIPPED', 'MultiQC summary not generated')
                    section.set_content(self.generate_skipped_content('MultiQC Summary', 'MultiQC summary was not generated'))
                    return
                
                # Generate summary
                section.set_summary({
                    'multiqc_files': len(multiqc_files),
                    'html_reports': len([f for f in multiqc_files if f['name'].endswith('.html')]),
                    'data_files': len([f for f in multiqc_files if f['name'].endswith(('.json', '.txt'))]),
                    'total_size': sum(f['size'] for f in multiqc_files)
                })
                
                # Generate content
                content = self.generate_file_list_html(multiqc_files, 'MultiQC Summary Reports')
                section.set_content(content)
                section.set_status('SUCCESS')
                
            except Exception as e:
                section.set_status('ERROR', str(e))
                section.set_content(self.generate_error_content('MultiQC Summary', e, section.required))
        
        def detect_assemblers(self, assembly_files):
            \"\"\"Detect which assemblers were used based on file names\"\"\"
            assemblers = set()
            for file_info in assembly_files:
                name = file_info['name'].lower()
                if 'megahit' in name:
                    assemblers.add('MEGAHIT')
                elif 'metaspades' in name or 'spades' in name:
                    assemblers.add('MetaSPAdes')
                elif 'hybrid' in name:
                    assemblers.add('Hybrid')
            return list(assemblers)
        
        def detect_blast_databases(self, blast_files):
            \"\"\"Detect which BLAST databases were used\"\"\"
            databases = set()
            for file_info in blast_files:
                name = file_info['name'].lower()
                if 'nt' in name:
                    databases.add('NCBI NT')
                elif 'nr' in name:
                    databases.add('NCBI NR')
                elif 'virus' in name:
                    databases.add('Viral')
            return list(databases)
        
        def generate_file_list_html(self, files, title):
            \"\"\"Generate HTML for file list\"\"\"
            if not files:
                return f"<p>No {title.lower()} available.</p>"
            
            html = f"<p><strong>{title}:</strong> {len(files)} files</p>"
            html += "<ul class='file-list'>"
            
            for file_info in files:
                size_str = self.format_file_size(file_info['size'])
                html += f"<li><a href='{file_info['name']}'>{file_info['name']}</a> <span class='file-size'>({size_str})</span></li>"
            
            html += "</ul>"
            return html
        
        def generate_missing_content(self, section_name, reason):
            \"\"\"Generate content for missing sections\"\"\"
            return f"<div class='missing-section'><p>⚠️ {reason}</p><p>This is a required section for the pipeline.</p></div>"
        
        def generate_skipped_content(self, section_name, reason):
            \"\"\"Generate content for skipped sections\"\"\"
            return f"<div class='skipped-section'><p>ℹ️ {reason}</p><p>This is an optional analysis step.</p></div>"
        
        def generate_error_content(self, section_name, error, required):
            \"\"\"Generate content for error sections\"\"\"
            content = f"<div class='error-section'><h4>❌ Error in {section_name}</h4>"
            content += f"<p><strong>Error:</strong> {str(error)}</p>"
            
            if required:
                content += "<p><strong>Impact:</strong> This is a required section. The pipeline may have failed.</p>"
                content += "<p><strong>Suggestion:</strong> Check the pipeline logs and ensure all required inputs are available.</p>"
            else:
                content += "<p><strong>Impact:</strong> This is an optional section. The pipeline can continue without it.</p>"
                content += "<p><strong>Note:</strong> You may re-run the pipeline with different parameters to include this analysis.</p>"
            
            content += "</div>"
            return content
        
        def format_file_size(self, bytes_size):
            \"\"\"Format file size for human reading\"\"\"
            if bytes_size < 1024:
                return f"{bytes_size} B"
            elif bytes_size < 1024 * 1024:
                return f"{bytes_size / 1024:.1f} KB"
            elif bytes_size < 1024 * 1024 * 1024:
                return f"{bytes_size / (1024 * 1024):.1f} MB"
            else:
                return f"{bytes_size / (1024 * 1024 * 1024):.1f} GB"
        
        def validate_all_sections(self):
            \"\"\"Validate all sections and return validation report\"\"\"
            validation_report = {
                'timestamp': datetime.datetime.now().isoformat(),
                'sections': {},
                'overall_status': 'VALID',
                'issues': []
            }
            
            for section_id, section in self.sections.items():
                validation = section.validate_content()
                validation_report['sections'][section_id] = validation
                
                if not validation['files_exist'] or not validation['content_valid']:
                    validation_report['overall_status'] = 'ISSUES'
                    validation_report['issues'].extend(validation['issues'])
            
            return validation_report
        
        def calculate_process_status(self):
            \"\"\"Calculate overall process status\"\"\"
            status_counts = defaultdict(int)
            
            for section in self.sections.values():
                status_counts[section.status] += 1
            
            total_sections = len(self.sections)
            required_sections = sum(1 for s in self.sections.values() if s.required)
            required_success = sum(1 for s in self.sections.values() if s.required and s.status == 'SUCCESS')
            
            # Determine overall status
            if required_success == required_sections and status_counts['ERROR'] == 0:
                overall_status = 'COMPLETED'
            elif required_success == required_sections and status_counts['ERROR'] > 0:
                overall_status = 'PARTIAL'
            elif required_success < required_sections:
                overall_status = 'FAILED'
            else:
                overall_status = 'UNKNOWN'
            
            return {
                'overall_status': overall_status,
                'total_sections': total_sections,
                'required_sections': required_sections,
                'successful_sections': status_counts['SUCCESS'],
                'failed_sections': status_counts['ERROR'],
                'missing_sections': status_counts['MISSING'],
                'skipped_sections': status_counts['SKIPPED'],
                'success_rate': round((status_counts['SUCCESS'] / total_sections * 100), 1) if total_sections > 0 else 0,
                'required_success_rate': round((required_success / required_sections * 100), 1) if required_sections > 0 else 0
            }
        
        def generate_report(self):
            \"\"\"Generate complete report with all sections\"\"\"
            print("🔄 Starting enhanced report generation...")
            
            # Load process failures
            self.load_process_failures()
            
            # Generate all sections
            try:
                self.generate_quality_section()
                print("✅ Quality section generated")
            except Exception as e:
                print(f"❌ Error in quality section: {e}")
            
            try:
                self.generate_taxonomy_section()
                print("✅ Taxonomy section generated")
            except Exception as e:
                print(f"❌ Error in taxonomy section: {e}")
            
            try:
                self.generate_assembly_section()
                print("✅ Assembly section generated")
            except Exception as e:
                print(f"❌ Error in assembly section: {e}")
            
            try:
                self.generate_assembly_quality_section()
                print("✅ Assembly quality section generated")
            except Exception as e:
                print(f"❌ Error in assembly quality section: {e}")
            
            try:
                self.generate_viral_analysis_section()
                print("✅ Viral analysis section generated")
            except Exception as e:
                print(f"❌ Error in viral analysis section: {e}")
            
            try:
                self.generate_functional_annotation_section()
                print("✅ Functional annotation section generated")
            except Exception as e:
                print(f"❌ Error in functional annotation section: {e}")
            
            try:
                self.generate_coverage_analysis_section()
                print("✅ Coverage analysis section generated")
            except Exception as e:
                print(f"❌ Error in coverage analysis section: {e}")
            
            try:
                self.generate_assembly_logs_section()
                print("✅ Assembly logs section generated")
            except Exception as e:
                print(f"❌ Error in assembly logs section: {e}")
            
            try:
                self.generate_organized_contigs_section()
                print("✅ Organized contigs section generated")
            except Exception as e:
                print(f"❌ Error in organized contigs section: {e}")
            
            try:
                self.generate_multiqc_section()
                print("✅ MultiQC section generated")
            except Exception as e:
                print(f"❌ Error in MultiQC section: {e}")
            
            # Calculate status and validate
            process_status = self.calculate_process_status()
            validation_report = self.validate_all_sections()
            
            # Generate report data
            report_data = {
                'metadata': self.metadata,
                'process_status': process_status,
                'sections': {k: v.to_dict() for k, v in self.sections.items()},
                'failures': self.failures,
                'validation': validation_report
            }
            
            return report_data, process_status, validation_report
    
    # Initialize and run report generation
    generator = EnhancedReportGenerator()
    report_data, process_status, validation_report = generator.generate_report()
    
    # Save report data
    with open('report_data.json', 'w') as f:
        json.dump(report_data, f, indent=2, default=str)
    
    with open('process_status.json', 'w') as f:
        json.dump(process_status, f, indent=2)
    
    with open('section_validation.json', 'w') as f:
        json.dump(validation_report, f, indent=2)
    
    # Generate summary text
    summary_text = f'''MetaNextViro Enhanced Report Summary
    =====================================
    
    Generated: {report_data['metadata']['generated_at']}
    Pipeline: {report_data['metadata']['pipeline']} v{report_data['metadata']['version']}
    
    Overall Status: {process_status['overall_status']}
    Success Rate: {process_status['success_rate']}%
    Required Success Rate: {process_status['required_success_rate']}%
    
    Section Summary:
    - Total Sections: {process_status['total_sections']}
    - Successful: {process_status['successful_sections']}
    - Failed: {process_status['failed_sections']}
    - Missing: {process_status['missing_sections']}
    - Skipped: {process_status['skipped_sections']}
    
    Validation Status: {validation_report['overall_status']}
    '''
    
    if validation_report['issues']:
        summary_text += f"\\nValidation Issues: {len(validation_report['issues'])}\\n"
        for issue in validation_report['issues'][:5]:  # Show first 5 issues
            summary_text += f"- {issue}\\n"
    
    if report_data['failures']:
        summary_text += f"\\nProcess Failures: {len(report_data['failures'])}\\n"
        for failure in report_data['failures'][:3]:  # Show first 3 failures
            summary_text += f"- {failure.get('process', 'Unknown')}: {failure.get('message', 'No message')}\\n"
    
    with open('report_summary.txt', 'w') as f:
        f.write(summary_text)
    
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
            .validation-info {{ 
                background: #e8f4fd; 
                border: 1px solid #bee5eb; 
                border-radius: 8px; 
                padding: 15px; 
                margin: 20px 0; 
            }}
        </style>
    </head>
    <body>
    <div class="container">
        <h1>🧬 MetaNextViro Enhanced Analysis Report</h1>
        
        <div class="section {process_status['overall_status'].lower()}">
            <h2>📊 Pipeline Summary</h2>
            <span class="status-badge status-{process_status['overall_status'].lower()}">{process_status['overall_status']}</span>
            <div class="summary-grid">
                <div class="summary-card">
                    <h4>Pipeline Status</h4>
                    <div class="value">{process_status['overall_status']}</div>
                </div>
                <div class="summary-card">
                    <h4>Success Rate</h4>
                    <div class="value">{process_status['success_rate']}%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: {process_status['success_rate']}%"></div>
                    </div>
                </div>
                <div class="summary-card">
                    <h4>Successful Sections</h4>
                    <div class="value">{process_status['successful_sections']}</div>
                    <small>out of {process_status['total_sections']} total</small>
                </div>
                <div class="summary-card">
                    <h4>Issues</h4>
                    <div class="value">{process_status['failed_sections'] + process_status['missing_sections']}</div>
                    <small>{process_status['skipped_sections']} skipped</small>
                </div>
            </div>
            <p class="timestamp">Generated on: {report_data['metadata']['generated_at']}</p>
        </div>
        
        <div class="validation-info">
            <h3>🔍 Report Validation</h3>
            <p><strong>Validation Status:</strong> <span class="status-badge status-{validation_report['overall_status'].lower()}">{validation_report['overall_status']}</span></p>
            <p><strong>Sections Validated:</strong> {len(validation_report['sections'])}</p>
            {f"<p><strong>Issues Found:</strong> {len(validation_report['issues'])}</p>" if validation_report['issues'] else ""}
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
    for section_id, section_data in report_data['sections'].items():
        status_class = section_data['status'].lower()
        html_content += f'''
        <div class="section {status_class}">
            <h2>{section_data['icon']} {section_data['name']}</h2>
            <span class="status-badge status-{status_class}">{section_data['status']}</span>
            <p><em>{section_data['description']}</em></p>
            {section_data['content']}
        </div>
        '''
    
    # Footer
    html_content += f'''
        <hr style="margin: 40px 0; border: none; border-top: 2px solid #ecf0f1;">
        <div class="section">
            <p><em>📋 Report generated by MetaNextViro Enhanced Report System</em></p>
            <p><em>🔗 For more information, visit: <a href="https://github.com/navduhan/metanextviro">https://github.com/navduhan/metanextviro</a></em></p>
            <p class="timestamp">Report generated at: {report_data['metadata']['generated_at']}</p>
        </div>
    </div>
    </body>
    </html>
    '''
    
    # Write HTML report
    with open('enhanced_report.html', 'w') as f:
        f.write(html_content)
    
    print("✅ Enhanced report generation completed successfully")
    print(f"📊 Status: {process_status['overall_status']}")
    print(f"📈 Success Rate: {process_status['success_rate']}%")
    print(f"📁 Sections: {process_status['successful_sections']}/{process_status['total_sections']} successful")
    print(f"🔍 Validation: {validation_report['overall_status']}")
    """
}