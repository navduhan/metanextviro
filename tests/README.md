# MetaNextViro Pipeline Testing Framework

This directory contains a comprehensive testing framework for the MetaNextViro pipeline improvements, covering configuration validation, partition selection, resource allocation, and performance optimization.

## Overview

The testing framework is designed to validate all aspects of the pipeline improvements according to requirements 1.1, 1.2, 1.3, 6.1, 6.2, 6.3, and 6.4. It includes:

- **Unit Tests**: Test individual components and functions
- **Integration Tests**: Test component interactions and end-to-end workflows  
- **Performance Tests**: Test resource utilization, scalability, and optimization

## Test Structure

```
tests/
├── comprehensive_test_suite.nf     # Main test orchestrator
├── run_tests.nf                    # Test runner script
├── test_config.yml                 # Test configuration
├── README.md                       # This documentation
├── unit/                          # Unit tests
│   ├── config_validation_tests.nf
│   ├── partition_selection_tests.nf
│   ├── input_validation_tests.nf
│   └── resource_allocation_tests.nf
├── integration/                   # Integration tests
│   ├── profile_integration_tests.nf
│   ├── environment_integration_tests.nf
│   └── end_to_end_tests.nf
└── performance/                   # Performance tests
    └── performance_tests.nf
```

## Running Tests

### Quick Start

Run all tests with default configuration:

```bash
nextflow run tests/run_tests.nf
```



### Running Specific Test Categories

Run only unit tests:
```bash
nextflow run tests/unit/config_validation_tests.nf
nextflow run tests/unit/partition_selection_tests.nf
nextflow run tests/unit/input_validation_tests.nf
nextflow run tests/unit/resource_allocation_tests.nf
```

Run only integration tests:
```bash
nextflow run tests/integration/profile_integration_tests.nf
nextflow run tests/integration/environment_integration_tests.nf
nextflow run tests/integration/end_to_end_tests.nf
```

Run only performance tests:
```bash
nextflow run tests/performance/performance_tests.nf
```

### Running Individual Test Workflows

Each test file can be run independently:

```bash
# Test configuration validation
nextflow run tests/unit/config_validation_tests.nf

# Test partition selection logic
nextflow run tests/unit/partition_selection_tests.nf

# Test input validation
nextflow run tests/unit/input_validation_tests.nf

# Test resource allocation
nextflow run tests/unit/resource_allocation_tests.nf

# Test profile integration
nextflow run tests/integration/profile_integration_tests.nf

# Test environment integration
nextflow run tests/integration/environment_integration_tests.nf

# Test end-to-end workflows
nextflow run tests/integration/end_to_end_tests.nf

# Test performance characteristics
nextflow run tests/performance/performance_tests.nf
```

## Enhanced Test Categories

### Unit Tests

#### Configuration Validation Tests (`unit/config_validation_tests.nf`)
- Tests the `ConfigValidator` class and related validation functions
- Validates resource configuration parameters
- Tests profile consistency validation
- Tests executor-specific configuration validation
- Tests database path validation
- Tests partition configuration validation
- Tests standardized process label validation
- Tests cross-profile compatibility

#### Partition Selection Tests (`unit/partition_selection_tests.nf`)
- Tests the `PartitionManager` class and intelligent partition selection
- Tests different partition selection strategies (intelligent, static, user-defined)
- Tests fallback logic when partitions are unavailable
- Tests cluster options generation for SLURM
- Tests resource threshold logic
- Tests GPU and memory-intensive process detection

#### Input Validation Tests (`unit/input_validation_tests.nf`)
- Tests the `InputValidator` class and validation workflows
- Tests file format validation (CSV, TSV, Excel)
- Tests samplesheet column and content validation
- Tests input file accessibility validation
- Tests database validation
- Tests adapter file validation

#### Resource Allocation Tests (`unit/resource_allocation_tests.nf`)
- Tests resource allocation logic and scaling
- Tests resource limit validation and enforcement
- Tests memory and time unit conversion
- Tests CPU allocation for different process types
- Tests retry scaling behavior
- Tests profile-specific resource allocation

### Integration Tests

#### Profile Integration Tests (`integration/profile_integration_tests.nf`)
- Tests integration between different execution profiles (local, SLURM)
- Tests profile switching and configuration inheritance
- Tests resource profile validation
- Tests cross-profile compatibility

