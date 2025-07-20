#!/bin/bash

# Set project path
PROJECT_PATH="/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen"

echo "Analyzing code performance for project at $PROJECT_PATH..."

# Check if the project directory exists
if [ ! -d "$PROJECT_PATH" ]; then
  echo "Error: Project directory not found at $PROJECT_PATH"
  exit 1
fi

# Create output directory
METRICS_DIR="./metrics_data"
mkdir -p "$METRICS_DIR"

# Get current timestamp for reports
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Function to count files by type
count_files_by_type() {
  echo "Counting files by type..."
  
  SWIFT_COUNT=$(find "$PROJECT_PATH" -name "*.swift" | wc -l)
  STORYBOARD_COUNT=$(find "$PROJECT_PATH" -name "*.storyboard" | wc -l)
  XIB_COUNT=$(find "$PROJECT_PATH" -name "*.xib" | wc -l)
  ASSET_CATALOG_COUNT=$(find "$PROJECT_PATH" -name "*.xcassets" | wc -l)
  
  echo "Swift files: $SWIFT_COUNT"
  echo "Storyboard files: $STORYBOARD_COUNT"
  echo "XIB files: $XIB_COUNT"
  echo "Asset catalogs: $ASSET_CATALOG_COUNT"
  
  # Save to report
  cat >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt" << EOF
FILE COUNTS
-----------
Swift files: $SWIFT_COUNT
Storyboard files: $STORYBOARD_COUNT
XIB files: $XIB_COUNT
Asset catalogs: $ASSET_CATALOG_COUNT

EOF
}

# Function to find large Swift files
find_large_files() {
  echo "Finding large Swift files..."
  
  echo "LARGE SWIFT FILES (by line count)" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "--------------------------------" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  find "$PROJECT_PATH" -name "*.swift" -exec wc -l {} \; | sort -nr | head -n 20 >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  echo "Top 10 largest Swift files:"
  find "$PROJECT_PATH" -name "*.swift" -exec wc -l {} \; | sort -nr | head -n 10
}

# Function to find complex functions
find_complex_functions() {
  echo "Finding complex functions (functions with many lines)..."
  
  echo "COMPLEX FUNCTIONS" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "-----------------" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  # Find functions with many lines (potential complexity)
  for file in $(find "$PROJECT_PATH" -name "*.swift"); do
    FUNCTIONS=$(grep -n "func " "$file" | cut -d: -f1,2)
    
    while IFS= read -r line; do
      if [ ! -z "$line" ]; then
        LINE_NUM=$(echo "$line" | cut -d: -f1)
        FUNC_NAME=$(echo "$line" | cut -d: -f2 | sed 's/func //g' | sed 's/{.*//g' | tr -d '\n')
        
        # Count lines in function (approximate)
        NEXT_FUNC_LINE=$(grep -A1 -n "func " "$file" | grep -A1 "$LINE_NUM:" | tail -n1 | cut -d- -f1 | cut -d: -f1)
        
        if [ -z "$NEXT_FUNC_LINE" ]; then
          # If this is the last function, count to end of file
          NEXT_FUNC_LINE=$(wc -l < "$file")
        fi
        
        FUNC_SIZE=$((NEXT_FUNC_LINE - LINE_NUM))
        
        if [ $FUNC_SIZE -gt 50 ]; then
          RELATIVE_PATH=${file#$PROJECT_PATH/}
          echo "$RELATIVE_PATH:$LINE_NUM - $FUNC_NAME ($FUNC_SIZE lines)" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
        fi
      fi
    done <<< "$FUNCTIONS"
  done
  
  # Sort by function size
  cat "$METRICS_DIR/code_metrics_$TIMESTAMP.txt" | grep "lines)" | sort -t'(' -k2 -nr | head -n 20 >> "$METRICS_DIR/complex_functions_$TIMESTAMP.txt"
  echo "" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  echo "Top 10 most complex functions:"
  cat "$METRICS_DIR/complex_functions_$TIMESTAMP.txt" | head -n 10
}

# Function to find potential memory issues
find_memory_issues() {
  echo "Finding potential memory issues..."
  
  echo "POTENTIAL MEMORY ISSUES" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "----------------------" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  # Look for large arrays/dictionaries
  echo "Large collections:" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  grep -r --include="*.swift" -n "= \[" "$PROJECT_PATH" | grep -E "\{.{100,}" | head -n 20 >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  # Look for potential retain cycles
  echo "Potential retain cycles (self captures in closures):" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  grep -r --include="*.swift" -n "\[\s*weak\s\+self\s*\]" "$PROJECT_PATH" | wc -l >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  grep -r --include="*.swift" -n "\[\s*unowned\s\+self\s*\]" "$PROJECT_PATH" | wc -l >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  grep -r --include="*.swift" -n "\[\s*self\s*\]" "$PROJECT_PATH" | wc -l >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  echo "" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
}

# Function to find UI performance issues
find_ui_issues() {
  echo "Finding potential UI performance issues..."
  
  echo "UI PERFORMANCE ISSUES" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "-------------------" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  # Look for main thread blocking operations
  echo "Potential main thread blocking:" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  grep -r --include="*.swift" -n "DispatchQueue.main.sync" "$PROJECT_PATH" | head -n 20 >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  # Look for heavy operations in UI lifecycle methods
  echo "Heavy operations in viewDidLoad:" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  grep -r --include="*.swift" -A 20 "func viewDidLoad" "$PROJECT_PATH" | grep -E "(for|while|repeat|switch)" | head -n 20 >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  echo "" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
}

# Function to analyze network operations
analyze_network() {
  echo "Analyzing network operations..."
  
  echo "NETWORK OPERATIONS" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "-----------------" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  # Count URLSession usages
  URL_SESSION_COUNT=$(grep -r --include="*.swift" "URLSession" "$PROJECT_PATH" | wc -l)
  ALAMOFIRE_COUNT=$(grep -r --include="*.swift" "Alamofire" "$PROJECT_PATH" | wc -l)
  
  echo "URLSession usages: $URL_SESSION_COUNT" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  echo "Alamofire usages: $ALAMOFIRE_COUNT" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
  
  echo "" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
}

# Run all analysis functions
echo "Starting code performance analysis..."
echo "CODE PERFORMANCE ANALYSIS - $TIMESTAMP" > "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
echo "===============================" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"
echo "" >> "$METRICS_DIR/code_metrics_$TIMESTAMP.txt"

count_files_by_type
find_large_files
find_complex_functions
find_memory_issues
find_ui_issues
analyze_network

echo "Analysis complete! Results saved to $METRICS_DIR/code_metrics_$TIMESTAMP.txt"
echo "You can review this file for potential performance issues in the codebase."
