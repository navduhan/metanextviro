// Enhanced Reporting Subworkflow with robust collection and error handling
include { enhanced_report_system } from '../modules/enhanced_report_system'

workflow ENHANCED_REPORTING {
    take:
        // All possible pipeline outputs with optional handling
        kraken2_reports
        fastqc_reports
        coverage_stats
        checkv_results
        virfinder_full
        virfinder_filtered
        blast_results
        assembly_results
        megahit_logs
        megahit_params
        megahit_raw_contigs
        metaspades_logs
        metaspades_params
        metaspades_raw_scaffolds
        hybrid_merged
        hybrid_cdhit
        hybrid_cdhit_clstr
        organized_dirs
        quast_results
        multiqc_results
        process_failures

    main:
        // Robust output collection with missing file handling
        collected_outputs = collectOutputsWithValidation(
            kraken2_reports,
            fastqc_reports,
            coverage_stats,
            checkv_results,
            virfinder_full,
            virfinder_filtered,
            blast_results,
            assembly_results,
            megahit_logs,
            megahit_params,
            megahit_raw_contigs,
            metaspades_logs,
            metaspades_params,
            metaspades_raw_scaffolds,
            hybrid_merged,
            hybrid_cdhit,
            hybrid_cdhit_clstr,
            organized_dirs,
            quast_results,
            multiqc_results,
            process_failures
        )

        // Generate enhanced report with error recovery
        enhanced_report_system(
            collected_outputs.kraken2_reports,
            collected_outputs.fastqc_reports,
            collected_outputs.coverage_stats,
            collected_outputs.checkv_results,
            collected_outputs.virfinder_full,
            collected_outputs.virfinder_filtered,
            collected_outputs.blast_results,
            collected_outputs.assembly_results,
            collected_outputs.megahit_logs,
            collected_outputs.megahit_params,
            collected_outputs.megahit_raw_contigs,
            collected_outputs.metaspades_logs,
            collected_outputs.metaspades_params,
            collected_outputs.metaspades_raw_scaffolds,
            collected_outputs.hybrid_merged,
            collected_outputs.hybrid_cdhit,
            collected_outputs.hybrid_cdhit_clstr,
            collected_outputs.organized_dirs,
            collected_outputs.quast_results,
            collected_outputs.multiqc_results,
            collected_outputs.process_failures
        )

    emit:
        report = enhanced_report_system.out.report
        data = enhanced_report_system.out.data
        status = enhanced_report_system.out.status
        validation = enhanced_report_system.out.validation
        summary = enhanced_report_system.out.summary
}

/**
 * Robust output collection with missing file handling and validation
 */
