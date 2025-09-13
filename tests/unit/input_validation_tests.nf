#!/usr/bin/env nextflow

/**
 * Unit Tests for Input Validation Functions
 * 
 * Tests the InputValidator class and validation workflows
 * Requirements: 1.1, 1.2, 1.3
 */

nextflow.enable.dsl = 2

include { InputValidator; ValidationResult } from '../../nextflow/lib/InputValidator.groovy'

workflow TEST_INPUT_VALIDATION {
    main:
    
    def testResults = [
        tests: [],
        summary: ""
    ]
    
    // Test 1: File Format Validation
    testResults.tests << testFileFormatValidation()
    
    // Test 2: Samplesheet Column Validation
    testResults.tests << testSamplesheetColumnValidation()
    
    // Test 3: Sample Row Validation
    testResults.tests << testSampleRowValidation()
    
    // Test 4: Input File Validation
    testResults.tests << testInputFileValidation()
    
    // Test 5: Database Validation
    testResults.tests << testDatabaseValidation()
    
    // Test 6: Adapter File Validation
    testResults.tests << testAdapterFileValidation()
    
    // Test 7: ValidationResult Class
    testResults.tests << testValidationResultClass()
    
    // Test 8: CSV Parsing
    testResults.tests << testCsvParsing()
    
    // Generate summary
    def passed = testResults.tests.count { it.passed }
    def total = testResults.tests.size()
    testResults.summary = "${passed}/${total} tests passed"
    
    emit:
    results = testResults
}

