#!/bin/bash

# MetaNextViro Container Testing Script
# Comprehensive testing procedures for container validation

set -euo pipefail

# Configuration
CONTAINER_NAME="metanextviro"
CONTAINER_TAG=${1:-"latest"}
TEST_DATA_DIR="tests/data"
TEST_OUTPUT_DIR="tests/container_output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function to run a test
run_test() {
    local test_name=$1
    local test_command=$2
    local expected_exit_code=${3:-0}
    
    ((TESTS_TOTAL++))
    print_message "$BLUE" "Running test: $test_name"
    
    if eval "$test_command"; then
        local exit_code=$?
        if [ $exit_code -eq $expected_exit_code ]; then
            print_message "$GREEN" "✓ PASS: $test_name"
            ((TESTS_PASSED++))
            return 0
        else
            print_message "$RED" "✗ FAIL: $test_name (exit code: $exit_code, expected: $expected_exit_code)"
            ((TESTS_FAILED++))
            return 1
        fi
    else
        print_message "$RED" "✗ FAIL: $test_name (command execution failed)"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to test container startup
test_container_startup() {
    print_message "$YELLOW" "Testing container startup and basic functionality..."
    
    run_test "Container startup" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} echo 'Hello from MetaNextViro container'"
    
    run_test "Container shell access" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'echo \$SHELL'"
    
    run_test "Working directory" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} pwd | grep -q '/workspace'"
}

# Function to test environment management
test_environment_management() {
    print_message "$YELLOW" "Testing environment management..."
    
    run_test "Conda installation" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} conda --version"
    
    run_test "Unified environment exists" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} conda env list | grep -q 'metanextviro-unified'"
    
    run_test "Environment activation script" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} /usr/local/bin/activate_env.sh"
    
    run_test "Unified environment mode" \
        "docker run --rm -e METANEXTVIRO_ENV_MODE=unified ${CONTAINER_NAME}:${CONTAINER_TAG} /usr/local/bin/activate_env.sh"
    
    run_test "Per-process environment mode" \
        "docker run --rm -e METANEXTVIRO_ENV_MODE=per_process ${CONTAINER_NAME}:${CONTAINER_TAG} /usr/local/bin/activate_env.sh"
}

# Function to test tool availability
test_tool_availability() {
    print_message "$YELLOW" "Testing tool availability in unified environment..."
    
    local tools=(
        "python --version"
        "fastqc --help"
        "multiqc --help"
        "fastp --help"
        "megahit --help"
        "blastn -help"
        "diamond help"
        "kraken2 --help"
        "samtools --help"
        "bowtie2 --help"
    )
    
    for tool_cmd in "${tools[@]}"; do
        local tool_name=$(echo "$tool_cmd" | cut -d' ' -f1)
        run_test "Tool availability: $tool_name" \
            "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && $tool_cmd' >/dev/null 2>&1"
    done
}

# Function to test Python packages
test_python_packages() {
    print_message "$YELLOW" "Testing Python package imports..."
    
    local packages=(
        "pandas"
        "matplotlib"
        "seaborn"
        "numpy"
        "scipy"
        "Bio"
        "ete3"
    )
    
    for package in "${packages[@]}"; do
        run_test "Python package: $package" \
            "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && python -c \"import $package\"'"
    done
}

# Function to test R packages
test_r_packages() {
    print_message "$YELLOW" "Testing R package availability..."
    
    run_test "R installation" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && R --version' >/dev/null 2>&1"
    
    run_test "VirFinder package" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && Rscript -e \"library(VirFinder)\"' >/dev/null 2>&1"
}

# Function to test container validation
test_container_validation() {
    print_message "$YELLOW" "Testing container validation system..."
    
    run_test "Container validation script" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} /usr/local/bin/validate_container.sh"
    
    run_test "Health check" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} /usr/local/bin/validate_container.sh --health-check"
}

# Function to test per-process environments
test_per_process_environments() {
    print_message "$YELLOW" "Testing per-process environments..."
    
    local environments=(
        "metanextviro-qc"
        "metanextviro-trimming"
        "metanextviro-assembly"
        "metanextviro-annotation"
        "metanextviro-taxonomy"
        "metanextviro-alignment"
        "metanextviro-viral"
    )
    
    for env in "${environments[@]}"; do
        run_test "Environment exists: $env" \
            "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} conda env list | grep -q '$env'"
    done
}