def collectOutputsWithValidation(
    kraken2_reports,
    fastqc_reports,
    coverage_stats,
    checkv_results,
    virfinder_full,
    virfinder_filtered,
    blast_results,
    assembly_results,
    megahit_logs,
    megahit_params,
    megahit_raw_contigs,
    metaspades_logs,
    metaspades_params,
    metaspades_raw_scaffolds,
    hybrid_merged,
    hybrid_cdhit,
    hybrid_cdhit_clstr,
    organized_dirs,
    quast_results,
    multiqc_results,
    process_failures
) {
    
    // Create empty file placeholders for missing outputs
    def emptyFile = file("${workflow.workDir}/empty_placeholder.txt")
    if (!emptyFile.exists()) {
        emptyFile.text = "# Empty placeholder file for missing pipeline outputs\n"
    }
    
    // Validate and collect outputs with fallback to empty files
    def validatedOutputs = [:]
    
    // Helper function to validate channel outputs
    def validateOutput = { output, name ->
        try {
            if (output && !output.isEmpty()) {
                // Check if output contains valid files
                def validFiles = output.filter { file ->
                    file.exists() && file.size() > 0
                }
                return validFiles.ifEmpty { [emptyFile] }
            } else {
                log.warn "No ${name} outputs available, using placeholder"
                return [emptyFile]
            }
        } catch (Exception e) {
            log.warn "Error validating ${name} outputs: ${e.message}, using placeholder"
            return [emptyFile]
        }
    }
    
    // Validate all outputs
    validatedOutputs.kraken2_reports = validateOutput(kraken2_reports, "Kraken2")
    validatedOutputs.fastqc_reports = validateOutput(fastqc_reports, "FastQC")
    validatedOutputs.coverage_stats = validateOutput(coverage_stats, "Coverage")
    validatedOutputs.checkv_results = validateOutput(checkv_results, "CheckV")
    validatedOutputs.virfinder_full = validateOutput(virfinder_full, "VirFinder Full")
    validatedOutputs.virfinder_filtered = validateOutput(virfinder_filtered, "VirFinder Filtered")
    validatedOutputs.blast_results = validateOutput(blast_results, "BLAST")
    validatedOutputs.assembly_results = validateOutput(assembly_results, "Assembly")
    validatedOutputs.megahit_logs = validateOutput(megahit_logs, "MEGAHIT Logs")
    validatedOutputs.megahit_params = validateOutput(megahit_params, "MEGAHIT Params")
    validatedOutputs.megahit_raw_contigs = validateOutput(megahit_raw_contigs, "MEGAHIT Contigs")
    validatedOutputs.metaspades_logs = validateOutput(metaspades_logs, "MetaSPAdes Logs")
    validatedOutputs.metaspades_params = validateOutput(metaspades_params, "MetaSPAdes Params")
    validatedOutputs.metaspades_raw_scaffolds = validateOutput(metaspades_raw_scaffolds, "MetaSPAdes Scaffolds")
    validatedOutputs.hybrid_merged = validateOutput(hybrid_merged, "Hybrid Merged")
    validatedOutputs.hybrid_cdhit = validateOutput(hybrid_cdhit, "Hybrid CD-HIT")
    validatedOutputs.hybrid_cdhit_clstr = validateOutput(hybrid_cdhit_clstr, "Hybrid Clusters")
    validatedOutputs.organized_dirs = validateOutput(organized_dirs, "Organized Contigs")
    validatedOutputs.quast_results = validateOutput(quast_results, "QUAST")
    validatedOutputs.multiqc_results = validateOutput(multiqc_results, "MultiQC")
    validatedOutputs.process_failures = validateOutput(process_failures, "Process Failures")
    
    return validatedOutputs
}

/**
 * Independent report section generation with error recovery
 */
workflow GENERATE_REPORT_SECTIONS {
    take:
        all_outputs
        
    main:
        // Generate each section independently with error handling
        quality_section = generateQualitySection(all_outputs.fastqc_reports)
        taxonomy_section = generateTaxonomySection(all_outputs.kraken2_reports)
        assembly_section = generateAssemblySection(all_outputs.assembly_results)
        viral_section = generateViralSection(
            all_outputs.checkv_results,
            all_outputs.virfinder_full,
            all_outputs.virfinder_filtered
        )
        annotation_section = generateAnnotationSection(all_outputs.blast_results)
        coverage_section = generateCoverageSection(all_outputs.coverage_stats)
        
        // Combine sections with status tracking
        combined_sections = combineReportSections(
            quality_section,
            taxonomy_section,
            assembly_section,
            viral_section,
            annotation_section,
            coverage_section
        )
        
    emit:
        sections = combined_sections
}

/**
 * Generate quality control section with error handling
 */
