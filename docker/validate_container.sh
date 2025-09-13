#!/bin/bash

# MetaNextViro Container Validation Script
# This script validates that all required tools and environments are properly installed

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation results
VALIDATION_PASSED=true
HEALTH_CHECK_MODE=false

# Parse arguments
if [ $# -gt 0 ] && [ "$1" = "--health-check" ]; then
    HEALTH_CHECK_MODE=true
fi

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}[PASS]${NC} $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}[FAIL]${NC} $message"
        VALIDATION_PASSED=false
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}[WARN]${NC} $message"
    else
        echo -e "[INFO] $message"
    fi
}

# Function to check if command exists
check_command() {
    local cmd=$1
    local env_name=${2:-""}
    
    if [ -n "$env_name" ]; then
        # Check in specific environment
        if conda run -n "$env_name" which "$cmd" >/dev/null 2>&1; then
            print_status "PASS" "$cmd found in environment $env_name"
            return 0
        else
            print_status "FAIL" "$cmd not found in environment $env_name"
            return 1
        fi
    else
        # Check in current environment
        if command -v "$cmd" >/dev/null 2>&1; then
            print_status "PASS" "$cmd found in PATH"
            return 0
        else
            print_status "FAIL" "$cmd not found in PATH"
            return 1
        fi
    fi
}

# Function to check conda environment
check_environment() {
    local env_name=$1
    
    if conda env list | grep -q "^$env_name "; then
        print_status "PASS" "Conda environment $env_name exists"
        return 0
    else
        print_status "FAIL" "Conda environment $env_name not found"
        return 1
    fi
}

# Function to validate unified environment
validate_unified_environment() {
    print_status "INFO" "Validating unified environment..."
    
    if ! check_environment "metanextviro-unified"; then
        return 1
    fi
    
    # Core tools that should be in unified environment
    local tools=(
        "fastqc"
        "multiqc"
        "fastp"
        "megahit"
        "spades.py"
        "blastn"
        "diamond"
        "kraken2"
        "quast.py"
        "checkv"
        "bowtie2"
        "samtools"
    )
    
    local failed_tools=0
    for tool in "${tools[@]}"; do
        if ! check_command "$tool" "metanextviro-unified"; then
            ((failed_tools++))
        fi
    done
    
    if [ $failed_tools -eq 0 ]; then
        print_status "PASS" "All core tools found in unified environment"
    else
        print_status "FAIL" "$failed_tools core tools missing from unified environment"
    fi
}

# Function to validate per-process environments
validate_per_process_environments() {
    print_status "INFO" "Validating per-process environments..."
    
    local environments=(
        "metanextviro-qc"
        "metanextviro-trimming"
        "metanextviro-assembly"
        "metanextviro-annotation"
        "metanextviro-taxonomy"
        "metanextviro-alignment"
        "metanextviro-viral"
    )
    
    local failed_envs=0
    for env in "${environments[@]}"; do
        if ! check_environment "$env"; then
            ((failed_envs++))
        fi
    done
    
    if [ $failed_envs -eq 0 ]; then
        print_status "PASS" "All per-process environments found"
    else
        print_status "WARN" "$failed_envs per-process environments missing (optional for unified mode)"
    fi
}

# Function to check system requirements
check_system_requirements() {
    print_status "INFO" "Checking system requirements..."
    
    # Check available memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -ge 4 ]; then
        print_status "PASS" "Sufficient memory available: ${mem_gb}GB"
    else
        print_status "WARN" "Low memory available: ${mem_gb}GB (recommended: 8GB+)"
    fi
    
    # Check disk space
    local disk_gb=$(df -BG /workspace | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$disk_gb" -ge 10 ]; then
        print_status "PASS" "Sufficient disk space: ${disk_gb}GB"
    else
        print_status "WARN" "Low disk space: ${disk_gb}GB (recommended: 50GB+)"
    fi
    
    # Check conda installation
    if command -v conda >/dev/null 2>&1; then
        local conda_version=$(conda --version | cut -d' ' -f2)
        print_status "PASS" "Conda installed: $conda_version"
    else
        print_status "FAIL" "Conda not found"
    fi
}

# Function to test basic functionality
test_basic_functionality() {
    if [ "$HEALTH_CHECK_MODE" = true ]; then
        return 0  # Skip functionality tests in health check mode
    fi
    
    print_status "INFO" "Testing basic functionality..."
    
    # Test Python import
    if conda run -n metanextviro-unified python -c "import pandas, matplotlib, biopython" 2>/dev/null; then
        print_status "PASS" "Python packages import successfully"
    else
        print_status "FAIL" "Python package import failed"
    fi
    
    # Test R packages (if available)
    if conda run -n metanextviro-unified Rscript -e "library(VirFinder)" 2>/dev/null; then
        print_status "PASS" "R packages load successfully"
    else
        print_status "WARN" "R package loading failed (may be expected in some configurations)"
    fi
}

# Main validation
main() {
    echo "MetaNextViro Container Validation"
    echo "================================="
    
    check_system_requirements
    validate_unified_environment
    validate_per_process_environments
    test_basic_functionality
    
    echo ""
    if [ "$VALIDATION_PASSED" = true ]; then
        print_status "PASS" "Container validation completed successfully"
        exit 0
    else
        print_status "FAIL" "Container validation failed"
        exit 1
    fi
}

# Run main function
main "$@"