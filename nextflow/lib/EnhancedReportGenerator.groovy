/**
 * Enhanced Report Generation System for MetaNextViro Pipeline
 * 
 * This module provides robust report generation with error handling,
 * graceful degradation, and process failure tracking.
 */

/**
 * Enhanced report generator with error recovery and graceful degradation
 */
class EnhancedReportGenerator {
    private ProcessFailureTracker failureTracker
    private Map<String, ReportSection> sections = [:]
    private boolean allowPartialReports = true
    private String outputDir
    
    EnhancedReportGenerator(ProcessFailureTracker failureTracker, String outputDir) {
        this.failureTracker = failureTracker
        this.outputDir = outputDir
        initializeReportSections()
    }
    
    /**
     * Generate comprehensive report with error handling
     */
    Map generateReport(Map allOutputs) {
        def reportData = [
            metadata: generateMetadata(),
            summary: generateSummary(),
            sections: [:],
            failures: failureTracker.generateFailureReport(),
            status: 'COMPLETED'
        ]
        
        // Generate each section with error handling
        sections.each { sectionName, section ->
            try {
                def sectionData = section.generate(allOutputs[sectionName])
                reportData.sections[sectionName] = sectionData
                
                if (sectionData.status == 'ERROR' && section.required) {
                    reportData.status = 'PARTIAL'
                }
            } catch (Exception e) {
                def errorSection = handleSectionError(sectionName, e, section.required)
                reportData.sections[sectionName] = errorSection
                
                if (section.required) {
                    reportData.status = 'PARTIAL'
                }
            }
        }
        
        // Check if report generation was successful
        if (reportData.sections.values().any { it.status == 'ERROR' && it.required }) {
            reportData.status = 'FAILED'
        }
        
        return reportData
    }
    
    /**
     * Generate HTML report with enhanced error information
     */
    String generateHTMLReport(Map reportData) {
        def html = new StringBuilder()
        
        // HTML header with enhanced styling
        html << generateHTMLHeader()
        
        // Report metadata and summary
        html << generateHTMLSummary(reportData)
        
        // Failure summary if there are failures
        if (reportData.failures.failures) {
            html << generateHTMLFailureSummary(reportData.failures)
        }
        
        // Generate sections
        reportData.sections.each { sectionName, sectionData ->
            html << generateHTMLSection(sectionName, sectionData)
        }
        
        // Footer
        html << generateHTMLFooter(reportData)
        
        return html.toString()
    }
    
    /**
     * Initialize report sections with their configurations
     */
    private void initializeReportSections() {
        sections['quality'] = new ReportSection(
            name: 'Quality Control',
            description: 'FastQC and quality assessment results',
            required: true,
            icon: '📊'
        ).withGenerator { outputs ->
            generateQualitySection(outputs)
        }
        
        sections['taxonomy'] = new ReportSection(
            name: 'Taxonomic Classification',
            description: 'Kraken2 taxonomic profiling results',
            required: true,
            icon: '🦠'
        ).withGenerator { outputs ->
            generateTaxonomySection(outputs)
        }
        
        sections['assembly'] = new ReportSection(
            name: 'Assembly Results',
            description: 'Genome assembly statistics and results',
            required: true,
            icon: '🧩'
        ).withGenerator { outputs ->
            generateAssemblySection(outputs)
        }
        
        sections['viral'] = new ReportSection(
            name: 'Viral Analysis',
            description: 'CheckV and VirFinder viral genome analysis',
            required: false,
            icon: '🔍'
        ).withGenerator { outputs ->
            generateViralSection(outputs)
        }
        
        sections['annotation'] = new ReportSection(
            name: 'Functional Annotation',
            description: 'BLAST annotation and functional analysis',
            required: false,
            icon: '🔬'
        ).withGenerator { outputs ->
            generateAnnotationSection(outputs)
        }
        
        sections['coverage'] = new ReportSection(
            name: 'Coverage Analysis',
            description: 'Read coverage and depth analysis',
            required: false,
            icon: '📈'
        ).withGenerator { outputs ->
            generateCoverageSection(outputs)
        }
    }
    
    /**
     * Handle section generation errors with graceful degradation
     */
    private Map handleSectionError(String sectionName, Exception error, boolean required) {
        def errorSection = [
            name: sectionName,
            status: 'ERROR',
            required: required,
            error: error.message,
            content: generateErrorContent(sectionName, error, required),
            timestamp: new Date()
        ]
        
        // Log the error
        println "⚠️  Error generating ${sectionName} section: ${error.message}"
        
        if (!required && allowPartialReports) {
            errorSection.content = generateSkippedContent(sectionName, "Section skipped due to error: ${error.message}")
            errorSection.status = 'SKIPPED'
        }
        
        return errorSection
    }
    