# Function to test resource usage
test_resource_usage() {
    print_message "$YELLOW" "Testing resource usage and limits..."
    
    run_test "Memory usage test" \
        "docker run --rm --memory=1g ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && python -c \"import numpy; a = numpy.zeros((1000, 1000))\"'"
    
    run_test "CPU usage test" \
        "docker run --rm --cpus=1 ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && python -c \"import time; time.sleep(1)\"'"
}

# Function to test file system and permissions
test_filesystem_permissions() {
    print_message "$YELLOW" "Testing file system and permissions..."
    
    run_test "Write permissions in workspace" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'echo \"test\" > /workspace/test_file && rm /workspace/test_file'"
    
    run_test "Temporary directory access" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'echo \"test\" > /tmp/test_file && rm /tmp/test_file'"
    
    run_test "Script execution permissions" \
        "docker run --rm ${CONTAINER_NAME}:${CONTAINER_TAG} ls -la /usr/local/bin/validate_container.sh | grep -q 'rwxr-xr-x'"
}

# Function to test with sample data (if available)
test_with_sample_data() {
    if [ ! -d "$TEST_DATA_DIR" ]; then
        print_message "$YELLOW" "Skipping sample data tests (no test data directory found)"
        return 0
    fi
    
    print_message "$YELLOW" "Testing with sample data..."
    
    # Create test output directory
    mkdir -p "$TEST_OUTPUT_DIR"
    
    run_test "FastQC on sample data" \
        "docker run --rm -v \$(pwd)/$TEST_DATA_DIR:/data -v \$(pwd)/$TEST_OUTPUT_DIR:/output ${CONTAINER_NAME}:${CONTAINER_TAG} bash -c 'source activate metanextviro-unified && fastqc /data/*.fastq* -o /output' >/dev/null 2>&1"
}

# Function to generate test report
generate_test_report() {
    print_message "$BLUE" "Generating test report..."
    
    local report_file="docker/test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "MetaNextViro Container Test Report"
        echo "================================="
        echo "Test Date: $(date)"
        echo "Container: ${CONTAINER_NAME}:${CONTAINER_TAG}"
        echo ""
        echo "Test Summary:"
        echo "  Total Tests: $TESTS_TOTAL"
        echo "  Passed: $TESTS_PASSED"
        echo "  Failed: $TESTS_FAILED"
        echo "  Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
        echo ""
        echo "Container Information:"
        docker inspect "${CONTAINER_NAME}:${CONTAINER_TAG}" --format='Image ID: {{.Id}}'
        docker inspect "${CONTAINER_NAME}:${CONTAINER_TAG}" --format='Created: {{.Created}}'
        docker inspect "${CONTAINER_NAME}:${CONTAINER_TAG}" --format='Size: {{.Size}} bytes'
        echo ""
        echo "Environment List:"
        docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" conda env list
    } > "$report_file"
    
    print_message "$GREEN" "Test report generated: $report_file"
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    print_message "$YELLOW" "Cleaning up test artifacts..."
    
    # Remove test output directory if it exists and is empty
    if [ -d "$TEST_OUTPUT_DIR" ] && [ -z "$(ls -A $TEST_OUTPUT_DIR)" ]; then
        rmdir "$TEST_OUTPUT_DIR"
    fi
}

# Main function
main() {
    print_message "$BLUE" "Starting MetaNextViro container testing..."
    
    # Check if container exists
    if ! docker image inspect "${CONTAINER_NAME}:${CONTAINER_TAG}" >/dev/null 2>&1; then
        print_message "$RED" "Error: Container ${CONTAINER_NAME}:${CONTAINER_TAG} not found"
        print_message "$YELLOW" "Please build the container first using: docker/build.sh"
        exit 1
    fi
    
    # Run test suites
    test_container_startup
    test_environment_management
    test_tool_availability
    test_python_packages
    test_r_packages
    test_container_validation
    test_per_process_environments
    test_resource_usage
    test_filesystem_permissions
    test_with_sample_data
    
    # Generate report and cleanup
    generate_test_report
    cleanup_test_artifacts
    
    # Final results
    echo ""
    print_message "$BLUE" "Testing completed!"
    print_message "$BLUE" "Results: $TESTS_PASSED/$TESTS_TOTAL tests passed"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_message "$GREEN" "All tests passed! Container is ready for use."
        exit 0
    else
        print_message "$RED" "$TESTS_FAILED tests failed. Please review the issues."
        exit 1
    fi
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [TAG]"
        echo "Test MetaNextViro container functionality"
        echo ""
        echo "Arguments:"
        echo "  TAG    Container tag to test (default: latest)"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        exit 0
        ;;
    *)
        main
        ;;
esac