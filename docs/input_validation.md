# Input Validation Module

The MetaNextViro pipeline includes a comprehensive input validation module that ensures data integrity and provides clear error messages to help users quickly identify and fix input-related issues.

## Features

### 1. File Format Validation
- **Supported Formats**: CSV, TSV, XLS, XLSX
- **Format Detection**: Automatic detection based on file extension
- **Accessibility Checks**: Verifies file existence and readability
- **Size Validation**: Ensures files are not empty

### 2. Samplesheet Structure Validation
- **Required Columns**: `sample`, `fastq_1`, `fastq_2`
- **Optional Columns**: `single_end`, `strandedness`
- **Duplicate Detection**: Identifies duplicate sample names
- **Content Validation**: Ensures all required fields are populated

### 3. Input File Accessibility
- **File Existence**: Verifies all input FASTQ files exist
- **Permission Checks**: Ensures files are readable
- **Extension Validation**: Warns about non-standard FASTQ extensions
- **Size Validation**: Checks for empty files

### 4. Database Validation
- **Required Databases**: Kraken2, CheckV
- **Optional Databases**: BLAST databases, DIAMOND database
- **Format Verification**: Checks database file structure
- **Conditional Validation**: Only validates databases that are configured for use

## Usage

### Basic Validation
The validation module is automatically integrated into the pipeline workflow:

```bash
nextflow run main.nf --input samplesheet.csv --outdir results
```

### Validation Configuration
You can customize validation behavior through parameters:

```bash
nextflow run main.nf \
    --input samplesheet.csv \
    --outdir results \
    --validation.strict_mode true \
    --validation.check_file_extensions true
```

### Validation Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `validation.enable_input_validation` | `true` | Enable/disable input validation |
| `validation.enable_database_validation` | `true` | Enable/disable database validation |
| `validation.strict_mode` | `false` | Treat warnings as errors |
| `validation.check_file_extensions` | `true` | Validate FASTQ file extensions |
| `validation.min_file_size_bytes` | `1000` | Minimum file size threshold |

## Samplesheet Format

### CSV Format (Recommended)
```csv
sample,fastq_1,fastq_2
sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
```

### TSV Format
```tsv
sample	fastq_1	fastq_2
sample1	/path/to/sample1_R1.fastq.gz	/path/to/sample1_R2.fastq.gz
sample2	/path/to/sample2_R1.fastq.gz	/path/to/sample2_R2.fastq.gz
```

### Required Columns
- **sample**: Unique identifier for each sample
- **fastq_1**: Path to forward reads (R1) FASTQ file
- **fastq_2**: Path to reverse reads (R2) FASTQ file

### Optional Columns
- **single_end**: Set to `true` for single-end sequencing data
- **strandedness**: Specify library strandedness (forward, reverse, unstranded)

## Database Requirements

### Required Databases
1. **Kraken2 Database**
   - Parameter: `--kraken2_db`
   - Type: Directory
   - Required files: `hash.k2d`, `opts.k2d`, `taxo.k2d`
   - Download: https://benlangmead.github.io/aws-indexes/k2

2. **CheckV Database**
   - Parameter: `--checkv_db`
   - Type: Directory
   - Required files: `genome_db`, `hmm_db`
   - Download: https://portal.nersc.gov/CheckV/

### Optional Databases
1. **BLAST Viruses Database**
   - Parameter: `--blastdb_viruses`
   - Condition: When `--blast_options` includes 'viruses' or 'all'
   - Required extensions: `.nal`, `.nhr`, `.nin`, `.nsq`

2. **BLAST NT Database**
   - Parameter: `--blastdb_nt`
   - Condition: When `--blast_options` includes 'nt' or 'all'
   - Required extensions: `.nal`, `.nhr`, `.nin`, `.nsq`

3. **DIAMOND Database**
   - Parameter: `--diamonddb`
   - Condition: When `--blastx_tool` is 'diamond'
   - Required extension: `.dmnd`

## Error Messages and Solutions

### Common Errors

#### 1. Missing Required Columns
```
Error: Missing required columns: fastq_2. Required columns: sample, fastq_1, fastq_2
```
**Solution**: Add the missing column to your samplesheet header.

#### 2. File Not Found
```
Error: Row 2: fastq_1 file does not exist: /path/to/missing_file.fastq.gz
```
**Solution**: Check the file path and ensure the file exists and is accessible.

#### 3. Duplicate Sample Names
```
Error: Row 3: Duplicate sample name 'sample1'
```
**Solution**: Ensure all sample names in the samplesheet are unique.