    /**
     * Generate quality control section
     */
    private Map generateQualitySection(def outputs) {
        def section = [
            name: 'Quality Control',
            status: 'SUCCESS',
            files: [],
            summary: [:],
            content: ''
        ]
        
        if (!outputs || (outputs instanceof Collection && outputs.isEmpty())) {
            return generateMissingSection('Quality Control', 'No FastQC reports available')
        }
        
        // Process FastQC outputs
        def fastqcFiles = collectFiles(outputs, ['html', 'zip'])
        section.files = fastqcFiles
        
        // Generate summary statistics
        section.summary = [
            totalSamples: fastqcFiles.count { it.name.contains('_fastqc.html') },
            passedQC: 0, // Would need to parse FastQC results
            warnings: 0,
            failures: 0
        ]
        
        section.content = generateQualityHTML(fastqcFiles)
        
        return section
    }
    
    /**
     * Generate taxonomy section
     */
    private Map generateTaxonomySection(def outputs) {
        def section = [
            name: 'Taxonomic Classification',
            status: 'SUCCESS',
            files: [],
            summary: [:],
            content: ''
        ]
        
        if (!outputs || (outputs instanceof Collection && outputs.isEmpty())) {
            return generateMissingSection('Taxonomic Classification', 'No Kraken2 results available')
        }
        
        def krakenFiles = collectFiles(outputs, ['report', 'txt', 'kraken'])
        section.files = krakenFiles
        
        section.summary = [
            totalClassified: 0, // Would parse from Kraken2 reports
            topTaxa: [],
            unclassified: 0
        ]
        
        section.content = generateTaxonomyHTML(krakenFiles)
        
        return section
    }
    
    /**
     * Generate assembly section
     */
    private Map generateAssemblySection(def outputs) {
        def section = [
            name: 'Assembly Results',
            status: 'SUCCESS',
            files: [],
            summary: [:],
            content: ''
        ]
        
        if (!outputs || (outputs instanceof Collection && outputs.isEmpty())) {
            return generateMissingSection('Assembly Results', 'No assembly results available')
        }
        
        def assemblyFiles = collectFiles(outputs, ['fa', 'fasta', 'log', 'txt'])
        section.files = assemblyFiles
        
        section.summary = [
            totalContigs: 0, // Would parse from assembly files
            n50: 0,
            totalLength: 0,
            assemblers: []
        ]
        
        section.content = generateAssemblyHTML(assemblyFiles)
        
        return section
    }
    
    /**
     * Generate viral analysis section
     */
    private Map generateViralSection(def outputs) {
        def section = [
            name: 'Viral Analysis',
            status: 'SUCCESS',
            files: [],
            summary: [:],
            content: ''
        ]
        
        if (!outputs || (outputs instanceof Collection && outputs.isEmpty())) {
            return generateSkippedSection('Viral Analysis', 'Viral analysis was not performed or failed')
        }
        
        def viralFiles = collectFiles(outputs, ['tsv', 'txt', 'csv'])
        section.files = viralFiles
        
        section.summary = [
            viralContigs: 0, // Would parse from CheckV/VirFinder results
            highConfidence: 0,
            mediumConfidence: 0,
            lowConfidence: 0
        ]
        
        section.content = generateViralHTML(viralFiles)
        
        return section
    }
    
    /**
     * Generate annotation section
     */
    private Map generateAnnotationSection(def outputs) {
        def section = [
            name: 'Functional Annotation',
            status: 'SUCCESS',
            files: [],
            summary: [:],
            content: ''
        ]
        
        if (!outputs || (outputs instanceof Collection && outputs.isEmpty())) {
            return generateSkippedSection('Functional Annotation', 'BLAST annotation was not performed or failed')
        }
        
        def blastFiles = collectFiles(outputs, ['txt', 'tsv', 'xml'])
        section.files = blastFiles
        
        section.summary = [
            annotatedContigs: 0, // Would parse from BLAST results
            topHits: [],
            databases: []
        ]
        
        section.content = generateAnnotationHTML(blastFiles)
        
        return section
    }
    
