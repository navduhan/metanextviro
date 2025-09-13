#!/bin/bash

# MetaNextViro Environment Activation Script
# This script activates the appropriate conda environment based on the mode

set -euo pipefail

# Default to unified mode if not specified
ENV_MODE=${METANEXTVIRO_ENV_MODE:-unified}

# Function to activate environment
activate_environment() {
    local env_name=$1
    echo "Activating conda environment: $env_name"
    
    # Check if environment exists
    if conda env list | grep -q "^$env_name "; then
        source activate "$env_name"
        echo "Successfully activated environment: $env_name"
        return 0
    else
        echo "Error: Environment $env_name not found"
        return 1
    fi
}

# Function to list available environments
list_environments() {
    echo "Available conda environments:"
    conda env list | grep metanextviro
}

# Main logic
case "$ENV_MODE" in
    "unified")
        activate_environment "metanextviro-unified"
        ;;
    "per_process")
        echo "Per-process mode enabled. Environments will be activated as needed by processes."
        list_environments
        ;;
    *)
        echo "Unknown environment mode: $ENV_MODE"
        echo "Valid modes: unified, per_process"
        list_environments
        exit 1
        ;;
esac

# If a specific environment is requested as argument
if [ $# -gt 0 ]; then
    activate_environment "$1"
fi