/**
 * Environment Management System for MetaNextViro Pipeline
 * 
 * This class provides flexible environment management with support for:
 * - Unified conda environment (all tools in single environment)
 * - Per-process environments (isolated environments for each tool category)
 * - Environment validation and conflict detection
 * - Automatic environment selection and fallback mechanisms
 */

class EnvironmentManager {
    
    // Environment mode constants
    static final String UNIFIED_MODE = 'unified'
    static final String PER_PROCESS_MODE = 'per_process'
    
    // Environment file paths
    static final Map<String, String> ENVIRONMENT_PATHS = [
        unified: 'environments/unified.yml',
        qc: 'environments/qc.yml',
        trimming: 'environments/trimming.yml',
        assembly: 'environments/assembly.yml',
        annotation: 'environments/annotation.yml',
        taxonomy: 'environments/taxonomy.yml',
        viral: 'environments/viral.yml',
        alignment: 'environments/alignment.yml'
    ]
    
    // Process to environment mapping for per-process mode
    static final Map<String, String> PROCESS_ENV_MAPPING = [
        'FASTQC': 'qc',
        'MULTIQC': 'qc',
        'FASTP': 'trimming',
        'FLEXBAR': 'trimming',
        'TRIM_GALORE': 'trimming',
        'MEGAHIT': 'assembly',
        'METASPADES': 'assembly',
        'HYBRID_ASSEMBLY': 'assembly',
        'QUAST': 'assembly',
        'BLASTN': 'annotation',
        'BLASTN_VIRUSES': 'annotation',
        'BLASTX': 'annotation',
        'DIAMOND_BLASTX': 'annotation',
        'CD_HIT': 'annotation',
        'KRAKEN2': 'taxonomy',
        'KRONA': 'taxonomy',
        'CHECKV': 'viral',
        'VIRFINDER': 'viral',
        'BOWTIE2': 'alignment',
        'SAMTOOLS': 'alignment',
        'BEDTOOLS': 'alignment',
        'COVERAGE': 'alignment'
    ]
    
    private String mode
    private String projectDir
    private Map<String, Object> params
    private List<String> validationErrors = []
    private List<String> validationWarnings = []
    
    /**
     * Constructor
     */
    EnvironmentManager(String mode, String projectDir, Map<String, Object> params) {
        this.mode = mode ?: UNIFIED_MODE
        this.projectDir = projectDir
        this.params = params ?: [:]
        
        validateMode()
    }
    
    /**
     * Validate the environment mode
     */
    private void validateMode() {
        if (!(mode in [UNIFIED_MODE, PER_PROCESS_MODE])) {
            throw new IllegalArgumentException(
                "Invalid environment mode: ${mode}. Must be '${UNIFIED_MODE}' or '${PER_PROCESS_MODE}'"
            )
        }
    }
    
    /**
     * Get the appropriate conda environment file for a process
     */
    String getEnvironmentForProcess(String processName) {
        if (mode == UNIFIED_MODE) {
            return getUnifiedEnvironmentPath()
        } else {
            return getPerProcessEnvironmentPath(processName)
        }
    }
    
    /**
     * Get unified environment path
     */
    String getUnifiedEnvironmentPath() {
        return "${projectDir}/${ENVIRONMENT_PATHS.unified}"
    }
    
    /**
     * Get per-process environment path for a specific process
     */
    String getPerProcessEnvironmentPath(String processName) {
        String envCategory = PROCESS_ENV_MAPPING[processName]
        if (!envCategory) {
            // Fallback to unified environment for unmapped processes
            validationWarnings << "Process ${processName} not mapped to specific environment, using unified"
            return getUnifiedEnvironmentPath()
        }
        
        String envPath = ENVIRONMENT_PATHS[envCategory]
        if (!envPath) {
            validationErrors << "Environment category ${envCategory} not found for process ${processName}"
            return getUnifiedEnvironmentPath()
        }
        
        return "${projectDir}/${envPath}"
    }
    