    /**
     * Generate coverage section
     */
    private Map generateCoverageSection(def outputs) {
        def section = [
            name: 'Coverage Analysis',
            status: 'SUCCESS',
            files: [],
            summary: [:],
            content: ''
        ]
        
        if (!outputs || (outputs instanceof Collection && outputs.isEmpty())) {
            return generateSkippedSection('Coverage Analysis', 'Coverage analysis was not performed or failed')
        }
        
        def coverageFiles = collectFiles(outputs, ['txt', 'tsv', 'png', 'pdf'])
        section.files = coverageFiles
        
        section.summary = [
            meanCoverage: 0, // Would parse from coverage files
            coverageBreadth: 0,
            plots: coverageFiles.count { it.name.endsWith('.png') || it.name.endsWith('.pdf') }
        ]
        
        section.content = generateCoverageHTML(coverageFiles)
        
        return section
    }
    
    /**
     * Generate missing section placeholder
     */
    private Map generateMissingSection(String sectionName, String reason) {
        return [
            name: sectionName,
            status: 'MISSING',
            required: sections[sectionName.toLowerCase().replaceAll(' ', '')]?.required ?: false,
            reason: reason,
            content: "<div class='missing-section'><p>⚠️ ${reason}</p></div>",
            files: [],
            summary: [:]
        ]
    }
    
    /**
     * Generate skipped section placeholder
     */
    private Map generateSkippedSection(String sectionName, String reason) {
        return [
            name: sectionName,
            status: 'SKIPPED',
            required: false,
            reason: reason,
            content: "<div class='skipped-section'><p>ℹ️ ${reason}</p><p>This is an optional analysis step.</p></div>",
            files: [],
            summary: [:]
        ]
    }
    
    /**
     * Generate error content for failed sections
     */
    private String generateErrorContent(String sectionName, Exception error, boolean required) {
        def content = new StringBuilder()
        content << "<div class='error-section'>"
        content << "<h3>❌ Error in ${sectionName}</h3>"
        content << "<p><strong>Error:</strong> ${error.message}</p>"
        
        if (required) {
            content << "<p><strong>Impact:</strong> This is a required section. The pipeline may have failed.</p>"
            content << "<p><strong>Suggestion:</strong> Check the pipeline logs and ensure all required inputs are available.</p>"
        } else {
            content << "<p><strong>Impact:</strong> This is an optional section. The pipeline can continue without it.</p>"
            content << "<p><strong>Note:</strong> You may re-run the pipeline with different parameters to include this analysis.</p>"
        }
        
        content << "</div>"
        return content.toString()
    }
    
    /**
     * Generate skipped content for optional sections
     */
    private String generateSkippedContent(String sectionName, String reason) {
        return """
        <div class='skipped-section'>
            <h3>ℹ️ ${sectionName} - Skipped</h3>
            <p><strong>Reason:</strong> ${reason}</p>
            <p>This is an optional analysis step that was not completed.</p>
        </div>
        """
    }
    
    /**
     * Collect files from outputs with specific extensions
     */
    private List collectFiles(def outputs, List<String> extensions) {
        def files = []
        
        if (outputs instanceof Collection) {
            outputs.each { output ->
                files.addAll(collectFilesFromPath(output, extensions))
            }
        } else {
            files.addAll(collectFilesFromPath(outputs, extensions))
        }
        
        return files
    }
    
    /**
     * Collect files from a specific path
     */
    private List collectFilesFromPath(def path, List<String> extensions) {
        def files = []
        
        try {
            def file = new File(path.toString())
            if (file.exists()) {
                if (file.isDirectory()) {
                    file.listFiles().each { f ->
                        if (f.isFile() && extensions.any { ext -> f.name.toLowerCase().endsWith(ext.toLowerCase()) }) {
                            files << [name: f.name, path: f.absolutePath, size: f.length()]
                        }
                    }
                } else if (extensions.any { ext -> file.name.toLowerCase().endsWith(ext.toLowerCase()) }) {
                    files << [name: file.name, path: file.absolutePath, size: file.length()]
                }
            }
        } catch (Exception e) {
            println "Warning: Could not process path ${path}: ${e.message}"
        }
        
        return files
    }
    
    /**
     * Generate report metadata
     */
    private Map generateMetadata() {
        return [
            generatedAt: new Date(),
            pipeline: 'MetaNextViro',
            version: '1.0.0', // Would get from pipeline config
            reportGenerator: 'EnhancedReportGenerator',
            outputDir: outputDir
        ]
    }
    
    /**
     * Generate report summary
     */
    private Map generateSummary() {
        def processStatuses = failureTracker.getProcessStatuses()
        
        return [
            totalProcesses: processStatuses.size(),
            completed: processStatuses.count { it.value == ProcessStatus.COMPLETED },
            failed: processStatuses.count { it.value == ProcessStatus.FAILED },
            skipped: processStatuses.count { it.value == ProcessStatus.SKIPPED },
            successRate: processStatuses.size() > 0 ? 
                (processStatuses.count { it.value == ProcessStatus.COMPLETED } / processStatuses.size() * 100).round(1) : 0
        ]
    }
    
