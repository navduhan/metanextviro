#!/usr/bin/env python3
"""
MetaNextViro Final Report Generator
Generates a comprehensive HTML report from pipeline outputs.
"""

import argparse
import os
import glob
from datetime import datetime
from pathlib import Path


def find_files(pattern, directory="."):
    """Find files matching a pattern in a directory."""
    if not directory or directory == "[]":
        return []
    files = []
    if isinstance(directory, str):
        directories = [directory]
    else:
        directories = directory
    
    for d in directories:
        if os.path.isdir(d):
            files.extend(glob.glob(os.path.join(d, "**", "*"), recursive=True))
            files.extend(glob.glob(os.path.join(d, "*")))
        elif os.path.isfile(d):
            files.append(d)
    
    return [f for f in files if os.path.isfile(f)]


def get_file_list_html(files, section_name):
    """Generate HTML list for files."""
    if not files:
        return f"<p>No {section_name} files available.</p>"
    
    html = "<ul class='file-list'>"
    for f in sorted(set(files)):
        filename = os.path.basename(f)
        html += f"<li><span class='icon'>📄</span>{filename}</li>"
    html += "</ul>"
    return html


def generate_report(args):
    """Generate the HTML report."""
    
    # Collect all files from input directories
    kraken2_files = find_files("*", args.kraken2_reports) if args.kraken2_reports else []
    fastqc_files = find_files("*", args.fastqc_reports) if args.fastqc_reports else []
    coverage_files = find_files("*", args.coverage_stats) if args.coverage_stats else []
    checkv_files = find_files("*", args.checkv_results) if args.checkv_results else []
    virfinder_full_files = find_files("*", args.virfinder_full) if args.virfinder_full else []
    virfinder_filtered_files = find_files("*", args.virfinder_filtered) if args.virfinder_filtered else []
    blast_files = find_files("*", args.blast_results) if args.blast_results else []
    assembly_files = find_files("*", args.assembly_results) if args.assembly_results else []
    
    # Get current timestamp
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # Generate HTML report
    html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MetaNextViro Final Report</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: #f4f7f9;
            color: #333;
            margin: 0;
            padding: 20px;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: #fff;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.05);
        }}
        h1 {{
            font-size: 2.5em;
            color: #2c3e50;
            border-bottom: 4px solid #3498db;
            padding-bottom: 15px;
            margin-bottom: 20px;
        }}
        h2 {{
            font-size: 1.8em;
            color: #34495e;
            margin-top: 40px;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #ecf0f1;
        }}
        .card {{
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 5px;
            padding: 20px;
            margin-bottom: 20px;
        }}
        .file-list {{
            list-style-type: none;
            padding: 0;
        }}
        .file-list li {{
            padding: 12px;
            border-bottom: 1px solid #ecf0f1;
            display: flex;
            align-items: center;
        }}
        .file-list li:last-child {{
            border-bottom: none;
        }}
        .icon {{
            margin-right: 12px;
            font-size: 1.2em;
        }}
        .summary {{
            background: #eaf5ff;
            border-left: 5px solid #3498db;
            padding: 20px;
            margin-bottom: 30px;
        }}
        .timestamp {{
            text-align: right;
            color: #7f8c8d;
            font-style: italic;
            margin-top: 30px;
        }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .stat-card {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }}
        .stat-number {{
            font-size: 2em;
            font-weight: bold;
        }}
        .stat-label {{
            font-size: 0.9em;
            opacity: 0.9;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🧬 MetaNextViro Analysis Report</h1>
        
        <div class="summary">
            <p>This report summarizes the results from the MetaNextViro pipeline.</p>
            <p><strong>Report generated:</strong> {timestamp}</p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number">{len(set(fastqc_files))}</div>
                <div class="stat-label">FastQC Reports</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{len(set(kraken2_files))}</div>
                <div class="stat-label">Kraken2 Reports</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{len(set(assembly_files))}</div>
                <div class="stat-label">Assembly Files</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{len(set(blast_files))}</div>
                <div class="stat-label">BLAST Results</div>
            </div>
        </div>

        <div class="card">
            <h2>📊 Quality Control (FastQC)</h2>
            {get_file_list_html(fastqc_files, "FastQC")}
        </div>

        <div class="card">
            <h2>🦠 Taxonomic Classification (Kraken2)</h2>
            {get_file_list_html(kraken2_files, "Kraken2")}
        </div>

        <div class="card">
            <h2>🔬 BLAST Annotation</h2>
            {get_file_list_html(blast_files, "BLAST")}
        </div>

        <div class="card">
            <h2>🧩 Assembly Results</h2>
            {get_file_list_html(assembly_files, "assembly")}
        </div>

        <div class="card">
            <h2>🔍 Viral Analysis - CheckV</h2>
            {get_file_list_html(checkv_files, "CheckV")}
        </div>

        <div class="card">
            <h2>🦠 Viral Analysis - VirFinder (Full)</h2>
            {get_file_list_html(virfinder_full_files, "VirFinder full")}
        </div>

        <div class="card">
            <h2>🦠 Viral Analysis - VirFinder (Filtered)</h2>
            {get_file_list_html(virfinder_filtered_files, "VirFinder filtered")}
        </div>

        <div class="card">
            <h2>📈 Coverage Analysis</h2>
            {get_file_list_html(coverage_files, "coverage")}
        </div>

        <div class="timestamp">
            Report generated by MetaNextViro pipeline on {timestamp}
        </div>
    </div>
</body>
</html>
'''
    
    # Write the report
    with open(args.output, 'w') as f:
        f.write(html)
    
    print(f"Report generated: {args.output}")


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Generate MetaNextViro HTML report")
    
    parser.add_argument("--kraken2-reports", nargs="*", default=[], 
                        help="Kraken2 report files")
    parser.add_argument("--fastqc-reports", nargs="*", default=[], 
                        help="FastQC report files")
    parser.add_argument("--coverage-stats", nargs="*", default=[], 
                        help="Coverage statistics files")
    parser.add_argument("--checkv-results", nargs="*", default=[], 
                        help="CheckV result directories")
    parser.add_argument("--virfinder-full", nargs="*", default=[], 
                        help="VirFinder full result files")
    parser.add_argument("--virfinder-filtered", nargs="*", default=[], 
                        help="VirFinder filtered result files")
    parser.add_argument("--blast-results", nargs="*", default=[], 
                        help="BLAST result files")
    parser.add_argument("--assembly-results", nargs="*", default=[], 
                        help="Assembly result files")
    parser.add_argument("--output", "-o", default="final_report.html",
                        help="Output HTML file")
    
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    generate_report(args)
