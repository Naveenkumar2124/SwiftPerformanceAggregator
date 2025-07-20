#!/bin/bash

# Set project path
PROJECT_PATH="/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen"

echo "Analyzing application performance issues by module and feature at $PROJECT_PATH..."

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
CSV_FILE="$METRICS_DIR/feature_performance_issues_$TIMESTAMP.csv"
SUMMARY_FILE="$METRICS_DIR/feature_summary_$TIMESTAMP.csv"

# Create CSV header
echo "Module,Feature,Issue Type,File Path,Line Number,Issue Description,Severity,Recommendation" > "$CSV_FILE"
echo "Module,Feature,High Issues,Medium Issues,Low Issues,Total Issues" > "$SUMMARY_FILE"

# Define modules based on directory structure
MODULES="SalesProPlus SalesLeadPlus Communications Contracting GoTool Cockpit Common Pods Other"

# Function to determine module from file path
get_module() {
  local file_path="$1"
  local rel_path=${file_path#$PROJECT_PATH/}
  
  for module in $MODULES; do
    if [[ "$rel_path" == "$module"* ]]; then
      echo "$module"
      return
    fi
  done
  
  # Default to "Other" if no match found
  echo "Other"
}

# Function to determine feature from file path
get_feature() {
  local file_path="$1"
  local module="$2"
  local rel_path=${file_path#$PROJECT_PATH/}
  
  # Remove module prefix from path
  local feature_path=${rel_path#$module/}
  
  # Extract feature from path
  if [[ "$feature_path" == *"/"* ]]; then
    # Try to get feature from directory structure
    local feature=$(echo "$feature_path" | cut -d'/' -f1-2)
    
    # If feature contains "Presentation", try to get more specific
    if [[ "$feature" == *"Presentation"* ]]; then
      feature=$(echo "$feature_path" | cut -d'/' -f1-3)
    fi
    
    # If feature contains "Domain", try to get more specific
    if [[ "$feature" == *"Domain"* ]]; then
      feature=$(echo "$feature_path" | cut -d'/' -f1-3)
    fi
    
    # If feature contains "Data", try to get more specific
    if [[ "$feature" == *"Data"* ]]; then
      feature=$(echo "$feature_path" | cut -d'/' -f1-3)
    fi
    
    echo "$feature"
  else
    # If no subdirectory, use filename as feature
    echo "$feature_path"
  fi
}

# Function to safely add an issue to the CSV file
add_issue() {
  local module="$1"
  local feature="$2"
  local issue_type="$3"
  local file_path="$4"
  local line_number="$5"
  local description="$6"
  local severity="$7"
  local recommendation="$8"
  
  # Get relative path for better readability
  local rel_path=${file_path#$PROJECT_PATH/}
  
  # Escape quotes and commas
  description=$(echo "$description" | sed 's/"/""/g')
  recommendation=$(echo "$recommendation" | sed 's/"/""/g')
  
  echo "\"$module\",\"$feature\",\"$issue_type\",\"$rel_path\",\"$line_number\",\"$description\",\"$severity\",\"$recommendation\"" >> "$CSV_FILE"
}

# Create temporary directory for count files
COUNT_DIR=$(mktemp -d)

echo "Finding main thread blocking database operations..."
# Find database operations (potentially on main thread)
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  grep -n "fetch" "$file" | head -n 20 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "$module" "$feature" "Main Thread Blocking" "$file" "$line_number" "Database operation potentially on main thread" "High" "Move database operations to a background queue using DispatchQueue.global().async"
      
      # Increment high count and total count
      counts=$(cat "$count_file")
      high=$(echo "$counts" | awk '{print $1}')
      medium=$(echo "$counts" | awk '{print $2}')
      low=$(echo "$counts" | awk '{print $3}')
      total=$(echo "$counts" | awk '{print $4}')
      high=$((high + 1))
      total=$((total + 1))
      echo "$high $medium $low $total" > "$count_file"
    fi
  done
done

echo "Finding large view controllers..."
# Find large view controllers
find "$PROJECT_PATH" -name "*ViewController*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "$module" "$feature" "Large View Controller" "$file" "N/A" "View controller with $line_count lines" "High" "Break down large view controllers into smaller components"
    
    # Increment high count and total count
    counts=$(cat "$count_file")
    high=$(echo "$counts" | awk '{print $1}')
    medium=$(echo "$counts" | awk '{print $2}')
    low=$(echo "$counts" | awk '{print $3}')
    total=$(echo "$counts" | awk '{print $4}')
    high=$((high + 1))
    total=$((total + 1))
    echo "$high $medium $low $total" > "$count_file"
  fi
done

echo "Finding large view models..."
# Find large view models
find "$PROJECT_PATH" -name "*ViewModel*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "$module" "$feature" "Large View Model" "$file" "N/A" "View model with $line_count lines" "High" "Break down large view models into smaller components"
    
    # Increment high count and total count
    counts=$(cat "$count_file")
    high=$(echo "$counts" | awk '{print $1}')
    medium=$(echo "$counts" | awk '{print $2}')
    low=$(echo "$counts" | awk '{print $3}')
    total=$(echo "$counts" | awk '{print $4}')
    high=$((high + 1))
    total=$((total + 1))
    echo "$high $medium $low $total" > "$count_file"
  fi
done

echo "Finding potential memory leaks in closures..."
# Find potential memory leaks in closures
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  grep -n "self\." "$file" | grep "{" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak self" "$file"; then
        add_issue "$module" "$feature" "Memory Leak" "$file" "$line_number" "Potential strong reference cycle in closure" "High" "Use [weak self] in closure capture list"
        
        # Increment high count and total count
        counts=$(cat "$count_file")
        high=$(echo "$counts" | awk '{print $1}')
        medium=$(echo "$counts" | awk '{print $2}')
        low=$(echo "$counts" | awk '{print $3}')
        total=$(echo "$counts" | awk '{print $4}')
        high=$((high + 1))
        total=$((total + 1))
        echo "$high $medium $low $total" > "$count_file"
      fi
    fi
  done
done

echo "Finding delegate properties not marked as weak..."
# Find delegate properties not marked as weak
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  grep -n "delegate" "$file" | grep "var" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak" <(echo "${BASH_REMATCH[2]}"); then
        add_issue "$module" "$feature" "Memory Leak" "$file" "$line_number" "Delegate property not marked as weak" "High" "Mark delegate properties as weak to prevent retain cycles"
        
        # Increment high count and total count
        counts=$(cat "$count_file")
        high=$(echo "$counts" | awk '{print $1}')
        medium=$(echo "$counts" | awk '{print $2}')
        low=$(echo "$counts" | awk '{print $3}')
        total=$(echo "$counts" | awk '{print $4}')
        high=$((high + 1))
        total=$((total + 1))
        echo "$high $medium $low $total" > "$count_file"
      fi
    fi
  done
done

echo "Finding force unwraps..."
# Find files with excessive force unwraps
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  unwrap_count=$(grep -o "!" "$file" | wc -l)
  if [ "$unwrap_count" -gt 20 ]; then
    add_issue "$module" "$feature" "Crash Risk" "$file" "N/A" "File contains $unwrap_count force unwraps" "Medium" "Replace force unwraps with optional binding or nil coalescing"
    
    # Increment medium count and total count
    counts=$(cat "$count_file")
    high=$(echo "$counts" | awk '{print $1}')
    medium=$(echo "$counts" | awk '{print $2}')
    low=$(echo "$counts" | awk '{print $3}')
    total=$(echo "$counts" | awk '{print $4}')
    medium=$((medium + 1))
    total=$((total + 1))
    echo "$high $medium $low $total" > "$count_file"
  fi
done

echo "Finding complex UI update logic..."
# Find complex UI update logic in main thread
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  grep -n "DispatchQueue.main.async" "$file" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "$module" "$feature" "UI Performance" "$file" "$line_number" "Complex UI update on main thread" "Medium" "Minimize work in main thread UI updates"
      
      # Increment medium count and total count
      counts=$(cat "$count_file")
      high=$(echo "$counts" | awk '{print $1}')
      medium=$(echo "$counts" | awk '{print $2}')
      low=$(echo "$counts" | awk '{print $3}')
      total=$(echo "$counts" | awk '{print $4}')
      medium=$((medium + 1))
      total=$((total + 1))
      echo "$high $medium $low $total" > "$count_file"
    fi
  done
done

echo "Finding timer usage without invalidation..."
# Find timer usage without invalidation
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  feature=$(get_feature "$file" "$module")
  
  # Create count file for this module/feature if it doesn't exist
  count_file="$COUNT_DIR/${module}_${feature//\//_}"
  if [ ! -f "$count_file" ]; then
    echo "0 0 0 0" > "$count_file"  # high medium low total
  fi
  
  if grep -q "Timer" "$file" && ! grep -q "invalidate" "$file"; then
    add_issue "$module" "$feature" "Resource Usage" "$file" "N/A" "Timer usage without invalidation" "Medium" "Always invalidate timers in deinit or when they are no longer needed"
    
    # Increment medium count and total count
    counts=$(cat "$count_file")
    high=$(echo "$counts" | awk '{print $1}')
    medium=$(echo "$counts" | awk '{print $2}')
    low=$(echo "$counts" | awk '{print $3}')
    total=$(echo "$counts" | awk '{print $4}')
    medium=$((medium + 1))
    total=$((total + 1))
    echo "$high $medium $low $total" > "$count_file"
  fi
done

# Generate summary by module and feature
for count_file in "$COUNT_DIR"/*; do
  filename=$(basename "$count_file")
  module_feature=${filename//_/\/}
  module=$(echo "$module_feature" | cut -d'/' -f1)
  feature=${module_feature#$module/}
  
  counts=$(cat "$count_file")
  high=$(echo "$counts" | awk '{print $1}')
  medium=$(echo "$counts" | awk '{print $2}')
  low=$(echo "$counts" | awk '{print $3}')
  total=$(echo "$counts" | awk '{print $4}')
  
  if [ "$total" -gt 0 ]; then
    echo "\"$module\",\"$feature\",\"$high\",\"$medium\",\"$low\",\"$total\"" >> "$SUMMARY_FILE"
  fi
done

# Sort summary by total issues (descending)
sort -t',' -k6 -nr "$SUMMARY_FILE" > "${SUMMARY_FILE}.tmp"
head -n 1 "$SUMMARY_FILE" > "${SUMMARY_FILE}.new"  # Keep header
grep -v "Module,Feature" "${SUMMARY_FILE}.tmp" >> "${SUMMARY_FILE}.new"
mv "${SUMMARY_FILE}.new" "$SUMMARY_FILE"
rm "${SUMMARY_FILE}.tmp"

# Calculate totals
TOTAL_HIGH=0
TOTAL_MEDIUM=0
TOTAL_LOW=0
TOTAL_ALL=0

for count_file in "$COUNT_DIR"/*; do
  counts=$(cat "$count_file")
  high=$(echo "$counts" | awk '{print $1}')
  medium=$(echo "$counts" | awk '{print $2}')
  low=$(echo "$counts" | awk '{print $3}')
  total=$(echo "$counts" | awk '{print $4}')
  
  TOTAL_HIGH=$((TOTAL_HIGH + high))
  TOTAL_MEDIUM=$((TOTAL_MEDIUM + medium))
  TOTAL_LOW=$((TOTAL_LOW + low))
  TOTAL_ALL=$((TOTAL_ALL + total))
done

echo "\"TOTAL\",\"ALL\",\"$TOTAL_HIGH\",\"$TOTAL_MEDIUM\",\"$TOTAL_LOW\",\"$TOTAL_ALL\"" >> "$SUMMARY_FILE"

# Clean up temporary directory
rm -rf "$COUNT_DIR"

echo ""
echo "Performance Issues Summary:"
echo "-------------------------"
echo "High Severity: $TOTAL_HIGH issues"
echo "Medium Severity: $TOTAL_MEDIUM issues"
echo "Low Severity: $TOTAL_LOW issues"
echo "Total: $TOTAL_ALL issues"
echo ""
echo "Top 10 Most Problematic Features:"
echo "------------------------------"
grep -v "Module,Feature\|TOTAL" "$SUMMARY_FILE" | head -n 10 | while IFS=, read -r module feature high medium low total; do
  # Remove quotes
  module=${module//\"/}
  feature=${feature//\"/}
  high=${high//\"/}
  medium=${medium//\"/}
  low=${low//\"/}
  total=${total//\"/}
  
  printf "%-14s | %-30s | High: %-4s | Medium: %-4s | Total: %-4s\n" \
    "$module" "$feature" "$high" "$medium" "$total"
done

echo ""
echo "Analysis complete! Results saved to:"
echo "1. Detailed report: $CSV_FILE"
echo "2. Feature summary: $SUMMARY_FILE"
echo ""
echo "You can open these CSV files in Excel for a detailed analysis of performance issues by module and feature."