def testFileFormatValidation() {
    def testName = "File Format Validation"
    
    try {
        // Create test files
        def testDir = new File("test_input_validation")
        testDir.mkdirs()
        
        def csvFile = new File(testDir, "test.csv")
        csvFile.text = "sample,fastq_1,fastq_2\n"
        
        def tsvFile = new File(testDir, "test.tsv")
        tsvFile.text = "sample\tfastq_1\tfastq_2\n"
        
        def txtFile = new File(testDir, "test.txt")
        txtFile.text = "invalid format\n"
        
        // Test valid CSV format
        def csvResult = InputValidator.validateFileFormat(csvFile.absolutePath)
        assert csvResult.isValid() : "CSV format should be valid"
        assert csvResult.info.any { it.contains("CSV") } : "Should indicate CSV format"
        
        // Test valid TSV format
        def tsvResult = InputValidator.validateFileFormat(tsvFile.absolutePath)
        assert tsvResult.isValid() : "TSV format should be valid"
        assert tsvResult.info.any { it.contains("TSV") } : "Should indicate TSV format"
        
        // Test invalid format
        def txtResult = InputValidator.validateFileFormat(txtFile.absolutePath)
        assert !txtResult.isValid() : "TXT format should be invalid"
        assert txtResult.errors.any { it.contains("Unsupported file format") } : "Should indicate unsupported format"
        assert txtResult.suggestions.any { it.contains("convert") } : "Should suggest conversion"
        
        // Test null input
        def nullResult = InputValidator.validateFileFormat(null)
        assert !nullResult.isValid() : "Null input should be invalid"
        assert nullResult.errors.any { it.contains("null or empty") } : "Should indicate null input"
        
        // Test nonexistent file
        def nonexistentResult = InputValidator.validateFileFormat("/nonexistent/file.csv")
        assert !nonexistentResult.isValid() : "Nonexistent file should be invalid"
        assert nonexistentResult.errors.any { it.contains("does not exist") } : "Should indicate file not found"
        
        // Cleanup
        testDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testSamplesheetColumnValidation() {
    def testName = "Samplesheet Column Validation"
    
    try {
        // Test valid columns
        def validColumns = ['sample', 'fastq_1', 'fastq_2']
        def validResult = InputValidator.validateColumns(validColumns)
        assert validResult.isValid() : "Valid columns should pass validation"
        assert validResult.info.any { it.contains("Column validation passed") } : "Should indicate success"
        
        // Test valid columns with optional
        def validWithOptional = ['sample', 'fastq_1', 'fastq_2', 'single_end']
        def validOptionalResult = InputValidator.validateColumns(validWithOptional)
        assert validOptionalResult.isValid() : "Valid columns with optional should pass"
        
        // Test missing required columns
        def missingRequired = ['sample', 'fastq_1']  // Missing fastq_2
        def missingResult = InputValidator.validateColumns(missingRequired)
        assert !missingResult.isValid() : "Missing required columns should fail"
        assert missingResult.errors.any { it.contains("Missing required columns") } : "Should indicate missing columns"
        assert missingResult.suggestions.any { it.contains("Required columns are") } : "Should list required columns"
        
        // Test unknown columns
        def unknownColumns = ['sample', 'fastq_1', 'fastq_2', 'unknown_column']
        def unknownResult = InputValidator.validateColumns(unknownColumns)
        assert unknownResult.isValid() : "Unknown columns should not fail validation"
        assert unknownResult.warnings.any { it.contains("Unknown columns") } : "Should warn about unknown columns"
        
        // Test empty columns
        def emptyResult = InputValidator.validateColumns([])
        assert !emptyResult.isValid() : "Empty columns should fail"
        assert emptyResult.errors.any { it.contains("No columns found") } : "Should indicate no columns"
        
        // Test null columns
        def nullResult = InputValidator.validateColumns(null)
        assert !nullResult.isValid() : "Null columns should fail"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testSampleRowValidation() {
    def testName = "Sample Row Validation"
    
    try {
        // Create test directory and files
        def testDir = new File("test_sample_validation")
        testDir.mkdirs()
        
        def fastq1 = new File(testDir, "sample1_R1.fastq.gz")
        fastq1.text = "test"
        def fastq2 = new File(testDir, "sample1_R2.fastq.gz")
        fastq2.text = "test"
        
        // Test valid rows
        def validRows = [
            [sample: 'sample1', fastq_1: fastq1.absolutePath, fastq_2: fastq2.absolutePath],
            [sample: 'sample2', fastq_1: fastq1.absolutePath, fastq_2: fastq2.absolutePath]
        ]
        
        def validResult = InputValidator.validateSampleRows(validRows)
        assert validResult.isValid() : "Valid rows should pass validation"
        
        // Test duplicate sample names
        def duplicateRows = [
            [sample: 'sample1', fastq_1: fastq1.absolutePath, fastq_2: fastq2.absolutePath],
            [sample: 'sample1', fastq_1: fastq1.absolutePath, fastq_2: fastq2.absolutePath]
        ]
        
        def duplicateResult = InputValidator.validateSampleRows(duplicateRows)
        assert !duplicateResult.isValid() : "Duplicate sample names should fail"
        assert duplicateResult.errors.any { it.contains("Duplicate sample name") } : "Should indicate duplicate names"
        
        // Test empty sample name
        def emptyNameRows = [
            [sample: '', fastq_1: fastq1.absolutePath, fastq_2: fastq2.absolutePath]
        ]
        
        def emptyNameResult = InputValidator.validateSampleRows(emptyNameRows)
        assert !emptyNameResult.isValid() : "Empty sample name should fail"
        assert emptyNameResult.errors.any { it.contains("Sample name cannot be empty") } : "Should indicate empty name"
        
        // Test missing files
        def missingFileRows = [
            [sample: 'sample1', fastq_1: '/nonexistent/file.fastq', fastq_2: fastq2.absolutePath]
        ]
        
        def missingFileResult = InputValidator.validateSampleRows(missingFileRows)
        assert !missingFileResult.isValid() : "Missing files should fail"
        assert missingFileResult.errors.any { it.contains("does not exist") } : "Should indicate missing file"
        
        // Test invalid single_end values
        def invalidSingleEndRows = [
            [sample: 'sample1', fastq_1: fastq1.absolutePath, fastq_2: fastq2.absolutePath, single_end: 'maybe']
        ]
        
        def invalidSingleEndResult = InputValidator.validateSampleRows(invalidSingleEndRows)
        assert invalidSingleEndResult.warnings.any { it.contains("Invalid single_end value") } : "Should warn about invalid single_end"
        
        // Cleanup
        testDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testInputFileValidation() {
    def testName = "Input File Validation"
    
    try {
        // Create test files
        def testDir = new File("test_file_validation")
        testDir.mkdirs()
        
        def validFastq = new File(testDir, "sample.fastq.gz")
        validFastq.text = "test"
        
        def invalidExtension = new File(testDir, "sample.txt")
        invalidExtension.text = "test"
        
        // Test valid FASTQ file
        def validResult = InputValidator.validateInputFile(validFastq.absolutePath, "fastq_1", 1)
        assert validResult.isValid() : "Valid FASTQ file should pass"
        
        // Test file with invalid extension
        def invalidExtResult = InputValidator.validateInputFile(invalidExtension.absolutePath, "fastq_1", 1)
        assert invalidExtResult.isValid() : "File with invalid extension should still pass validation"
        assert invalidExtResult.warnings.any { it.contains("does not have a standard FASTQ extension") } : "Should warn about extension"
        
        // Test nonexistent file
        def nonexistentResult = InputValidator.validateInputFile("/nonexistent/file.fastq", "fastq_1", 1)
        assert !nonexistentResult.isValid() : "Nonexistent file should fail"
        assert nonexistentResult.errors.any { it.contains("does not exist") } : "Should indicate file not found"
        
        // Test empty file path
        def emptyResult = InputValidator.validateInputFile("", "fastq_1", 1)
        assert !emptyResult.isValid() : "Empty file path should fail"
        assert emptyResult.errors.any { it.contains("cannot be empty") } : "Should indicate empty path"
        
        // Test null file path
        def nullResult = InputValidator.validateInputFile(null, "fastq_1", 1)
        assert !nullResult.isValid() : "Null file path should fail"
        
        // Cleanup
        testDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testDatabaseValidation() {
    def testName = "Database Validation"
    
    try {
        // Create test database directories
        def testDir = new File("test_databases")
        testDir.mkdirs()
        
        def kraken2Dir = new File(testDir, "kraken2")
        kraken2Dir.mkdirs()
        
        def checkvDir = new File(testDir, "checkv")
        checkvDir.mkdirs()
        
        // Test valid database configuration
        def validParams = [
            kraken2_db: kraken2Dir.absolutePath,
            checkv_db: checkvDir.absolutePath,
            blast_options: ['viruses'],
            blastdb_viruses: "/nonexistent/blast"
        ]
        
        def validResult = InputValidator.validateDatabases(validParams)
        assert validResult.errors.isEmpty() : "Valid required databases should have no errors"
        assert validResult.warnings.any { it.contains("Optional database") } : "Should warn about missing optional databases"
        
        // Test missing required databases
        def missingParams = [
            kraken2_db: null,
            checkv_db: "/nonexistent/checkv"
        ]
        
        def missingResult = InputValidator.validateDatabases(missingParams)
        assert !missingResult.isValid() : "Missing required databases should fail"
        assert missingResult.errors.any { it.contains("path is required") } : "Should indicate required database missing"
        assert missingResult.errors.any { it.contains("does not exist") } : "Should indicate nonexistent database"
        
        // Test DIAMOND database configuration
        def diamondParams = [
            kraken2_db: kraken2Dir.absolutePath,
            checkv_db: checkvDir.absolutePath,
            blastx_tool: 'diamond',
            diamonddb: "/nonexistent/diamond.dmnd"
        ]
        
        def diamondResult = InputValidator.validateDatabases(diamondParams)
        assert diamondResult.warnings.any { it.contains("Optional database") } : "Should warn about missing DIAMOND database"
        
        // Cleanup
        testDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testAdapterFileValidation() {
    def testName = "Adapter File Validation"
    
    try {
        // Create test files
        def testDir = new File("test_adapters")
        testDir.mkdirs()
        
        def validAdapter = new File(testDir, "adapters.fa")
        validAdapter.text = ">adapter1\nACGT\n"
        
        def invalidExtension = new File(testDir, "adapters.txt")
        invalidExtension.text = ">adapter1\nACGT\n"
        
        // Test valid adapter file
        def validResult = InputValidator.validateAdapterFile(validAdapter.absolutePath)
        assert validResult.isValid() : "Valid adapter file should pass"
        assert validResult.info.any { it.contains("Adapter file validation passed") } : "Should indicate success"
        
        // Test file with invalid extension
        def invalidExtResult = InputValidator.validateAdapterFile(invalidExtension.absolutePath)
        assert invalidExtResult.isValid() : "File with invalid extension should still pass"
        assert invalidExtResult.warnings.any { it.contains("does not have a standard FASTA extension") } : "Should warn about extension"
        
        // Test nonexistent file
        def nonexistentResult = InputValidator.validateAdapterFile("/nonexistent/adapters.fa")
        assert !nonexistentResult.isValid() : "Nonexistent file should fail"
        assert nonexistentResult.errors.any { it.contains("does not exist") } : "Should indicate file not found"
        
        // Test null adapter (should be valid - adapters are optional)
        def nullResult = InputValidator.validateAdapterFile(null)
        assert nullResult.isValid() : "Null adapter should be valid (optional)"
        
        // Cleanup
        testDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testValidationResultClass() {
    def testName = "ValidationResult Class"
    
    try {
        // Test basic functionality
        def result = new ValidationResult()
        assert !result.isValid() : "New result should be invalid by default"
        assert result.errors.isEmpty() : "Should start with no errors"
        assert result.warnings.isEmpty() : "Should start with no warnings"
        
        // Test adding errors and warnings
        result.addError("Test error")
        result.addWarning("Test warning")
        result.addInfo("Test info")
        result.addSuggestion("Test suggestion")
        
        assert !result.isValid() : "Should be invalid with errors"
        assert result.errors.size() == 1 : "Should have one error"
        assert result.warnings.size() == 1 : "Should have one warning"
        assert result.info.size() == 1 : "Should have one info"
        assert result.suggestions.size() == 1 : "Should have one suggestion"
        
        // Test setting valid
        result.setValid(true)
        assert !result.isValid() : "Should still be invalid due to errors"
        
        // Test merging results
        def otherResult = new ValidationResult()
        otherResult.addError("Other error")
        otherResult.addWarning("Other warning")
        otherResult.setValid(true)
        
        result.merge(otherResult)
        assert result.errors.size() == 2 : "Should have merged errors"
        assert result.warnings.size() == 2 : "Should have merged warnings"
        
        // Test toString
        def resultString = result.toString()
        assert resultString.contains("FAILED") : "Should show failed status"
        assert resultString.contains("Test error") : "Should contain error message"
        assert resultString.contains("Test warning") : "Should contain warning message"
        
        // Test error report generation
        def errorReport = result.generateErrorReport()
        assert errorReport.containsKey('valid') : "Should include validity status"
        assert errorReport.containsKey('summary') : "Should include summary"
        assert errorReport.containsKey('errors') : "Should include errors"
        assert !errorReport.valid : "Should indicate invalid"
        assert errorReport.summary.totalErrors == 2 : "Should count errors correctly"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}

def testCsvParsing() {
    def testName = "CSV Parsing"
    
    try {
        // Create test CSV file
        def testDir = new File("test_csv_parsing")
        testDir.mkdirs()
        
        def csvFile = new File(testDir, "test.csv")
        csvFile.text = '''sample,fastq_1,fastq_2
sample1,"/path/to/file1_R1.fastq.gz","/path/to/file1_R2.fastq.gz"
sample2,/path/to/file2_R1.fastq.gz,/path/to/file2_R2.fastq.gz
"sample,3",/path/to/file3_R1.fastq.gz,/path/to/file3_R2.fastq.gz
'''
        
        // Test CSV parsing through samplesheet validation
        def result = InputValidator.validateSamplesheet(csvFile.absolutePath)
        
        // Should fail due to missing files, but parsing should work
        assert result.errors.any { it.contains("does not exist") } : "Should detect missing files"
        
        // The parsing itself should handle quoted values correctly
        // This is tested indirectly through the validation process
        
        // Test malformed CSV
        def malformedCsv = new File(testDir, "malformed.csv")
        malformedCsv.text = '''sample,fastq_1,fastq_2
sample1,file1.fastq
sample2,file2.fastq,file2_R2.fastq,extra_column
'''
        
        def malformedResult = InputValidator.validateSamplesheet(malformedCsv.absolutePath)
        assert !malformedResult.isValid() : "Malformed CSV should fail validation"
        
        // Cleanup
        testDir.deleteDir()
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}