def generateQualitySection(fastqc_outputs) {
    return process {
        tag "quality_section"
        label 'process_low'
        
        input:
        path fastqc_files from fastqc_outputs
        
        output:
        path "quality_section.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        import os
        from pathlib import Path
        
        section_data = {
            'name': 'Quality Control',
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'timestamp': '$(date -Iseconds)'
        }
        
        try:
            # Process FastQC files
            fastqc_files = []
            for root, dirs, files in os.walk('.'):
                for file in files:
                    if file.endswith(('.html', '.zip')):
                        file_path = os.path.join(root, file)
                        file_info = {
                            'name': file,
                            'path': file_path,
                            'size': os.path.getsize(file_path)
                        }
                        fastqc_files.append(file_info)
            
            section_data['files'] = fastqc_files
            section_data['summary'] = {
                'total_files': len(fastqc_files),
                'html_reports': len([f for f in fastqc_files if f['name'].endswith('.html')]),
                'zip_archives': len([f for f in fastqc_files if f['name'].endswith('.zip')])
            }
            
            if not fastqc_files:
                section_data['status'] = 'MISSING'
                section_data['message'] = 'No FastQC files found'
            
        except Exception as e:
            section_data['status'] = 'ERROR'
            section_data['error'] = str(e)
        
        with open('quality_section.json', 'w') as f:
            json.dump(section_data, f, indent=2)
        """
    }
}

/**
 * Generate taxonomy section with error handling
 */
def generateTaxonomySection(kraken2_outputs) {
    return process {
        tag "taxonomy_section"
        label 'process_low'
        
        input:
        path kraken2_files from kraken2_outputs
        
        output:
        path "taxonomy_section.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        import os
        
        section_data = {
            'name': 'Taxonomic Classification',
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'timestamp': '$(date -Iseconds)'
        }
        
        try:
            # Process Kraken2 files
            kraken_files = []
            for root, dirs, files in os.walk('.'):
                for file in files:
                    if any(ext in file.lower() for ext in ['report', 'kraken', 'output']):
                        file_path = os.path.join(root, file)
                        file_info = {
                            'name': file,
                            'path': file_path,
                            'size': os.path.getsize(file_path)
                        }
                        kraken_files.append(file_info)
            
            section_data['files'] = kraken_files
            section_data['summary'] = {
                'total_files': len(kraken_files),
                'report_files': len([f for f in kraken_files if 'report' in f['name']]),
                'output_files': len([f for f in kraken_files if 'output' in f['name'] or 'kraken' in f['name']])
            }
            
            if not kraken_files:
                section_data['status'] = 'MISSING'
                section_data['message'] = 'No Kraken2 files found'
            
        except Exception as e:
            section_data['status'] = 'ERROR'
            section_data['error'] = str(e)
        
        with open('taxonomy_section.json', 'w') as f:
            json.dump(section_data, f, indent=2)
        """
    }
}

/**
 * Generate assembly section with error handling
 */