#### Environment Integration Tests (`integration/environment_integration_tests.nf`)
- Tests unified vs per-process environment management
- Tests environment mode switching
- Tests dependency conflict resolution
- Tests container integration (Docker, Singularity)
- Tests environment validation and setup

#### End-to-End Tests (`integration/end_to_end_tests.nf`)
- Tests complete pipeline execution with different configurations
- Tests error handling and recovery mechanisms
- Tests resource scaling under different conditions
- Tests configuration validation in real execution scenarios

### Performance Tests

#### Performance Tests (`performance/performance_tests.nf`)
- Tests resource utilization efficiency (CPU, memory, I/O)
- Tests scalability with different input sizes
- Tests parallel processing performance
- Tests memory usage optimization
- Tests partition selection performance
- Tests configuration validation performance
- Tests environment setup performance
- Tests resource scaling performance

## Test Configuration

The test suite uses `test_config.yml` for configuration. Key settings include:

- **Test Execution**: Enable/disable test categories, timeouts, parallelism
- **Resource Limits**: Maximum resources to use during testing
- **Validation Thresholds**: Performance and accuracy requirements
- **Environment Settings**: Local, SLURM, and container configurations
- **Reporting**: Output formats and detail levels

## Test Data

Tests use mock data and temporary files to avoid dependencies on external resources:

- Mock samplesheets with various formats and error conditions
- Temporary database directories for validation testing
- Simulated input files of different sizes for performance testing
- Mock SLURM environments for partition selection testing

## Expected Outcomes

### Unit Tests
- All configuration validation functions should correctly identify valid and invalid configurations
- Partition selection should choose appropriate partitions based on resource requirements
- Input validation should catch common errors and provide helpful messages
- Resource allocation should scale appropriately and respect limits

### Integration Tests
- Different profiles should work correctly and be compatible
- Environment management should handle both unified and per-process modes
- End-to-end workflows should complete successfully with proper error handling

### Performance Tests
- Resource utilization should be efficient (>70% CPU, >60% memory)
- Scalability should be sub-linear with input size due to parallelization
- Memory usage should be optimized with minimal leaks and fragmentation
- Configuration and environment operations should be fast (<1-5 seconds)

## Troubleshooting

### Common Issues

1. **Missing Dependencies**: Ensure all required Groovy classes are available
2. **Resource Constraints**: Adjust test configuration for your system's resources
3. **Permission Issues**: Ensure write access to temporary directories
4. **SLURM Unavailable**: Set `mock_slurm_commands: true` in test configuration

### Test Failures

If tests fail:

1. Check the generated test reports for detailed error information
2. Review the test configuration to ensure appropriate thresholds
3. Verify that your system meets the minimum requirements
4. Check for any missing or corrupted test data files

### Performance Issues

If performance tests fail:

1. Adjust performance thresholds in `test_config.yml`
2. Ensure sufficient system resources are available
3. Check for background processes that might affect performance
4. Consider running tests on a dedicated system

## Extending the Test Suite

### Adding New Tests

1. Create new test functions following the existing patterns
2. Add appropriate assertions and error handling
3. Include performance metrics where relevant
4. Update test configuration if needed

### Test Function Structure

```groovy
def testNewFeature() {
    def testName = "New Feature Test"
    
    try {
        // Test setup
        def testData = createTestData()
        
        // Execute test
        def result = executeFeature(testData)
        
        // Validate results
        assert result.success : "Feature should succeed"
        assert result.metric >= threshold : "Metric should meet threshold"
        
        return [name: testName, passed: true, error: null]
        
    } catch (Exception e) {
        return [name: testName, passed: false, error: e.message]
    }
}
```

### Performance Test Guidelines

- Measure relevant metrics (time, memory, CPU usage)
- Use realistic test data sizes
- Include baseline comparisons where appropriate
- Set reasonable performance thresholds
- Account for system variability in assertions

## Continuous Integration

The test suite is designed to be integrated into CI/CD pipelines:

- Tests can run in parallel for faster execution
- Results are generated in multiple formats (HTML, JSON, CSV)
- Exit codes indicate overall test success/failure
- Resource usage is monitored and reported

## Reporting

Test results are automatically generated in multiple formats:

- **HTML Report**: Human-readable test results with metrics and charts
- **JSON Report**: Machine-readable results for integration with other tools
- **CSV Metrics**: Performance metrics for trend analysis
- **Console Output**: Real-time test progress and summary

Reports include:
- Test execution summary (passed/failed counts)
- Performance metrics and trends
- Error details and stack traces
- Resource utilization statistics
- Recommendations for optimization

## Requirements Coverage

This testing framework addresses the following requirements:

- **1.1, 1.2, 1.3**: Configuration and resource management validation
- **6.1, 6.2**: Performance and scalability testing
- **6.3, 6.4**: Resource optimization and utilization testing

Each test is mapped to specific requirements to ensure comprehensive coverage of all pipeline improvements.
##
# Validation Tests (`validation_tests.nf`)

Comprehensive validation of all pipeline improvements:

- **Configuration Validation**: Standardized process labels, resource profiles, cross-profile compatibility
- **Resource Management**: Resource allocation logic, memory scaling, CPU allocation, retry scaling
- **Partition Selection**: Intelligent selection, memory-based selection, GPU detection, fallback logic
- **Input Validation**: Samplesheet formats, file accessibility, database validation, error messages
- **Environment Management**: Unified vs per-process environments, switching, dependency resolution
- **Performance Optimization**: Resource utilization, parallel processing, memory optimization
- **Regression Testing**: Functionality preservation, backward compatibility, output consistency
- **Integration Validation**: End-to-end workflows, multi-profile integration, error recovery

### Continuous Integration Tests (`ci_tests.nf`)

Multi-environment testing and compatibility validation:

- **Local Environment Testing**: Configuration validation, resource allocation, process execution
- **SLURM Environment Testing**: Partition selection, cluster options, job handling, performance optimization
- **Container Environment Testing**: Docker/Singularity compatibility, environment management
- **Performance Benchmarking**: Resource utilization, scalability, throughput, memory efficiency
- **Regression Testing**: Functionality preservation, performance regression detection
- **Compatibility Testing**: Cross-platform, version compatibility, dependency compatibility

### Performance Benchmarking Suite (`performance_benchmarks.nf`)

Detailed performance analysis and optimization validation:

- **Resource Utilization Benchmarks**: CPU efficiency, memory efficiency, I/O throughput, allocation speed
- **Scalability Benchmarks**: Parallel processing, input size scaling, multi-sample processing, load balancing
- **Memory Optimization Benchmarks**: Usage efficiency, leak detection, garbage collection, fragmentation
- **Configuration Performance Benchmarks**: Validation speed, parsing performance, caching performance
- **Partition Selection Benchmarks**: Selection speed, accuracy, fallback performance, availability checking
- **Environment Management Benchmarks**: Setup performance, switching performance, dependency resolution

## New Testing Features

### Enhanced Test Runner

The enhanced test runner (`run_tests.nf`) provides:

- **Multiple Test Modes**: Run specific test categories or comprehensive testing
- **Parallel Execution**: Configurable parallel test execution for faster results
- **Advanced Configuration**: Flexible test configuration with YAML support
- **Comprehensive Reporting**: Detailed reports in multiple formats (text, JSON)
- **Test Data Management**: Automatic cleanup and preservation options
- **Timeout Management**: Configurable timeouts for different test categories

### Advanced Test Configuration

The enhanced test configuration (`test_config.yml`) includes:

- **Validation Thresholds**: Performance, accuracy, and efficiency thresholds
- **CI Settings**: Multi-environment testing, regression testing, compatibility testing
- **Benchmark Settings**: Resource benchmarks, scalability benchmarks, performance comparison
- **Advanced Features**: Stress testing, load testing, chaos testing, security testing

### Test Reporting

Enhanced reporting capabilities:

- **Comprehensive Reports**: Detailed test results with recommendations
- **Performance Metrics**: Resource utilization, scalability, and efficiency metrics
- **Regression Analysis**: Performance regression detection and analysis
- **Deployment Readiness**: Assessment of deployment readiness based on test results
- **Multiple Formats**: Text reports for humans, JSON reports for automation

## Requirements Coverage

This enhanced testing framework addresses all requirements for task 13:

### Create comprehensive test suite covering all new features ✅

