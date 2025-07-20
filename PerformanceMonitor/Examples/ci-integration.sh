#!/bin/bash
# Swift Performance Metrics Aggregator - CI Integration Script
# This script demonstrates how to integrate performance metrics collection
# into your CI/CD pipeline for Swift projects

# Configuration
PROJECT_PATH="$CI_PROJECT_DIR"  # Adjust based on your CI environment
PROJECT_NAME="YourSwiftApp"
COMMIT_HASH=$(git rev-parse HEAD)
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
METRICS_SERVER="https://your-metrics-server.com"
API_KEY="YOUR_API_KEY"

# Build paths
SPA_CLI_PATH="$HOME/.spa/bin/spa-cli"
CONFIG_PATH="$HOME/.spa/config/performance-config.json"

# Ensure the Swift Performance Aggregator is installed
install_spa() {
  echo "Installing Swift Performance Aggregator..."
  mkdir -p "$HOME/.spa/bin"
  
  # Clone and build the Swift Performance Aggregator
  git clone https://github.com/yourusername/swift-performance-aggregator.git /tmp/spa
  cd /tmp/spa
  swift build -c release
  cp .build/release/spa-cli "$SPA_CLI_PATH"
  
  # Create default configuration
  mkdir -p "$HOME/.spa/config"
  "$SPA_CLI_PATH" config --project "$PROJECT_NAME" --output "$CONFIG_PATH" --create-default
  
  echo "Installation complete."
}

# Check if SPA is installed
if [ ! -f "$SPA_CLI_PATH" ]; then
  install_spa
fi

# Function to collect performance metrics
collect_metrics() {
  echo "Collecting performance metrics for $PROJECT_NAME..."
  
  # Run the metrics collection
  "$SPA_CLI_PATH" collect \
    --project "$PROJECT_PATH" \
    --project-name "$PROJECT_NAME" \
    --config "$CONFIG_PATH" \
    --commit "$COMMIT_HASH" \
    --branch "$BRANCH_NAME"
    
  if [ $? -ne 0 ]; then
    echo "Error: Failed to collect performance metrics"
    return 1
  fi
  
  echo "Performance metrics collection completed successfully."
  return 0
}

# Function to send metrics to Windsurf
send_to_windsurf() {
  echo "Sending performance metrics to Windsurf..."
  
  # Generate a report
  REPORT_PATH="/tmp/performance-report-$COMMIT_HASH.json"
  "$SPA_CLI_PATH" report \
    --project "$PROJECT_NAME" \
    --config "$CONFIG_PATH" \
    --format json \
    --output "$REPORT_PATH"
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to generate performance report"
    return 1
  fi
  
  # Send the report to Windsurf API
  curl -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d @"$REPORT_PATH" \
    "$METRICS_SERVER/api/performance-metrics"
    
  if [ $? -ne 0 ]; then
    echo "Error: Failed to send metrics to Windsurf"
    return 1
  fi
  
  echo "Performance metrics sent to Windsurf successfully."
  return 0
}

# Main execution
echo "Starting performance metrics collection for $PROJECT_NAME ($COMMIT_HASH)"

# Only run on specific branches or for specific events
if [ "$CI_EVENT_TYPE" == "pull_request" ] || [ "$BRANCH_NAME" == "main" ] || [ "$BRANCH_NAME" == "develop" ]; then
  collect_metrics
  send_to_windsurf
else
  echo "Skipping performance metrics collection for branch $BRANCH_NAME"
fi

echo "Performance metrics process completed."
exit 0
