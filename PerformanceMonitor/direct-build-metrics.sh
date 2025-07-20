#!/bin/bash

# Set project path and scheme
PROJECT_PATH="/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen"
SCHEME="SalesPro-QA"

echo "Running direct build metrics collection for $SCHEME..."

# Check if the project directory exists
if [ ! -d "$PROJECT_PATH" ]; then
  echo "Error: Project directory not found at $PROJECT_PATH"
  exit 1
fi

# Find workspace or project
WORKSPACE=$(find "$PROJECT_PATH" -maxdepth 1 -name "*.xcworkspace" | head -n 1)
XCODEPROJ=$(find "$PROJECT_PATH" -maxdepth 1 -name "*.xcodeproj" | head -n 1)

if [ -z "$WORKSPACE" ] && [ -z "$XCODEPROJ" ]; then
  echo "Error: No Xcode project or workspace found in $PROJECT_PATH"
  exit 1
fi

# Determine if we're using a workspace or project
if [ ! -z "$WORKSPACE" ]; then
  echo "Found workspace: $(basename "$WORKSPACE")"
  PROJECT_TYPE="workspace"
  PROJECT_FILE="$WORKSPACE"
else
  echo "Found project: $(basename "$XCODEPROJ")"
  PROJECT_TYPE="project"
  PROJECT_FILE="$XCODEPROJ"
fi

# Verify the scheme exists
echo "Verifying scheme $SCHEME exists..."
SCHEME_EXISTS=$(xcrun xcodebuild -list -"$PROJECT_TYPE" "$PROJECT_FILE" 2>/dev/null | grep -A 100 "Schemes:" | grep -w "$SCHEME")

if [ -z "$SCHEME_EXISTS" ]; then
  echo "Error: Scheme $SCHEME not found in $(basename "$PROJECT_FILE")"
  echo "Available schemes:"
  xcrun xcodebuild -list -"$PROJECT_TYPE" "$PROJECT_FILE" 2>/dev/null | grep -A 100 "Schemes:" | grep -v "Schemes:" | grep -v "^$" | sed 's/^[ \t]*//'
  exit 1
fi

echo "Scheme $SCHEME verified."

# Create metrics directory
METRICS_DIR="./metrics_data"
mkdir -p "$METRICS_DIR"

# Clean the project first
echo "Cleaning project..."
xcrun xcodebuild clean -"$PROJECT_TYPE" "$PROJECT_FILE" -scheme "$SCHEME" 2>/dev/null

# Measure build time
echo "Building project and measuring time..."
START_TIME=$(date +%s)

BUILD_OUTPUT=$(xcrun xcodebuild build -"$PROJECT_TYPE" "$PROJECT_FILE" -scheme "$SCHEME" -configuration Debug 2>&1)
BUILD_STATUS=$?

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))

if [ $BUILD_STATUS -eq 0 ]; then
  echo "Build successful. Duration: $BUILD_DURATION seconds"
  
  # Save metrics to a JSON file
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat > "$METRICS_DIR/build_metrics_$TIMESTAMP.json" << EOF
{
  "projectName": "pep-swift-shngen",
  "metrics": [
    {
      "source": "buildTime",
      "type": "buildDuration",
      "value": $BUILD_DURATION,
      "unit": "seconds",
      "timestamp": "$TIMESTAMP",
      "metadata": {
        "scheme": "$SCHEME"
      }
    }
  ]
}
EOF

  echo "Metrics saved to $METRICS_DIR/build_metrics_$TIMESTAMP.json"
  
  # Extract per-file build times if available
  echo "Analyzing per-file build times..."
  
  # Count files built
  FILE_COUNT=$(echo "$BUILD_OUTPUT" | grep -c "CompileSwift")
  echo "Files compiled: $FILE_COUNT"
  
  # Show slowest files
  echo "Slowest files to compile:"
  echo "$BUILD_OUTPUT" | grep -A 1 "CompileSwift" | grep -B 1 "seconds" | head -n 10
  
else
  echo "Build failed with status $BUILD_STATUS"
  echo "Build output:"
  echo "$BUILD_OUTPUT"
fi