- **Configuration Management**: Standardized labels, resource profiles, validation
- **Partition Selection**: Intelligent selection, fallback logic, cluster options
- **Input Validation**: File formats, accessibility, databases, error handling
- **Environment Management**: Unified vs per-process, switching, dependency resolution
- **Performance Optimization**: Resource utilization, scalability, memory optimization
- **Error Handling**: Recovery mechanisms, graceful degradation, reporting

### Implement continuous integration testing for multiple environments ✅

- **Local Environment**: Full testing on local systems
- **SLURM Environment**: Partition selection, job submission, resource scaling
- **Container Environment**: Docker/Singularity compatibility testing
- **Cross-Platform**: Compatibility across different systems and configurations

### Add regression testing to ensure existing functionality is preserved ✅

- **Functionality Preservation**: Core pipeline processes maintain functionality
- **Backward Compatibility**: Old configurations and parameters still work
- **Output Consistency**: Results remain consistent across versions
- **Performance Regression**: Detection of performance degradation

### Create performance benchmarking suite for optimization validation ✅

- **Resource Benchmarks**: CPU, memory, and I/O utilization efficiency
- **Scalability Benchmarks**: Parallel processing and input size scaling
- **Performance Comparison**: Baseline comparison and regression detection
- **Optimization Validation**: Verification of performance improvements

## Test Execution Workflow

1. **Test Planning**: Configure test execution based on requirements
2. **Environment Setup**: Prepare test environments and data
3. **Test Execution**: Run tests according to selected mode and configuration
4. **Result Collection**: Gather test results and performance metrics
5. **Analysis**: Analyze results against thresholds and requirements
6. **Reporting**: Generate comprehensive reports with recommendations
7. **Cleanup**: Clean up test data and temporary files

## Continuous Integration Integration

The testing framework is designed for CI/CD integration:

- **Automated Execution**: Can be triggered automatically in CI pipelines
- **Exit Codes**: Proper exit codes for CI system integration
- **Report Generation**: Machine-readable reports for automated processing
- **Threshold Validation**: Configurable pass/fail criteria
- **Performance Tracking**: Historical performance tracking and trend analysis

## Best Practices

### Running Tests

1. **Start with Unit Tests**: Run unit tests first to catch basic issues
2. **Use Appropriate Timeouts**: Set realistic timeouts for your environment
3. **Monitor Resources**: Ensure sufficient resources for performance tests
4. **Review Configuration**: Customize test configuration for your environment
5. **Check Reports**: Always review detailed reports for insights

### Test Development

1. **Follow Patterns**: Use existing test patterns for consistency
2. **Add Assertions**: Include meaningful assertions with clear error messages
3. **Handle Errors**: Implement proper error handling and cleanup
4. **Document Tests**: Add clear documentation for test purpose and expectations
5. **Update Configuration**: Update test configuration when adding new tests

### Performance Testing

1. **Baseline Establishment**: Establish performance baselines for comparison
2. **Consistent Environment**: Use consistent environments for reliable results
3. **Multiple Runs**: Run performance tests multiple times for accuracy
4. **Resource Monitoring**: Monitor system resources during performance tests
5. **Trend Analysis**: Track performance trends over time

## Troubleshooting

### Common Issues

1. **Test Timeouts**: Increase timeout values in test configuration
2. **Resource Constraints**: Ensure sufficient CPU and memory for tests
3. **Permission Issues**: Check file and directory permissions
4. **Missing Dependencies**: Verify all required tools and libraries are available
5. **Configuration Errors**: Validate test configuration syntax and values

### Performance Issues

1. **Slow Tests**: Check system resources and reduce parallel execution
2. **Memory Issues**: Increase available memory or reduce test data size
3. **I/O Bottlenecks**: Use faster storage or reduce I/O intensive operations
4. **Network Issues**: Check network connectivity for remote resources

### Debugging

1. **Verbose Logging**: Enable verbose logging for detailed information
2. **Individual Tests**: Run individual tests to isolate issues
3. **Test Data**: Verify test data integrity and accessibility
4. **Environment**: Check environment setup and configuration
5. **Dependencies**: Verify all dependencies are properly installed

## Future Enhancements

Potential future enhancements to the testing framework:

- **Machine Learning**: ML-based performance prediction and optimization
- **Cloud Testing**: Support for cloud-based testing environments
- **Visual Reports**: Web-based interactive test reports
- **Test Automation**: Automated test generation based on code changes
- **Integration Testing**: Enhanced integration with external systems