    /**
     * Generate HTML header with enhanced styling
     */
    private String generateHTMLHeader() {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>MetaNextViro Enhanced Report</title>
            <style>
                body { 
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
                    margin: 0; 
                    padding: 20px; 
                    line-height: 1.6; 
                    background-color: #f5f7fa;
                }
                .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 15px; margin-bottom: 30px; }
                h2 { color: #34495e; margin-top: 40px; border-left: 4px solid #3498db; padding-left: 15px; }
                h3 { color: #2c3e50; margin-top: 25px; }
                .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
                .summary-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #3498db; }
                .summary-card h4 { margin: 0 0 10px 0; color: #2c3e50; }
                .summary-card .value { font-size: 2em; font-weight: bold; color: #3498db; }
                .section { background: #f8f9fa; padding: 20px; margin: 20px 0; border-radius: 8px; }
                .section.error { border-left: 4px solid #e74c3c; background: #fdf2f2; }
                .section.warning { border-left: 4px solid #f39c12; background: #fef9e7; }
                .section.success { border-left: 4px solid #27ae60; background: #f0f9f4; }
                .section.skipped { border-left: 4px solid #95a5a6; background: #f8f9fa; }
                .file-list { list-style: none; padding: 0; }
                .file-list li { 
                    background: white; 
                    margin: 8px 0; 
                    padding: 12px; 
                    border-radius: 5px; 
                    border-left: 3px solid #3498db;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }
                .file-list a { color: #2980b9; text-decoration: none; font-weight: 500; }
                .file-list a:hover { text-decoration: underline; }
                .file-size { color: #7f8c8d; font-size: 0.9em; }
                .status-badge { 
                    padding: 4px 12px; 
                    border-radius: 20px; 
                    font-size: 0.8em; 
                    font-weight: bold; 
                    text-transform: uppercase;
                }
                .status-success { background: #d4edda; color: #155724; }
                .status-error { background: #f8d7da; color: #721c24; }
                .status-warning { background: #fff3cd; color: #856404; }
                .status-skipped { background: #e2e3e5; color: #383d41; }
                .failure-summary { background: #fdf2f2; border: 1px solid #f5c6cb; border-radius: 8px; padding: 20px; margin: 20px 0; }
                .failure-item { background: white; margin: 10px 0; padding: 15px; border-radius: 5px; border-left: 3px solid #e74c3c; }
                .timestamp { color: #7f8c8d; font-style: italic; font-size: 0.9em; }
                .error-section, .missing-section, .skipped-section { 
                    padding: 20px; 
                    border-radius: 8px; 
                    margin: 15px 0; 
                }
                .error-section { background: #fdf2f2; border: 1px solid #f5c6cb; }
                .missing-section { background: #fff3cd; border: 1px solid #ffeaa7; }
                .skipped-section { background: #e2e3e5; border: 1px solid #ced4da; }
                .progress-bar { 
                    width: 100%; 
                    height: 20px; 
                    background: #ecf0f1; 
                    border-radius: 10px; 
                    overflow: hidden; 
                    margin: 10px 0;
                }
                .progress-fill { 
                    height: 100%; 
                    background: linear-gradient(90deg, #3498db, #2ecc71); 
                    transition: width 0.3s ease;
                }
            </style>
        </head>
        <body>
        <div class="container">
        """
    }
    
    /**
     * Generate HTML summary section
     */
    private String generateHTMLSummary(Map reportData) {
        def summary = reportData.summary
        def metadata = reportData.metadata
        
        def statusClass = reportData.status == 'COMPLETED' ? 'success' : 
                         reportData.status == 'PARTIAL' ? 'warning' : 'error'
        
        return """
        <h1>🧬 MetaNextViro Enhanced Analysis Report</h1>
        
        <div class="section ${statusClass}">
            <h2>📊 Pipeline Summary</h2>
            <div class="summary-grid">
                <div class="summary-card">
                    <h4>Pipeline Status</h4>
                    <div class="value">${reportData.status}</div>
                    <span class="status-badge status-${statusClass}">${reportData.status}</span>
                </div>
                <div class="summary-card">
                    <h4>Success Rate</h4>
                    <div class="value">${summary.successRate}%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${summary.successRate}%"></div>
                    </div>
                </div>
                <div class="summary-card">
                    <h4>Completed Processes</h4>
                    <div class="value">${summary.completed}</div>
                    <small>out of ${summary.totalProcesses} total</small>
                </div>
                <div class="summary-card">
                    <h4>Failed Processes</h4>
                    <div class="value">${summary.failed}</div>
                    <small>${summary.skipped} skipped</small>
                </div>
            </div>
            <p class="timestamp">Generated on: ${metadata.generatedAt}</p>
        </div>
        """
    }
    
    /**
     * Generate HTML failure summary
     */
    private String generateHTMLFailureSummary(Map failures) {
        if (!failures.failures) {
            return ""
        }
        
        def html = new StringBuilder()
        html << """
        <div class="failure-summary">
            <h2>⚠️ Process Failures and Issues</h2>
            <p>The following processes encountered issues during execution:</p>
        """
        
        failures.failures.each { failure ->
            def severityClass = failure.severity.toLowerCase()
            html << """
            <div class="failure-item">
                <h4>${failure.severity == 'CRITICAL' ? '🔴' : '❌'} ${failure.process}</h4>
                <p><strong>Error:</strong> ${failure.message}</p>
                ${failure.suggestion ? "<p><strong>Suggestion:</strong> ${failure.suggestion}</p>" : ""}
                ${failure.recoverable ? "<p><strong>Recovery:</strong> This error may be recoverable by retrying with different parameters.</p>" : ""}
                <p class="timestamp">Occurred at: ${failure.timestamp}</p>
            </div>
            """
        }
        
        html << "</div>"
        return html.toString()
    }
    
    /**
     * Generate HTML section
     */
    private String generateHTMLSection(String sectionName, Map sectionData) {
        def statusClass = sectionData.status.toLowerCase()
        def icon = sections[sectionName]?.icon ?: '📄'
        
        def html = new StringBuilder()
        html << """
        <div class="section ${statusClass}">
            <h2>${icon} ${sectionData.name}</h2>
            <span class="status-badge status-${statusClass}">${sectionData.status}</span>
        """
        
        if (sectionData.content) {
            html << sectionData.content
        }
        
        if (sectionData.files) {
            html << "<h3>📁 Generated Files</h3>"
            html << "<ul class='file-list'>"
            sectionData.files.each { file ->
                def fileSize = file.size ? formatFileSize(file.size) : ""
                html << """
                <li>
                    <a href='${file.name}'>📄 ${file.name}</a>
                    <span class='file-size'>${fileSize}</span>
                </li>
                """
            }
            html << "</ul>"
        }
        
        html << "</div>"
        return html.toString()
    }
    
    /**
     * Generate HTML footer
     */
    private String generateHTMLFooter(Map reportData) {
        return """
        <hr style="margin: 40px 0; border: none; border-top: 2px solid #ecf0f1;">
        <div class="section">
            <p><em>📋 Report generated by MetaNextViro Enhanced Pipeline</em></p>
            <p><em>🔗 For more information, visit: <a href="https://github.com/navduhan/metanextviro">https://github.com/navduhan/metanextviro</a></em></p>
            <p class="timestamp">Report generated at: ${reportData.metadata.generatedAt}</p>
        </div>
        </div>
        </body>
        </html>
        """
    }
    
    /**
     * Format file size for display
     */
    private String formatFileSize(long bytes) {
        if (bytes < 1024) return "${bytes} B"
        if (bytes < 1024 * 1024) return "${(bytes / 1024).round(1)} KB"
        if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).round(1)} MB"
        return "${(bytes / (1024 * 1024 * 1024)).round(1)} GB"
    }
    
    // Placeholder methods for specific section HTML generation
    private String generateQualityHTML(List files) { return "<p>Quality control files processed: ${files.size()}</p>" }
    private String generateTaxonomyHTML(List files) { return "<p>Taxonomy files processed: ${files.size()}</p>" }
    private String generateAssemblyHTML(List files) { return "<p>Assembly files processed: ${files.size()}</p>" }
    private String generateViralHTML(List files) { return "<p>Viral analysis files processed: ${files.size()}</p>" }
    private String generateAnnotationHTML(List files) { return "<p>Annotation files processed: ${files.size()}</p>" }
    private String generateCoverageHTML(List files) { return "<p>Coverage files processed: ${files.size()}</p>" }
}

/**
 * Report section configuration
 */
class ReportSection {
    String name
    String description
    boolean required = true
    String icon = '📄'
    Closure generator
    
    ReportSection withGenerator(Closure generator) {
        this.generator = generator
        return this
    }
    
    Map generate(def outputs) {
        if (generator) {
            return generator.call(outputs)
        }
        return [
            name: name,
            status: 'ERROR',
            content: 'No generator defined for this section',
            files: [],
            summary: [:]
        ]
    }
}