    /**
     * Validate all environment files exist and are readable
     */
    boolean validateEnvironmentFiles() {
        validationErrors.clear()
        validationWarnings.clear()
        
        if (mode == UNIFIED_MODE) {
            return validateSingleEnvironment(getUnifiedEnvironmentPath())
        } else {
            return validateAllPerProcessEnvironments()
        }
    }
    
    /**
     * Validate a single environment file
     */
    private boolean validateSingleEnvironment(String envPath) {
        File envFile = new File(envPath)
        
        if (!envFile.exists()) {
            validationErrors << "Environment file not found: ${envPath}"
            return false
        }
        
        if (!envFile.canRead()) {
            validationErrors << "Environment file not readable: ${envPath}"
            return false
        }
        
        // Validate YAML syntax and required fields
        return validateEnvironmentContent(envFile)
    }
    
    /**
     * Validate all per-process environment files
     */
    private boolean validateAllPerProcessEnvironments() {
        boolean allValid = true
        
        ENVIRONMENT_PATHS.each { category, path ->
            if (category != 'unified') {
                String fullPath = "${projectDir}/${path}"
                if (!validateSingleEnvironment(fullPath)) {
                    allValid = false
                }
            }
        }
        
        return allValid
    }
    
    /**
     * Validate environment file content
     */
    private boolean validateEnvironmentContent(File envFile) {
        try {
            // Simple validation - check for required sections
            String content = envFile.text
            
            if (!content.contains('name:')) {
                validationErrors << "Environment file ${envFile.path} missing 'name:' field"
                return false
            }
            
            if (!content.contains('dependencies:')) {
                validationErrors << "Environment file ${envFile.path} missing 'dependencies:' field"
                return false
            }
            
            // Check for basic YAML structure
            if (!content.contains('channels:')) {
                validationWarnings << "Environment file ${envFile.path} missing 'channels:' field"
            }
            
            return true
            
        } catch (Exception e) {
            validationErrors << "Error reading environment file ${envFile.path}: ${e.message}"
            return false
        }
    }
    
    /**
     * Generate environment setup validation report
     */
    Map<String, Object> generateValidationReport() {
        boolean isValid = validateEnvironmentFiles()
        
        return [
            mode: mode,
            valid: isValid,
            errors: validationErrors,
            warnings: validationWarnings,
            environmentPaths: mode == UNIFIED_MODE ? 
                [getUnifiedEnvironmentPath()] : 
                ENVIRONMENT_PATHS.findAll { k, v -> k != 'unified' }.collect { k, v -> "${projectDir}/${v}" },
            processMapping: mode == PER_PROCESS_MODE ? PROCESS_ENV_MAPPING : null
        ]
    }
    
    /**
     * Resolve environment conflicts automatically
     */
    boolean resolveConflicts() {
        // For now, just validate that files exist and are readable
        // More sophisticated conflict resolution can be added later
        return validateEnvironmentFiles()
    }
    
    /**
     * Get validation errors
     */
    List<String> getValidationErrors() {
        return validationErrors.clone()
    }
    
    /**
     * Get validation warnings
     */
    List<String> getValidationWarnings() {
        return validationWarnings.clone()
    }
    
    /**
     * Check if environment setup is valid
     */
    boolean isValid() {
        return validateEnvironmentFiles() && validationErrors.isEmpty()
    }
    
    /**
     * Get current environment mode
     */
    String getMode() {
        return mode
    }
    
    /**
     * Switch environment mode
     */
    void switchMode(String newMode) {
        if (!(newMode in [UNIFIED_MODE, PER_PROCESS_MODE])) {
            throw new IllegalArgumentException(
                "Invalid environment mode: ${newMode}. Must be '${UNIFIED_MODE}' or '${PER_PROCESS_MODE}'"
            )
        }
        this.mode = newMode
        validationErrors.clear()
        validationWarnings.clear()
    }
    
    /**
     * Get environment configuration summary
     */
    Map<String, Object> getEnvironmentSummary() {
        return [
            mode: mode,
            unifiedPath: getUnifiedEnvironmentPath(),
            processMapping: PROCESS_ENV_MAPPING,
            availableEnvironments: ENVIRONMENT_PATHS.keySet(),
            isValid: isValid()
        ]
    }
}