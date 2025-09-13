/*
 * Environment Validation Subworkflow
 * 
 * This subworkflow validates the environment setup for the MetaNextViro pipeline
 * including conda environment files, dependencies, and conflict detection
 */

// Import environment management library
include { EnvironmentManager } from '../lib/EnvironmentManager.groovy'

workflow ENVIRONMENT_VALIDATION {
    take:
        env_mode        // Environment mode: 'unified' or 'per_process'
        project_dir     // Project directory path
        
    main:
        // Initialize environment manager
        def envManager = new EnvironmentManager(env_mode, project_dir, params)
        
        // Validate environment files
        VALIDATE_ENV_FILES(envManager)
        
        // Check for package conflicts
        CHECK_PACKAGE_CONFLICTS(envManager)
        
        // Validate conda availability
        VALIDATE_CONDA_SETUP()
        
        // Test environment creation (optional)
        if (params.test_env_creation) {
            TEST_ENVIRONMENT_CREATION(envManager)
        }
        
    emit:
        validation_report = VALIDATE_ENV_FILES.out.report
        conflict_report = CHECK_PACKAGE_CONFLICTS.out.conflicts
        conda_status = VALIDATE_CONDA_SETUP.out.status
}

/*
 * Validate environment files exist and have correct format
 */
process VALIDATE_ENV_FILES {
    tag "env_validation"
    label 'process_quick'
    
    input:
    val envManager
    
    output:
    path "environment_validation_report.json", emit: report
    
    script:
    """
    #!/usr/bin/env python3
    
    import json
    import yaml
    import os
    from pathlib import Path
    
    def validate_environment_file(env_path):
        \"\"\"Validate a single environment file\"\"\"
        errors = []
        warnings = []
        
        if not os.path.exists(env_path):
            errors.append(f"Environment file not found: {env_path}")
            return {"valid": False, "errors": errors, "warnings": warnings}
        
        try:
            with open(env_path, 'r') as f:
                content = yaml.safe_load(f)
            
            # Check required fields
            if 'name' not in content:
                errors.append(f"Missing 'name' field in {env_path}")
            
            if 'dependencies' not in content:
                errors.append(f"Missing 'dependencies' field in {env_path}")
            elif not isinstance(content['dependencies'], list):
                errors.append(f"'dependencies' must be a list in {env_path}")
            
            # Check channels
            if 'channels' not in content:
                warnings.append(f"No 'channels' specified in {env_path}")
            elif not isinstance(content['channels'], list):
                errors.append(f"'channels' must be a list in {env_path}")
            
            # Validate dependencies format
            for dep in content.get('dependencies', []):
                if isinstance(dep, str):
                    # Check for valid package name format
                    if '=' in dep:
                        pkg_name, version = dep.split('=', 1)
                        if not pkg_name.strip():
                            errors.append(f"Invalid package specification: '{dep}' in {env_path}")
                elif isinstance(dep, dict):
                    # Handle pip dependencies
                    if 'pip' in dep:
                        if not isinstance(dep['pip'], list):
                            errors.append(f"pip dependencies must be a list in {env_path}")
                else:
                    warnings.append(f"Unusual dependency format: {dep} in {env_path}")
            
        except yaml.YAMLError as e:
            errors.append(f"Invalid YAML syntax in {env_path}: {str(e)}")
        except Exception as e:
            errors.append(f"Error reading {env_path}: {str(e)}")
        
        return {
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings
        }
    
    def main():
        # Environment paths based on mode
        env_mode = "${env_mode}"
        project_dir = "${project_dir}"
        
        validation_results = {
            "mode": env_mode,
            "timestamp": "\$(date -Iseconds)",
            "environments": {},
            "overall_valid": True,
            "total_errors": 0,
            "total_warnings": 0
        }
        
        if env_mode == "unified":
            env_path = os.path.join(project_dir, "environments/unified.yml")
            result = validate_environment_file(env_path)
            validation_results["environments"]["unified"] = result
            
            if not result["valid"]:
                validation_results["overall_valid"] = False
            
            validation_results["total_errors"] += len(result["errors"])
            validation_results["total_warnings"] += len(result["warnings"])
            
        else:  # per_process mode
            env_files = [
                "qc.yml", "trimming.yml", "assembly.yml", "annotation.yml",
                "taxonomy.yml", "viral.yml", "alignment.yml"
            ]
            
            for env_file in env_files:
                env_path = os.path.join(project_dir, "environments", env_file)
                env_name = env_file.replace('.yml', '')
                result = validate_environment_file(env_path)
                validation_results["environments"][env_name] = result
                
                if not result["valid"]:
                    validation_results["overall_valid"] = False
                
                validation_results["total_errors"] += len(result["errors"])
                validation_results["total_warnings"] += len(result["warnings"])
        
        # Write validation report
        with open("environment_validation_report.json", "w") as f:
            json.dump(validation_results, f, indent=2)
        
        # Print summary
        print(f"Environment validation completed for mode: {env_mode}")
        print(f"Overall valid: {validation_results['overall_valid']}")
        print(f"Total errors: {validation_results['total_errors']}")
        print(f"Total warnings: {validation_results['total_warnings']}")
        
        if not validation_results["overall_valid"]:
            print("\\nValidation errors found:")
            for env_name, result in validation_results["environments"].items():
                if result["errors"]:
                    print(f"  {env_name}:")
                    for error in result["errors"]:
                        print(f"    - {error}")
    
    if __name__ == "__main__":
        main()
    """
}

