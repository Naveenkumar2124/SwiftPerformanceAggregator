#!/bin/bash
# Swift Performance Metrics Aggregator - Test Integration Script
# This script helps you test the integration with an existing Swift project

# Default values
PROJECT_PATH=""
PROJECT_NAME=""
CONFIG_PATH="./performance-config.json"
COLLECT_METRICS=true
GENERATE_REPORT=true
START_SERVER=false
SERVER_PORT=8080

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --project)
      PROJECT_PATH="$2"
      shift
      shift
      ;;
    --name)
      PROJECT_NAME="$2"
      shift
      shift
      ;;
    --config)
      CONFIG_PATH="$2"
      shift
      shift
      ;;
    --no-collect)
      COLLECT_METRICS=false
      shift
      ;;
    --no-report)
      GENERATE_REPORT=false
      shift
      ;;
    --server)
      START_SERVER=true
      shift
      ;;
    --port)
      SERVER_PORT="$2"
      shift
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --project PATH    Path to your Swift project"
      echo "  --name NAME       Name of your project"
      echo "  --config PATH     Path to configuration file (default: ./performance-config.json)"
      echo "  --no-collect      Skip metrics collection"
      echo "  --no-report       Skip report generation"
      echo "  --server          Start the API server"
      echo "  --port PORT       Server port (default: 8080)"
      echo "  --help            Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check required arguments
if [ -z "$PROJECT_PATH" ]; then
  echo "Error: Project path is required"
  echo "Use --help for usage information"
  exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
  # Extract project name from path if not provided
  PROJECT_NAME=$(basename "$PROJECT_PATH")
  echo "Using project name: $PROJECT_NAME"
fi

# Check if project exists
if [ ! -d "$PROJECT_PATH" ]; then
  echo "Error: Project directory does not exist: $PROJECT_PATH"
  exit 1
fi

# Build the Swift Performance Aggregator
echo "Building Swift Performance Aggregator..."
cd "$(dirname "$0")/.."
swift build

if [ $? -ne 0 ]; then
  echo "Error: Failed to build Swift Performance Aggregator"
  exit 1
fi

# Create default configuration if it doesn't exist
if [ ! -f "$CONFIG_PATH" ]; then
  echo "Creating default configuration at $CONFIG_PATH..."
  
  # Get current user's home directory
  HOME_DIR=$(eval echo ~$USER)
  STORAGE_PATH="$HOME_DIR/Library/Application Support/PerformanceMetrics"
  
  cat > "$CONFIG_PATH" << EOL
{
  "projectName": "$PROJECT_NAME",
  "enabledCollectors": ["xctest", "instruments", "buildTime"],
  "visualizationOptions": {
    "enabledCharts": ["timeline", "heatmap", "comparison"],
    "defaultTimeRange": {
      "days": 30
    },
    "colorScheme": "system"
  },
  "storage": {
    "type": "file",
    "path": "$STORAGE_PATH",
    "retentionDays": 90
  }
}
EOL
  
  echo "Default configuration created"
fi

# Collect metrics
if [ "$COLLECT_METRICS" = true ]; then
  echo "Collecting performance metrics..."
  ./.build/debug/spa-cli collect --project "$PROJECT_PATH" --project-name "$PROJECT_NAME" --config "$CONFIG_PATH"
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to collect metrics"
    exit 1
  fi
  
  echo "Metrics collection completed"
fi

# Generate report
if [ "$GENERATE_REPORT" = true ]; then
  echo "Generating performance report..."
  REPORT_PATH="./performance-report-$(date +%Y%m%d%H%M%S).json"
  
  ./.build/debug/spa-cli report --project "$PROJECT_NAME" --config "$CONFIG_PATH" --format json --output "$REPORT_PATH"
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to generate report"
    exit 1
  fi
  
  echo "Report generated: $REPORT_PATH"
fi

# Start API server
if [ "$START_SERVER" = true ]; then
  echo "Starting API server on port $SERVER_PORT..."
  
  # Update port in configuration
  TMP_CONFIG=$(mktemp)
  jq ".serverPort = $SERVER_PORT" "$CONFIG_PATH" > "$TMP_CONFIG"
  mv "$TMP_CONFIG" "$CONFIG_PATH"
  
  ./.build/debug/spa-cli serve --config "$CONFIG_PATH" &
  SERVER_PID=$!
  
  echo "API server started with PID $SERVER_PID"
  echo "Press Ctrl+C to stop the server"
  
  # Handle termination
  trap "kill $SERVER_PID; echo 'Server stopped'; exit 0" INT TERM
  
  # Wait for the server
  wait $SERVER_PID
fi

echo "All tasks completed successfully"
exit 0
