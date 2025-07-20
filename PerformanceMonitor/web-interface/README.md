# Swift Performance Analyzer Web Interface

This web interface provides an interactive way to analyze Swift projects for performance issues, with detailed reports and visualizations.

## Features

- **Project Selection**: Choose any Swift project folder to analyze
- **Customizable Analysis**: Select which types of performance issues to scan for
- **Interactive Reports**: View issues by module, feature, and severity
- **Data Visualization**: Charts and graphs to help identify problem areas
- **Export Options**: Export reports as CSV or PDF

## Setup Instructions

1. Install Node.js dependencies:

```bash
cd /Users/naveen/Documents/Pepsico/PerformanceMonitor/web-interface
npm install
```

2. Start the server:

```bash
npm start
```

3. Open your browser and navigate to:

```
http://localhost:3000
```

## How to Use

1. Enter the path to your Swift project or click "Browse" to select it
2. Select which types of performance issues you want to analyze
3. Click "Analyze Project" to start the analysis
4. View the results in the interactive dashboard
5. Export the results as CSV or PDF for sharing

## Analysis Options

- **Main Thread Blocking**: Find operations that could block the main thread
- **Large Files**: Identify oversized view controllers and view models
- **Memory Leaks**: Detect potential memory leaks in closures and delegates
- **Force Unwraps**: Find excessive use of force unwrapping
- **UI Updates**: Identify complex UI update logic that may cause performance issues

## Understanding the Results

The analysis results are presented in four tabs:

1. **Summary**: Overview of issues by severity and type, plus top problematic files
2. **By Module**: Breakdown of issues by module with visualization
3. **By Feature**: Detailed view of issues by feature within each module
4. **All Issues**: Complete list of all detected issues with filtering options

## Troubleshooting

If you encounter any issues:

- Make sure the project path is correct and accessible
- Check that Node.js is installed correctly
- Verify that all dependencies are installed
- Check the console for any error messages

## Requirements

- Node.js 14+
- Modern web browser (Chrome, Firefox, Safari, Edge)
- macOS (for analyzing Swift projects)