#### 4. Database Not Found
```
Error: Required database not found: Kraken2 database at /path/to/kraken2_db
```
**Solution**: Download and install the required database, or update the path parameter.

### Warnings

#### 1. Non-standard File Extensions
```
Warning: Row 2: fastq_1 does not have standard FASTQ extension: /path/to/file.txt
```
**Solution**: Rename files to use standard FASTQ extensions (`.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`).

#### 2. Excel Format Detected
```
Warning: Excel format detected. Consider converting to CSV for better compatibility.
```
**Solution**: Save your Excel file as CSV format for better performance and compatibility.

## Validation Reports

The validation module generates detailed reports saved to the output directory:

- `validation/validation_summary.txt`: Overall validation status and summary
- `validation/validation_summary.json`: Machine-readable validation results
- `validation/database_validation.txt`: Database validation details
- `validation/{sample}_validation.txt`: Per-sample validation results

### Example Validation Summary
```
MetaNextViro Pipeline - Validation Summary
=========================================
Generated: 2024-01-15 10:30:00

VALIDATION STATUS: PASSED

Total validation reports: 5
All validations completed successfully!

DETAILED REPORTS:
  - database_validation.txt
  - sample1_validation.txt
  - sample2_validation.txt
  - sample3_validation.txt
```

## Troubleshooting

### Performance Issues
- Large samplesheets (>1000 samples) may take longer to validate
- Consider splitting very large samplesheets into smaller batches
- Use `--validation.enable_file_accessibility_checks false` to skip file checks if needed

### File Permission Issues
```bash
# Fix file permissions
chmod 644 /path/to/samplesheet.csv
chmod 644 /path/to/fastq/files/*.fastq.gz

# Fix directory permissions
chmod 755 /path/to/database/directory
```

### Network File Systems
- Validation may be slower on network-mounted filesystems
- Consider copying files locally for better performance
- Ensure network connectivity is stable during validation

## Advanced Configuration

### Custom Validation Rules
You can extend the validation module by modifying the validation configuration:

```groovy
// nextflow/configs/validation.config
params {
    validation {
        // Add custom file extensions
        allowed_fastq_extensions = ['.fastq', '.fq', '.fastq.gz', '.fq.gz', '.fastq.bz2']
        
        // Custom minimum file size (in bytes)
        min_file_size_bytes = 5000
        
        // Additional required columns
        required_columns = ['sample', 'fastq_1', 'fastq_2', 'condition']
    }
}
```

### Integration with Other Workflows
The validation module can be used independently in other Nextflow workflows:

```groovy
include { INPUT_VALIDATION } from './nextflow/subworkflow/input_validation.nf'

workflow MY_WORKFLOW {
    INPUT_VALIDATION(params.input)
    
    // Use validated samples
    validated_samples = INPUT_VALIDATION.out.validated_samples
    // ... rest of workflow
}
```

## Best Practices

1. **Use CSV Format**: CSV is the most reliable and fastest format for samplesheets
2. **Absolute Paths**: Use absolute file paths to avoid path resolution issues
3. **Consistent Naming**: Use consistent and descriptive sample names
4. **Test Small**: Test with a small samplesheet first before running large datasets
5. **Check Logs**: Always review validation logs before proceeding with analysis
6. **Backup Data**: Ensure input files are backed up before processing

## API Reference

### InputValidator Class

#### Methods

##### `validateFileFormat(String filePath)`
Validates the format of an input file.
- **Parameters**: `filePath` - Path to the file to validate
- **Returns**: `ValidationResult` object
- **Throws**: None (errors captured in result)

##### `validateSamplesheet(String filePath)`
Validates samplesheet structure and content.
- **Parameters**: `filePath` - Path to the samplesheet file
- **Returns**: `ValidationResult` object
- **Throws**: None (errors captured in result)

##### `validateDatabases(Map params)`
Validates database configurations and accessibility.
- **Parameters**: `params` - Pipeline parameters map
- **Returns**: `ValidationResult` object
- **Throws**: None (errors captured in result)

### ValidationResult Class

#### Properties
- `valid`: Boolean indicating if validation passed
- `errors`: List of error messages
- `warnings`: List of warning messages
- `info`: List of informational messages
- `suggestions`: List of suggested solutions

#### Methods
- `isValid()`: Returns true if validation passed and no errors exist
- `addError(String message)`: Add an error message
- `addWarning(String message)`: Add a warning message
- `merge(ValidationResult other)`: Merge another validation result
- `toString()`: Generate formatted validation report