/*
 * Check for package conflicts between environments
 */
process CHECK_PACKAGE_CONFLICTS {
    tag "conflict_detection"
    label 'process_quick'
    
    input:
    val envManager
    
    output:
    path "conflict_report.json", emit: conflicts
    
    script:
    """
    #!/usr/bin/env python3
    
    import json
    import yaml
    import os
    from collections import defaultdict
    
    def extract_packages(dependencies):
        \"\"\"Extract package names and versions from dependencies list\"\"\"
        packages = {}
        
        for dep in dependencies:
            if isinstance(dep, str):
                if '=' in dep:
                    name, version = dep.split('=', 1)
                    packages[name.strip()] = version.strip()
                else:
                    packages[dep.strip()] = None
            elif isinstance(dep, dict) and 'pip' in dep:
                # Handle pip dependencies
                for pip_dep in dep['pip']:
                    if isinstance(pip_dep, str):
                        if '==' in pip_dep:
                            name, version = pip_dep.split('==', 1)
                            packages[f"pip:{name.strip()}"] = version.strip()
                        else:
                            packages[f"pip:{pip_dep.strip()}"] = None
        
        return packages
    
    def detect_conflicts(env_packages):
        \"\"\"Detect version conflicts between environments\"\"\"
        conflicts = []
        all_packages = defaultdict(dict)
        
        # Collect all package versions across environments
        for env_name, packages in env_packages.items():
            for pkg_name, version in packages.items():
                all_packages[pkg_name][env_name] = version
        
        # Check for conflicts
        for pkg_name, env_versions in all_packages.items():
            if len(env_versions) > 1:
                versions = set(v for v in env_versions.values() if v is not None)
                if len(versions) > 1:
                    conflicts.append({
                        "package": pkg_name,
                        "environments": env_versions,
                        "conflicting_versions": list(versions),
                        "severity": "high" if pkg_name in ["python", "r-base", "numpy"] else "medium"
                    })
        
        return conflicts
    
    def main():
        env_mode = "${env_mode}"
        project_dir = "${project_dir}"
        
        conflict_report = {
            "mode": env_mode,
            "timestamp": "\$(date -Iseconds)",
            "conflicts": [],
            "recommendations": []
        }
        
        if env_mode == "per_process":
            env_files = [
                "qc.yml", "trimming.yml", "assembly.yml", "annotation.yml",
                "taxonomy.yml", "viral.yml", "alignment.yml"
            ]
            
            env_packages = {}
            
            # Load all environment files
            for env_file in env_files:
                env_path = os.path.join(project_dir, "environments", env_file)
                env_name = env_file.replace('.yml', '')
                
                if os.path.exists(env_path):
                    try:
                        with open(env_path, 'r') as f:
                            content = yaml.safe_load(f)
                        
                        packages = extract_packages(content.get('dependencies', []))
                        env_packages[env_name] = packages
                        
                    except Exception as e:
                        print(f"Error reading {env_path}: {e}")
            
            # Detect conflicts
            conflicts = detect_conflicts(env_packages)
            conflict_report["conflicts"] = conflicts
            
            # Generate recommendations
            if conflicts:
                conflict_report["recommendations"] = [
                    "Consider using unified environment mode to avoid version conflicts",
                    "Pin package versions consistently across all environments",
                    "Use conda-forge channel for better dependency resolution"
                ]
                
                for conflict in conflicts:
                    if conflict["severity"] == "high":
                        conflict_report["recommendations"].append(
                            f"Critical: Resolve {conflict['package']} version conflict immediately"
                        )
        
        else:
            # Unified mode - no inter-environment conflicts possible
            conflict_report["conflicts"] = []
            conflict_report["recommendations"] = [
                "Unified environment mode eliminates inter-environment conflicts"
            ]
        
        # Write conflict report
        with open("conflict_report.json", "w") as f:
            json.dump(conflict_report, f, indent=2)
        
        print(f"Conflict detection completed for mode: {env_mode}")
        print(f"Conflicts found: {len(conflict_report['conflicts'])}")
        
        if conflict_report["conflicts"]:
            print("\\nConflicts detected:")
            for conflict in conflict_report["conflicts"]:
                print(f"  - {conflict['package']}: {conflict['conflicting_versions']}")
    
    if __name__ == "__main__":
        main()
    """
}

/*
 * Validate conda installation and availability
 */