def generateAssemblySection(assembly_outputs) {
    return process {
        tag "assembly_section"
        label 'process_low'
        
        input:
        path assembly_files from assembly_outputs
        
        output:
        path "assembly_section.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        import os
        
        section_data = {
            'name': 'Assembly Results',
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'timestamp': '$(date -Iseconds)'
        }
        
        try:
            # Process assembly files
            assembly_files = []
            for root, dirs, files in os.walk('.'):
                for file in files:
                    if file.endswith(('.fa', '.fasta', '.fna')):
                        file_path = os.path.join(root, file)
                        file_info = {
                            'name': file,
                            'path': file_path,
                            'size': os.path.getsize(file_path)
                        }
                        assembly_files.append(file_info)
            
            section_data['files'] = assembly_files
            section_data['summary'] = {
                'total_files': len(assembly_files),
                'total_size': sum(f['size'] for f in assembly_files),
                'assemblers': list(set([
                    'MEGAHIT' if 'megahit' in f['name'].lower() else
                    'MetaSPAdes' if 'spades' in f['name'].lower() else
                    'Hybrid' if 'hybrid' in f['name'].lower() else 'Unknown'
                    for f in assembly_files
                ]))
            }
            
            if not assembly_files:
                section_data['status'] = 'MISSING'
                section_data['message'] = 'No assembly files found'
            
        except Exception as e:
            section_data['status'] = 'ERROR'
            section_data['error'] = str(e)
        
        with open('assembly_section.json', 'w') as f:
            json.dump(section_data, f, indent=2)
        """
    }
}

/**
 * Generate viral analysis section with error handling
 */
def generateViralSection(checkv_outputs, virfinder_full_outputs, virfinder_filtered_outputs) {
    return process {
        tag "viral_section"
        label 'process_low'
        
        input:
        path checkv_files from checkv_outputs
        path virfinder_full_files from virfinder_full_outputs
        path virfinder_filtered_files from virfinder_filtered_outputs
        
        output:
        path "viral_section.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        import os
        
        section_data = {
            'name': 'Viral Analysis',
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'timestamp': '$(date -Iseconds)'
        }
        
        try:
            # Process viral analysis files
            viral_files = []
            
            # Collect all viral analysis files
            for root, dirs, files in os.walk('.'):
                for file in files:
                    if file.endswith(('.tsv', '.txt', '.csv', '.fasta')):
                        file_path = os.path.join(root, file)
                        file_info = {
                            'name': file,
                            'path': file_path,
                            'size': os.path.getsize(file_path),
                            'type': 'checkv' if 'checkv' in root else 
                                   'virfinder_full' if 'virfinder_full' in root else
                                   'virfinder_filtered' if 'virfinder_filtered' in root else 'unknown'
                        }
                        viral_files.append(file_info)
            
            section_data['files'] = viral_files
            section_data['summary'] = {
                'total_files': len(viral_files),
                'checkv_files': len([f for f in viral_files if f['type'] == 'checkv']),
                'virfinder_full_files': len([f for f in viral_files if f['type'] == 'virfinder_full']),
                'virfinder_filtered_files': len([f for f in viral_files if f['type'] == 'virfinder_filtered']),
                'total_size': sum(f['size'] for f in viral_files)
            }
            
            if not viral_files:
                section_data['status'] = 'SKIPPED'
                section_data['message'] = 'No viral analysis files found'
            
        except Exception as e:
            section_data['status'] = 'ERROR'
            section_data['error'] = str(e)
        
        with open('viral_section.json', 'w') as f:
            json.dump(section_data, f, indent=2)
        """
    }
}

/**
 * Generate annotation section with error handling
 */
def generateAnnotationSection(blast_outputs) {
    return process {
        tag "annotation_section"
        label 'process_low'
        
        input:
        path blast_files from blast_outputs
        
        output:
        path "annotation_section.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        import os
        
        section_data = {
            'name': 'Functional Annotation',
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'timestamp': '$(date -Iseconds)'
        }
        
        try:
            # Process BLAST files
            blast_files = []
            for root, dirs, files in os.walk('.'):
                for file in files:
                    if file.endswith(('.txt', '.tsv', '.xml', '.out')):
                        file_path = os.path.join(root, file)
                        file_info = {
                            'name': file,
                            'path': file_path,
                            'size': os.path.getsize(file_path)
                        }
                        blast_files.append(file_info)
            
            section_data['files'] = blast_files
            section_data['summary'] = {
                'total_files': len(blast_files),
                'total_size': sum(f['size'] for f in blast_files),
                'databases': list(set([
                    'NCBI NT' if 'nt' in f['name'].lower() else
                    'NCBI NR' if 'nr' in f['name'].lower() else
                    'Viral' if 'virus' in f['name'].lower() else 'Unknown'
                    for f in blast_files
                ]))
            }
            
            if not blast_files:
                section_data['status'] = 'SKIPPED'
                section_data['message'] = 'No BLAST annotation files found'
            
        except Exception as e:
            section_data['status'] = 'ERROR'
            section_data['error'] = str(e)
        
        with open('annotation_section.json', 'w') as f:
            json.dump(section_data, f, indent=2)
        """
    }
}

/**
 * Generate coverage section with error handling
 */
def generateCoverageSection(coverage_outputs) {
    return process {
        tag "coverage_section"
        label 'process_low'
        
        input:
        path coverage_files from coverage_outputs
        
        output:
        path "coverage_section.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        import os
        
        section_data = {
            'name': 'Coverage Analysis',
            'status': 'SUCCESS',
            'files': [],
            'summary': {},
            'timestamp': '$(date -Iseconds)'
        }
        
        try:
            # Process coverage files
            coverage_files = []
            for root, dirs, files in os.walk('.'):
                for file in files:
                    if file.endswith(('.txt', '.tsv', '.cov', '.png', '.pdf')):
                        file_path = os.path.join(root, file)
                        file_info = {
                            'name': file,
                            'path': file_path,
                            'size': os.path.getsize(file_path)
                        }
                        coverage_files.append(file_info)
            
            section_data['files'] = coverage_files
            section_data['summary'] = {
                'total_files': len(coverage_files),
                'data_files': len([f for f in coverage_files if f['name'].endswith(('.txt', '.tsv', '.cov'))]),
                'plot_files': len([f for f in coverage_files if f['name'].endswith(('.png', '.pdf'))]),
                'total_size': sum(f['size'] for f in coverage_files)
            }
            
            if not coverage_files:
                section_data['status'] = 'SKIPPED'
                section_data['message'] = 'No coverage analysis files found'
            
        except Exception as e:
            section_data['status'] = 'ERROR'
            section_data['error'] = str(e)
        
        with open('coverage_section.json', 'w') as f:
            json.dump(section_data, f, indent=2)
        """
    }
}

