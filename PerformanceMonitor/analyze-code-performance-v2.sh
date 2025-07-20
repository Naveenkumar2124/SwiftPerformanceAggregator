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
REPORT_FILE="$METRICS_DIR/code_metrics_$TIMESTAMP.txt"

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
  cat >> "$REPORT_FILE" << EOF
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
  
  echo "LARGE SWIFT FILES (by line count)" >> "$REPORT_FILE"
  echo "--------------------------------" >> "$REPORT_FILE"
  
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 wc -l | sort -nr | head -n 20 >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  
  echo "Top 10 largest Swift files:"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 wc -l | sort -nr | head -n 10
}

# Function to find files with many imports
find_many_imports() {
  echo "Finding files with many imports..."
  
  echo "FILES WITH MANY IMPORTS" >> "$REPORT_FILE"
  echo "---------------------" >> "$REPORT_FILE"
  
  # Create a temporary file for results
  TEMP_FILE=$(mktemp)
  
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    IMPORT_COUNT=$(grep -c "^import " "$file")
    if [ "$IMPORT_COUNT" -gt 10 ]; then
      echo "$IMPORT_COUNT imports: $file" >> "$TEMP_FILE"
    fi
  done
  
  # Sort by import count (numerically, descending)
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  
  echo "Top 10 files with most imports:"
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 10
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find large view controllers
find_large_view_controllers() {
  echo "Finding large view controllers..."
  
  echo "LARGE VIEW CONTROLLERS" >> "$REPORT_FILE"
  echo "---------------------" >> "$REPORT_FILE"
  
  # Create a temporary file for results
  TEMP_FILE=$(mktemp)
  
  find "$PROJECT_PATH" -name "*ViewController*.swift" -print0 | while IFS= read -r -d '' file; do
    LINE_COUNT=$(wc -l < "$file")
    echo "$LINE_COUNT lines: $file" >> "$TEMP_FILE"
  done
  
  # Sort by line count (numerically, descending)
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  
  echo "Top 10 largest view controllers:"
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 10
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find large view models
find_large_view_models() {
  echo "Finding large view models..."
  
  echo "LARGE VIEW MODELS" >> "$REPORT_FILE"
  echo "----------------" >> "$REPORT_FILE"
  
  # Create a temporary file for results
  TEMP_FILE=$(mktemp)
  
  find "$PROJECT_PATH" -name "*ViewModel*.swift" -print0 | while IFS= read -r -d '' file; do
    LINE_COUNT=$(wc -l < "$file")
    echo "$LINE_COUNT lines: $file" >> "$TEMP_FILE"
  done
  
  # Sort by line count (numerically, descending)
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  
  echo "Top 10 largest view models:"
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 10
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find potential memory issues
find_memory_issues() {
  echo "Finding potential memory issues..."
  
  echo "POTENTIAL MEMORY ISSUES" >> "$REPORT_FILE"
  echo "----------------------" >> "$REPORT_FILE"
  
  # Look for potential retain cycles
  WEAK_SELF_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "\[\s*weak\s\+self\s*\]" | wc -l)
  UNOWNED_SELF_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "\[\s*unowned\s\+self\s*\]" | wc -l)
  STRONG_SELF_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "\[\s*self\s*\]" | wc -l)
  
  echo "Files with weak self captures: $WEAK_SELF_COUNT" >> "$REPORT_FILE"
  echo "Files with unowned self captures: $UNOWNED_SELF_COUNT" >> "$REPORT_FILE"
  echo "Files with strong self captures: $STRONG_SELF_COUNT" >> "$REPORT_FILE"
  
  echo "Files with weak self captures: $WEAK_SELF_COUNT"
  echo "Files with unowned self captures: $UNOWNED_SELF_COUNT"
  echo "Files with strong self captures: $STRONG_SELF_COUNT"
  
  echo "" >> "$REPORT_FILE"
}

# Function to find UI performance issues
find_ui_issues() {
  echo "Finding potential UI performance issues..."
  
  echo "UI PERFORMANCE ISSUES" >> "$REPORT_FILE"
  echo "-------------------" >> "$REPORT_FILE"
  
  # Look for main thread blocking operations
  MAIN_SYNC_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "DispatchQueue.main.sync" | wc -l)
  echo "Files with DispatchQueue.main.sync: $MAIN_SYNC_COUNT" >> "$REPORT_FILE"
  echo "Files with DispatchQueue.main.sync: $MAIN_SYNC_COUNT"
  
  echo "" >> "$REPORT_FILE"
}

# Function to analyze database operations
analyze_database() {
  echo "Analyzing database operations..."
  
  echo "DATABASE OPERATIONS" >> "$REPORT_FILE"
  echo "------------------" >> "$REPORT_FILE"
  
  # Count CoreData and Couchbase usages
  COREDATA_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "NSManagedObject\|NSFetchRequest\|NSPersistentContainer" | wc -l)
  COUCHBASE_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "CouchbaseLite\|Database\|Query" | wc -l)
  
  echo "Files with CoreData operations: $COREDATA_COUNT" >> "$REPORT_FILE"
  echo "Files with Couchbase operations: $COUCHBASE_COUNT" >> "$REPORT_FILE"
  
  echo "Files with CoreData operations: $COREDATA_COUNT"
  echo "Files with Couchbase operations: $COUCHBASE_COUNT"
  
  echo "" >> "$REPORT_FILE"
}

# Function to find force unwraps
find_force_unwraps() {
  echo "Finding force unwraps..."
  
  echo "FORCE UNWRAPS" >> "$REPORT_FILE"
  echo "-------------" >> "$REPORT_FILE"
  
  # Count files with force unwraps
  FORCE_UNWRAP_COUNT=$(find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "!" | wc -l)
  
  echo "Files with force unwraps: $FORCE_UNWRAP_COUNT" >> "$REPORT_FILE"
  echo "Files with force unwraps: $FORCE_UNWRAP_COUNT"
  
  # Find top 10 files with most force unwraps
  echo "Top 10 files with most force unwraps:" >> "$REPORT_FILE"
  
  TEMP_FILE=$(mktemp)
  
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    UNWRAP_COUNT=$(grep -o "!" "$file" | wc -l)
    if [ "$UNWRAP_COUNT" -gt 10 ]; then
      echo "$UNWRAP_COUNT unwraps: $file" >> "$TEMP_FILE"
    fi
  done
  
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 10 >> "$REPORT_FILE"
  echo "Top 10 files with most force unwraps:"
  sort -nr -t':' -k1 "$TEMP_FILE" | head -n 10
  
  # Clean up
  rm "$TEMP_FILE"
  
  echo "" >> "$REPORT_FILE"
}

# Run all analysis functions
echo "Starting code performance analysis..."
echo "CODE PERFORMANCE ANALYSIS - $TIMESTAMP" > "$REPORT_FILE"
echo "===============================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

count_files_by_type
find_large_files
find_many_imports
find_large_view_controllers
find_large_view_models
find_memory_issues
find_ui_issues
analyze_database
find_force_unwraps

echo "Analysis complete! Results saved to $REPORT_FILE"
echo "You can review this file for potential performance issues in the codebase."
