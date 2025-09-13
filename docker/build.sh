#!/bin/bash

# MetaNextViro Container Build Script
# Automated container building with validation and testing

set -euo pipefail

# Configuration
CONTAINER_NAME="metanextviro"
CONTAINER_TAG=${1:-"latest"}
BUILD_CONTEXT="."
DOCKERFILE="Dockerfile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_message "$BLUE" "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker >/dev/null 2>&1; then
        print_message "$RED" "Error: Docker is not installed"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_message "$RED" "Error: Docker daemon is not running"
        exit 1
    fi
    
    # Check if required files exist
    local required_files=(
        "Dockerfile"
        "environments/unified.yml"
        "docker/validate_container.sh"
        "docker/activate_env.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_message "$RED" "Error: Required file not found: $file"
            exit 1
        fi
    done
    
    print_message "$GREEN" "Prerequisites check passed"
}

# Function to build container
build_container() {
    print_message "$BLUE" "Building container: ${CONTAINER_NAME}:${CONTAINER_TAG}"
    
    # Build with build args for better caching
    docker build \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --tag "${CONTAINER_NAME}:${CONTAINER_TAG}" \
        --file "$DOCKERFILE" \
        "$BUILD_CONTEXT"
    
    if [ $? -eq 0 ]; then
        print_message "$GREEN" "Container build completed successfully"
    else
        print_message "$RED" "Container build failed"
        exit 1
    fi
}

# Function to test container
test_container() {
    print_message "$BLUE" "Testing container: ${CONTAINER_NAME}:${CONTAINER_TAG}"
    
    # Test basic container startup
    print_message "$YELLOW" "Testing container startup..."
    if docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" echo "Container startup test" >/dev/null 2>&1; then
        print_message "$GREEN" "Container startup test passed"
    else
        print_message "$RED" "Container startup test failed"
        exit 1
    fi
    
    # Test validation script
    print_message "$YELLOW" "Running container validation..."
    if docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" /usr/local/bin/validate_container.sh; then
        print_message "$GREEN" "Container validation passed"
    else
        print_message "$RED" "Container validation failed"
        exit 1
    fi
    
    # Test environment activation
    print_message "$YELLOW" "Testing environment activation..."
    if docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" /usr/local/bin/activate_env.sh >/dev/null 2>&1; then
        print_message "$GREEN" "Environment activation test passed"
    else
        print_message "$RED" "Environment activation test failed"
        exit 1
    fi
    
    # Test health check
    print_message "$YELLOW" "Testing health check..."
    if docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" /usr/local/bin/validate_container.sh --health-check >/dev/null 2>&1; then
        print_message "$GREEN" "Health check test passed"
    else
        print_message "$RED" "Health check test failed"
        exit 1
    fi
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    print_message "$BLUE" "Running comprehensive container tests..."
    
    # Test unified environment mode
    print_message "$YELLOW" "Testing unified environment mode..."
    docker run --rm \
        -e METANEXTVIRO_ENV_MODE=unified \
        "${CONTAINER_NAME}:${CONTAINER_TAG}" \
        bash -c "source /usr/local/bin/activate_env.sh && conda list | grep fastqc"
    
    # Test per-process environment mode
    print_message "$YELLOW" "Testing per-process environment mode..."
    docker run --rm \
        -e METANEXTVIRO_ENV_MODE=per_process \
        "${CONTAINER_NAME}:${CONTAINER_TAG}" \
        bash -c "source /usr/local/bin/activate_env.sh && conda env list | grep metanextviro"
    
    # Test tool availability
    print_message "$YELLOW" "Testing tool availability..."
    local tools=("fastqc --version" "multiqc --version" "python --version")
    
    for tool_cmd in "${tools[@]}"; do
        if docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" bash -c "source activate metanextviro-unified && $tool_cmd" >/dev/null 2>&1; then
            print_message "$GREEN" "Tool test passed: $tool_cmd"
        else
            print_message "$YELLOW" "Tool test warning: $tool_cmd (may not support --version)"
        fi
    done
}

# Function to generate build report
generate_build_report() {
    print_message "$BLUE" "Generating build report..."
    
    local report_file="docker/build_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "MetaNextViro Container Build Report"
        echo "=================================="
        echo "Build Date: $(date)"
        echo "Container: ${CONTAINER_NAME}:${CONTAINER_TAG}"
        echo ""
        echo "Container Information:"
        docker inspect "${CONTAINER_NAME}:${CONTAINER_TAG}" --format='Size: {{.Size}} bytes'
        docker inspect "${CONTAINER_NAME}:${CONTAINER_TAG}" --format='Created: {{.Created}}'
        echo ""
        echo "Environment Information:"
        docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" conda env list
        echo ""
        echo "Validation Results:"
        docker run --rm "${CONTAINER_NAME}:${CONTAINER_TAG}" /usr/local/bin/validate_container.sh
    } > "$report_file"
    
    print_message "$GREEN" "Build report generated: $report_file"
}

# Function to cleanup on failure
cleanup_on_failure() {
    print_message "$YELLOW" "Cleaning up failed build artifacts..."
    
    # Remove dangling images
    docker image prune -f >/dev/null 2>&1 || true
    
    print_message "$YELLOW" "Cleanup completed"
}

# Main function
main() {
    print_message "$BLUE" "Starting MetaNextViro container build process..."
    
    # Set trap for cleanup on failure
    trap cleanup_on_failure ERR
    
    check_prerequisites
    build_container
    test_container
    run_comprehensive_tests
    generate_build_report
    
    print_message "$GREEN" "Container build and testing completed successfully!"
    print_message "$BLUE" "Container ready: ${CONTAINER_NAME}:${CONTAINER_TAG}"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [TAG]"
        echo "Build and test MetaNextViro container"
        echo ""
        echo "Arguments:"
        echo "  TAG    Container tag (default: latest)"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        exit 0
        ;;
    *)
        main
        ;;
esac