# Swift Performance Metrics Aggregator - Windsurf Integration Guide

This guide explains how to integrate the Swift Performance Metrics Aggregator with Windsurf for enhanced code reviews with performance insights.

## Overview

The Swift Performance Metrics Aggregator collects performance data from various sources and integrates with Windsurf to provide performance insights during code reviews. This integration enables developers to:

1. View performance metrics directly in code reviews
2. Identify performance regressions early in the development cycle
3. Make data-driven decisions about performance optimizations
4. Track performance trends over time

## Setup Instructions

### 1. Add the Swift Performance Aggregator to your project

#### Option A: As a Swift Package dependency

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/swift-performance-aggregator.git", from: "1.0.0")
]
```

#### Option B: As a standalone tool

Clone the repository and build the tool:

```bash
git clone https://github.com/yourusername/swift-performance-aggregator.git
cd swift-performance-aggregator
swift build -c release
cp .build/release/spa-cli /usr/local/bin/spa-cli
```

### 2. Create a configuration file

Create a `performance-config.json` file in your project root:

```json
{
  "projectName": "YourSwiftApp",
  "enabledCollectors": ["xctest", "instruments", "metrickit", "buildTime"],
  "visualizationOptions": {
    "enabledCharts": ["timeline", "heatmap", "comparison", "distribution", "breakdown"],
    "defaultTimeRange": {
      "days": 30
    },
    "colorScheme": "system"
  },
  "windsurf": {
    "apiEndpoint": "https://your-windsurf-instance.com/api",
    "apiKey": "YOUR_API_KEY",
    "enableWebhooks": true,
    "webhookEndpoint": "https://your-performance-metrics-server.com/webhook/code-review"
  },
  "storage": {
    "type": "file",
    "path": "/path/to/metrics/storage",
    "retentionDays": 90
  }
}
```

### 3. Start the API server

Start the API server to enable communication with Windsurf:

```bash
spa-cli serve --config /path/to/performance-config.json
```

### 4. Configure Windsurf integration

In your Windsurf configuration, add the Swift Performance Metrics Aggregator as a plugin:

```json
{
  "plugins": [
    {
      "name": "swift-performance-metrics",
      "apiEndpoint": "http://localhost:8080",
      "apiKey": "YOUR_API_KEY"
    }
  ]
}
```

## Integration with CI/CD Pipeline

To automatically collect performance metrics during CI/CD runs:

1. Add the following step to your CI/CD pipeline:

```yaml
steps:
  - name: Collect Performance Metrics
    run: |
      spa-cli collect --project $PROJECT_PATH --config performance-config.json --commit $COMMIT_HASH
```

2. Configure your CI/CD system to send webhook events to the Swift Performance Metrics Aggregator when a code review is created or updated.

## Available Features

### 1. Performance Metrics Collection

The Swift Performance Metrics Aggregator collects metrics from:

- **XCTest Performance Tests**: CPU time, memory usage
- **Instruments**: CPU time, memory usage, disk I/O, network latency, energy impact
- **MetricKit**: App launch time, memory usage, energy impact
- **Build Time Analysis**: Compilation time per file

### 2. Code Review Annotations

The aggregator generates annotations for code reviews, including:

- File-level performance metrics
- Line-level performance metrics for specific functions
- Performance recommendations based on collected data

### 3. Visualization Components

The following visualizations are available in the Windsurf UI:

- **Timeline Charts**: Show performance metrics over time
- **Heatmaps**: Identify performance hotspots in your codebase
- **Comparison Charts**: Compare performance between commits
- **Metric Cards**: Display key performance indicators

## API Reference

### REST API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check endpoint |
| `/collect` | POST | Trigger metrics collection |
| `/metrics` | GET | Retrieve metrics for visualization |
| `/report` | GET | Get a performance report |
| `/webhook/code-review` | POST | Webhook for code review events |
| `/visualizations/:type` | GET | Get visualization data |
| `/annotations` | GET | Get code review annotations |
| `/windsurf-visualization` | GET | Get Windsurf visualization components |

### Command Line Interface

```
USAGE: spa-cli <subcommand>

SUBCOMMANDS:
  collect                 Collect performance metrics from a Swift project
  report                  Generate a performance report
  serve                   Start the performance metrics API server
  config                  Manage configuration
```

## Troubleshooting

### Common Issues

1. **No metrics collected**: Ensure the collectors are properly configured and the project structure is supported.
2. **API server not starting**: Check port availability and permissions.
3. **Windsurf integration not working**: Verify API keys and endpoints in both configurations.

### Logs

Logs are available at:

- API Server: Standard output or configured log file
- Collectors: `/tmp/spa-collectors.log`

## Example: Analyzing Performance Impact in Code Reviews

When a developer submits a code review, the Swift Performance Metrics Aggregator:

1. Collects performance metrics for the changed code
2. Compares metrics with the baseline (e.g., main branch)
3. Generates annotations highlighting performance impacts
4. Provides visualizations showing performance changes
5. Offers recommendations for performance improvements

This workflow helps teams maintain high-performance standards throughout the development process.

## Advanced Configuration

For advanced use cases, you can:

1. Create custom collectors for specific metrics
2. Customize visualization components
3. Implement custom storage backends
4. Extend the API with additional endpoints

Refer to the API documentation for more details on these advanced features.
