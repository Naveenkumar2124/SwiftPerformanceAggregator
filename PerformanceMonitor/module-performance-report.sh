#!/bin/bash

# Set project path
PROJECT_PATH="/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen"

echo "Analyzing application performance issues by module at $PROJECT_PATH..."

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
CSV_FILE="$METRICS_DIR/module_performance_issues_$TIMESTAMP.csv"
SUMMARY_FILE="$METRICS_DIR/module_summary_$TIMESTAMP.csv"

# Create CSV header
echo "Module,Issue Type,File Path,Line Number,Issue Description,Severity,Recommendation" > "$CSV_FILE"
echo "Module,High Issues,Medium Issues,Low Issues,Total Issues" > "$SUMMARY_FILE"

# Define modules based on directory structure
declare -a MODULES=(
  "SalesProPlus"
  "SalesLeadPlus"
  "Communications"
  "Contracting"
  "GoTool"
  "Cockpit"
  "Common"
  "Pods"
)

# Function to determine module from file path
get_module() {
  local file_path="$1"
  local rel_path=${file_path#$PROJECT_PATH/}
  
  for module in "${MODULES[@]}"; do
    if [[ "$rel_path" == "$module"* ]]; then
      echo "$module"
      return
    fi
  done
  
  # Default to "Other" if no match found
  echo "Other"
}

# Function to safely add an issue to the CSV file
add_issue() {
  local module="$1"
  local issue_type="$2"
  local file_path="$3"
  local line_number="$4"
  local description="$5"
  local severity="$6"
  local recommendation="$7"
  
  # Get relative path for better readability
  local rel_path=${file_path#$PROJECT_PATH/}
  
  # Escape quotes and commas
  description=$(echo "$description" | sed 's/"/""/g')
  recommendation=$(echo "$recommendation" | sed 's/"/""/g')
  
  echo "\"$module\",\"$issue_type\",\"$rel_path\",\"$line_number\",\"$description\",\"$severity\",\"$recommendation\"" >> "$CSV_FILE"
}

# Initialize counters for each module
declare -A HIGH_COUNTS
declare -A MEDIUM_COUNTS
declare -A LOW_COUNTS
declare -A TOTAL_COUNTS

for module in "${MODULES[@]}" "Other"; do
  HIGH_COUNTS["$module"]=0
  MEDIUM_COUNTS["$module"]=0
  LOW_COUNTS["$module"]=0
  TOTAL_COUNTS["$module"]=0
done

echo "Finding main thread blocking database operations..."
# Find database operations (potentially on main thread)
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  grep -n "fetch" "$file" | head -n 20 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "$module" "Main Thread Blocking" "$file" "$line_number" "Database operation potentially on main thread" "High" "Move database operations to a background queue using DispatchQueue.global().async"
      ((HIGH_COUNTS["$module"]++))
      ((TOTAL_COUNTS["$module"]++))
    fi
  done
done

echo "Finding large view controllers..."
# Find large view controllers
find "$PROJECT_PATH" -name "*ViewController*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "$module" "Large View Controller" "$file" "N/A" "View controller with $line_count lines" "High" "Break down large view controllers into smaller components"
    ((HIGH_COUNTS["$module"]++))
    ((TOTAL_COUNTS["$module"]++))
  fi
done

echo "Finding large view models..."
# Find large view models
find "$PROJECT_PATH" -name "*ViewModel*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "$module" "Large View Model" "$file" "N/A" "View model with $line_count lines" "High" "Break down large view models into smaller components"
    ((HIGH_COUNTS["$module"]++))
    ((TOTAL_COUNTS["$module"]++))
  fi
done

echo "Finding potential memory leaks in closures..."
# Find potential memory leaks in closures
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  grep -n "self\." "$file" | grep "{" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak self" "$file"; then
        add_issue "$module" "Memory Leak" "$file" "$line_number" "Potential strong reference cycle in closure" "High" "Use [weak self] in closure capture list"
        ((HIGH_COUNTS["$module"]++))
        ((TOTAL_COUNTS["$module"]++))
      fi
    fi
  done
done

echo "Finding delegate properties not marked as weak..."
# Find delegate properties not marked as weak
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  grep -n "delegate" "$file" | grep "var" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak" <(echo "${BASH_REMATCH[2]}"); then
        add_issue "$module" "Memory Leak" "$file" "$line_number" "Delegate property not marked as weak" "High" "Mark delegate properties as weak to prevent retain cycles"
        ((HIGH_COUNTS["$module"]++))
        ((TOTAL_COUNTS["$module"]++))
      fi
    fi
  done
done

echo "Finding force unwraps..."
# Find files with excessive force unwraps
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  unwrap_count=$(grep -o "!" "$file" | wc -l)
  if [ "$unwrap_count" -gt 20 ]; then
    add_issue "$module" "Crash Risk" "$file" "N/A" "File contains $unwrap_count force unwraps" "Medium" "Replace force unwraps with optional binding or nil coalescing"
    ((MEDIUM_COUNTS["$module"]++))
    ((TOTAL_COUNTS["$module"]++))
  fi
done

echo "Finding complex UI update logic..."
# Find complex UI update logic in main thread
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  grep -n "DispatchQueue.main.async" "$file" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "$module" "UI Performance" "$file" "$line_number" "Complex UI update on main thread" "Medium" "Minimize work in main thread UI updates"
      ((MEDIUM_COUNTS["$module"]++))
      ((TOTAL_COUNTS["$module"]++))
    fi
  done
done

echo "Finding timer usage without invalidation..."
# Find timer usage without invalidation
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  module=$(get_module "$file")
  if grep -q "Timer" "$file" && ! grep -q "invalidate" "$file"; then
    add_issue "$module" "Resource Usage" "$file" "N/A" "Timer usage without invalidation" "Medium" "Always invalidate timers in deinit or when they are no longer needed"
    ((MEDIUM_COUNTS["$module"]++))
    ((TOTAL_COUNTS["$module"]++))
  fi
done

# Generate module summary
for module in "${MODULES[@]}" "Other"; do
  echo "\"$module\",${HIGH_COUNTS["$module"]},${MEDIUM_COUNTS["$module"]},${LOW_COUNTS["$module"]},${TOTAL_COUNTS["$module"]}" >> "$SUMMARY_FILE"
done

# Calculate totals
TOTAL_HIGH=0
TOTAL_MEDIUM=0
TOTAL_LOW=0
TOTAL_ALL=0

for module in "${MODULES[@]}" "Other"; do
  TOTAL_HIGH=$((TOTAL_HIGH + ${HIGH_COUNTS["$module"]}))
  TOTAL_MEDIUM=$((TOTAL_MEDIUM + ${MEDIUM_COUNTS["$module"]}))
  TOTAL_LOW=$((TOTAL_LOW + ${LOW_COUNTS["$module"]}))
  TOTAL_ALL=$((TOTAL_ALL + ${TOTAL_COUNTS["$module"]}))
done

echo "\"TOTAL\",\"$TOTAL_HIGH\",\"$TOTAL_MEDIUM\",\"$TOTAL_LOW\",\"$TOTAL_ALL\"" >> "$SUMMARY_FILE"

echo ""
echo "Performance Issues Summary by Module:"
echo "--------------------------------"
echo "Module         | High  | Medium | Low   | Total"
echo "--------------------------------"

# Print module summary
for module in "${MODULES[@]}" "Other"; do
  printf "%-14s | %-5s | %-6s | %-5s | %-5s\n" \
    "$module" "${HIGH_COUNTS["$module"]}" "${MEDIUM_COUNTS["$module"]}" "${LOW_COUNTS["$module"]}" "${TOTAL_COUNTS["$module"]}"
done

echo "--------------------------------"
printf "%-14s | %-5s | %-6s | %-5s | %-5s\n" \
  "TOTAL" "$TOTAL_HIGH" "$TOTAL_MEDIUM" "$TOTAL_LOW" "$TOTAL_ALL"
echo ""

echo "Analysis complete! Results saved to:"
echo "1. Detailed report: $CSV_FILE"
echo "2. Module summary: $SUMMARY_FILE"
echo ""
echo "You can open these CSV files in Excel for a detailed analysis of performance issues by module."
