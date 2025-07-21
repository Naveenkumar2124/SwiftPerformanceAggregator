# Swift Performance Metrics Aggregator

A comprehensive tool for collecting, analyzing, and visualizing performance metrics from Swift projects. This tool integrates with Windsurf UI to provide rich visualizations of performance data.

## Features

- Collects performance metrics from multiple sources:
  - Xcode Instruments
  - XCTest Performance Tests
  - MetricKit
  - Swift Concurrency Analyzer
  - Build Time Analysis
- Normalizes and aggregates data for unified analysis
- Includes customizable visualization components
- Works with both new and existing Swift projects

## Getting Started

### Prerequisites

- Xcode 13.0+
- Swift 5.5+
- macOS 12.0+

### Installation

```bash
git clone https://github.com/Naveenkumar2124/SwiftPerformanceAggregator.git
cd swift-performance-aggregator

Usage
As a Command Line Tool
bash
# Collect metrics from a project

chmod +x simple-module-report.sh

./simple-module-report.sh


Web Interface
The Performance Monitor includes a powerful web interface for interactive analysis and visualization of performance metrics.

Web Interface Features
Interactive Dashboard: Visual representation of performance metrics with filtering options
Project Selection: Easily select any Swift project folder to analyze
Customizable Analysis: Choose which types of performance issues to scan for
Detailed Reports: View issues categorized by module, feature, and severity
Data Visualization: Interactive charts and graphs to identify problem areas
Export Options: Export reports as CSV or PDF for sharing with your team
Setting Up the Web Interface
Navigate to the web interface directory:
bash
cd web-interface
Install dependencies:
bash
npm install
Start the server:
bash
npm start
# or use the convenience script
./start.sh
Open your browser and navigate to:
http://localhost:3000
Analysis Options
The web interface allows you to analyze your Swift project for various performance issues:

Main Thread Blocking: Identify operations that could block the main thread
Large Files: Find oversized view controllers and view models
Memory Leaks: Detect potential memory leaks in closures and delegates
Force Unwraps: Locate excessive use of force unwrapping
UI Updates: Find complex UI update logic that may cause performance issues
Understanding Results
Analysis results are presented in four intuitive tabs:

Summary: Overview of issues by severity and type, plus top problematic files
By Module: Breakdown of issues by module with visualization
By Feature: Detailed view of issues by feature within each module
All Issues: Complete list of all detected issues with filtering options
Requirements
Node.js 14+
Modern web browser (Chrome, Firefox, Safari, Edge)
macOS (for analyzing Swift projects)

License
This project is licensed under the MIT License - see the LICENSE file for details.