process VALIDATE_CONDA_SETUP {
    tag "conda_validation"
    label 'process_quick'
    
    output:
    path "conda_status.json", emit: status
    
    script:
    """
    #!/bin/bash
    
    # Initialize status report
    cat > conda_status.json << 'EOF'
    {
        "conda_available": false,
        "conda_version": null,
        "mamba_available": false,
        "mamba_version": null,
        "channels_configured": [],
        "cache_dir": null,
        "recommendations": []
    }
    EOF
    
    # Check conda availability
    if command -v conda &> /dev/null; then
        conda_version=\$(conda --version 2>/dev/null | cut -d' ' -f2)
        echo "Conda found: version \$conda_version"
        
        # Update JSON with conda info
        python3 -c "
    import json
    with open('conda_status.json', 'r') as f:
        data = json.load(f)
    data['conda_available'] = True
    data['conda_version'] = '\$conda_version'
    
    # Get conda info
    import subprocess
    try:
        result = subprocess.run(['conda', 'info', '--json'], capture_output=True, text=True)
        if result.returncode == 0:
            conda_info = json.loads(result.stdout)
            data['channels_configured'] = conda_info.get('channels', [])
            data['cache_dir'] = conda_info.get('pkgs_dirs', [None])[0]
    except:
        pass
    
    with open('conda_status.json', 'w') as f:
        json.dump(data, f, indent=2)
    "
    else
        echo "Conda not found in PATH"
    fi
    
    # Check mamba availability
    if command -v mamba &> /dev/null; then
        mamba_version=\$(mamba --version 2>/dev/null | head -1 | cut -d' ' -f2)
        echo "Mamba found: version \$mamba_version"
        
        # Update JSON with mamba info
        python3 -c "
    import json
    with open('conda_status.json', 'r') as f:
        data = json.load(f)
    data['mamba_available'] = True
    data['mamba_version'] = '\$mamba_version'
    with open('conda_status.json', 'w') as f:
        json.dump(data, f, indent=2)
    "
    else
        echo "Mamba not found in PATH"
    fi
    
    # Add recommendations
    python3 -c "
    import json
    with open('conda_status.json', 'r') as f:
        data = json.load(f)
    
    recommendations = []
    
    if not data['conda_available']:
        recommendations.append('Install conda or miniconda to use conda environments')
    
    if not data['mamba_available']:
        recommendations.append('Install mamba for faster environment resolution: conda install mamba')
    
    required_channels = ['bioconda', 'conda-forge', 'defaults']
    missing_channels = [ch for ch in required_channels if ch not in data['channels_configured']]
    if missing_channels:
        recommendations.append(f'Add missing channels: conda config --add channels {\" \".join(missing_channels)}')
    
    data['recommendations'] = recommendations
    
    with open('conda_status.json', 'w') as f:
        json.dump(data, f, indent=2)
    "
    
    echo "Conda validation completed"
    """
}

/*
 * Test environment creation (optional)
 */
process TEST_ENVIRONMENT_CREATION {
    tag "env_creation_test"
    label 'process_medium'
    
    input:
    val envManager
    
    output:
    path "creation_test_report.json", emit: test_report
    
    when:
    params.test_env_creation
    
    script:
    """
    #!/bin/bash
    
    echo "Testing environment creation..."
    
    # Initialize test report
    cat > creation_test_report.json << 'EOF'
    {
        "mode": "${env_mode}",
        "timestamp": "\$(date -Iseconds)",
        "tests": {},
        "overall_success": true
    }
    EOF
    
    # Function to test environment creation
    test_env_creation() {
        local env_file=\$1
        local env_name=\$2
        
        echo "Testing creation of environment: \$env_name"
        
        # Create temporary environment name
        local temp_env_name="test_\${env_name}_\$(date +%s)"
        
        # Test environment creation (dry-run)
        if conda env create -n \$temp_env_name -f \$env_file --dry-run &> /dev/null; then
            echo "✓ Environment \$env_name can be created successfully"
            
            # Update test report
            python3 -c "
    import json
    with open('creation_test_report.json', 'r') as f:
        data = json.load(f)
    data['tests']['\$env_name'] = {'success': True, 'error': None}
    with open('creation_test_report.json', 'w') as f:
        json.dump(data, f, indent=2)
    "
        else
            echo "✗ Environment \$env_name creation failed"
            
            # Update test report with error
            python3 -c "
    import json
    with open('creation_test_report.json', 'r') as f:
        data = json.load(f)
    data['tests']['\$env_name'] = {'success': False, 'error': 'Dry-run creation failed'}
    data['overall_success'] = False
    with open('creation_test_report.json', 'w') as f:
        json.dump(data, f, indent=2)
    "
        fi
    }
    
    # Test based on environment mode
    if [ "${env_mode}" = "unified" ]; then
        test_env_creation "${project_dir}/environments/unified.yml" "unified"
    else
        # Test all per-process environments
        for env_file in ${project_dir}/environments/*.yml; do
            if [ -f "\$env_file" ] && [ "\$(basename \$env_file)" != "unified.yml" ]; then
                env_name=\$(basename \$env_file .yml)
                test_env_creation "\$env_file" "\$env_name"
            fi
        done
    fi
    
    echo "Environment creation testing completed"
    """
}