/**
 * Combine report sections with status tracking
 */
def combineReportSections(quality_section, taxonomy_section, assembly_section, 
                         viral_section, annotation_section, coverage_section) {
    return process {
        tag "combine_sections"
        label 'process_low'
        
        input:
        path quality from quality_section
        path taxonomy from taxonomy_section
        path assembly from assembly_section
        path viral from viral_section
        path annotation from annotation_section
        path coverage from coverage_section
        
        output:
        path "combined_sections.json"
        
        script:
        """
        #!/usr/bin/env python3
        import json
        
        combined_data = {
            'sections': {},
            'summary': {
                'total_sections': 0,
                'successful_sections': 0,
                'failed_sections': 0,
                'missing_sections': 0,
                'skipped_sections': 0
            },
            'timestamp': '$(date -Iseconds)'
        }
        
        section_files = [
            ('quality', '${quality}'),
            ('taxonomy', '${taxonomy}'),
            ('assembly', '${assembly}'),
            ('viral', '${viral}'),
            ('annotation', '${annotation}'),
            ('coverage', '${coverage}')
        ]
        
        for section_name, section_file in section_files:
            try:
                with open(section_file, 'r') as f:
                    section_data = json.load(f)
                    combined_data['sections'][section_name] = section_data
                    combined_data['summary']['total_sections'] += 1
                    
                    if section_data['status'] == 'SUCCESS':
                        combined_data['summary']['successful_sections'] += 1
                    elif section_data['status'] == 'ERROR':
                        combined_data['summary']['failed_sections'] += 1
                    elif section_data['status'] == 'MISSING':
                        combined_data['summary']['missing_sections'] += 1
                    elif section_data['status'] == 'SKIPPED':
                        combined_data['summary']['skipped_sections'] += 1
                        
            except Exception as e:
                print(f"Error processing {section_name}: {e}")
                combined_data['sections'][section_name] = {
                    'name': section_name,
                    'status': 'ERROR',
                    'error': str(e)
                }
                combined_data['summary']['failed_sections'] += 1
        
        # Calculate success rate
        total = combined_data['summary']['total_sections']
        successful = combined_data['summary']['successful_sections']
        combined_data['summary']['success_rate'] = round((successful / total * 100), 1) if total > 0 else 0
        
        with open('combined_sections.json', 'w') as f:
            json.dump(combined_data, f, indent=2)
        """
    }
}