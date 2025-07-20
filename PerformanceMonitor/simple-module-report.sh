#!/bin/bash

# Set default project path
DEFAULT_PROJECT_PATH="YOUR Project PATH"

# Allow overriding project path via command line argument
PROJECT_PATH="${1:-$DEFAULT_PROJECT_PATH}"

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
echo "Module,Issue Type,File Path,Line Number,Issue Description,Severity,Recommendation,Impact" > "$CSV_FILE"
echo "Module,High Issues,Medium Issues,Low Issues,Total Issues" > "$SUMMARY_FILE"

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
  
  # Determine impact based on severity
  local impact
  
  case "$severity" in
    "High")
      impact="User-facing performance degradation"
      ;;
    "Medium")
      impact="Internal performance degradation"
      ;;
    "Low")
      impact="Minor code quality issue"
      ;;
    *)
      impact="Unknown"
      ;;
  esac
  
  # Escape quotes and commas
  description=$(echo "$description" | sed 's/"/""/g')
  recommendation=$(echo "$recommendation" | sed 's/"/""/g')
  impact=$(echo "$impact" | sed 's/"/""/g')
  
  echo "\"$module\",\"$issue_type\",\"$rel_path\",\"$line_number\",\"$description\",\"$severity\",\"$recommendation\",\"$impact\"" >> "$CSV_FILE"
}

# Create temporary files to store counts
HIGH_COUNT_FILE=$(mktemp)
MEDIUM_COUNT_FILE=$(mktemp)
LOW_COUNT_FILE=$(mktemp)
TOTAL_COUNT_FILE=$(mktemp)

# Initialize count files
for module in $MODULES; do
  echo "$module 0" >> "$HIGH_COUNT_FILE"
  echo "$module 0" >> "$MEDIUM_COUNT_FILE"
  echo "$module 0" >> "$LOW_COUNT_FILE"
  echo "$module 0" >> "$TOTAL_COUNT_FILE"
done

# Function to increment counter
increment_counter() {
  local module="$1"
  local severity="$2"
  local count_file
  
  case "$severity" in
    "High")
      count_file="$HIGH_COUNT_FILE"
      ;;
    "Medium")
      count_file="$MEDIUM_COUNT_FILE"
      ;;
    "Low")
      count_file="$LOW_COUNT_FILE"
      ;;
  esac
  
  # Increment the specific counter
  awk -v mod="$module" '{if ($1 == mod) {$2++} print}' "$count_file" > "${count_file}.tmp"
  mv "${count_file}.tmp" "$count_file"
  
  # Increment total counter
  awk -v mod="$module" '{if ($1 == mod) {$2++} print}' "$TOTAL_COUNT_FILE" > "${TOTAL_COUNT_FILE}.tmp"
  mv "${TOTAL_COUNT_FILE}.tmp" "$TOTAL_COUNT_FILE"
}

echo "Finding main thread blocking database operations..."
# Find database operations (potentially on main thread)
find "$PROJECT_PATH" -name "*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  grep -n "fetch" "$file" | head -n 20 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "$module" "Main Thread Blocking" "$file" "$line_number" "Database operation potentially on main thread" "High" "Move database operations to a background queue using DispatchQueue.global().async"
      increment_counter "$module" "High"
    fi
  done
done

echo "Finding large view controllers..."
# Find large view controllers
find "$PROJECT_PATH" -name "*ViewController*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "$module" "Large View Controller" "$file" "N/A" "View controller with $line_count lines" "High" "Break down large view controllers into smaller components"
    increment_counter "$module" "High"
  fi
done

echo "Finding large view models..."
# Find large view models
find "$PROJECT_PATH" -name "*ViewModel*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "$module" "Large View Model" "$file" "N/A" "View model with $line_count lines" "High" "Break down large view models into smaller components"
    increment_counter "$module" "High"
  fi
done

echo "Finding potential memory leaks in closures..."
# Find potential memory leaks in closures
find "$PROJECT_PATH" -name "*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  grep -n "self\." "$file" | grep "{" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak self" "$file"; then
        add_issue "$module" "Memory Leak" "$file" "$line_number" "Potential strong reference cycle in closure" "High" "Use [weak self] in closure capture list"
        increment_counter "$module" "High"
      fi
    fi
  done
done

echo "Finding delegate properties not marked as weak..."
# Find delegate properties not marked as weak
find "$PROJECT_PATH" -name "*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  grep -n "delegate" "$file" | grep "var" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak" <(echo "${BASH_REMATCH[2]}"); then
        add_issue "$module" "Memory Leak" "$file" "$line_number" "Delegate property not marked as weak" "High" "Mark delegate properties as weak to prevent retain cycles"
        increment_counter "$module" "High"
      fi
    fi
  done
done

echo "Finding force unwraps..."
# Find files with excessive force unwraps
find "$PROJECT_PATH" -name "*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  unwrap_count=$(grep -o "!" "$file" | wc -l)
  if [ "$unwrap_count" -gt 20 ]; then
    add_issue "$module" "Crash Risk" "$file" "N/A" "File contains $unwrap_count force unwraps" "Medium" "Replace force unwraps with optional binding or nil coalescing"
    increment_counter "$module" "Medium"
  fi
done

echo "Finding complex UI update logic..."
# Find complex UI update logic in main thread
find "$PROJECT_PATH" -name "*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  grep -n "DispatchQueue.main.async" "$file" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "$module" "UI Performance" "$file" "$line_number" "Complex UI update on main thread" "Medium" "Minimize work in main thread UI updates"
      increment_counter "$module" "Medium"
    fi
  done
done

echo "Finding timer usage without invalidation..."
# Find timer usage without invalidation
find "$PROJECT_PATH" -name "*.swift" -type f -not -path "*/Pods/*" -not -path "*/DB/*" | while read -r file; do
  module=$(get_module "$file")
  if grep -q "Timer" "$file" && ! grep -q "invalidate" "$file"; then
    add_issue "$module" "Resource Usage" "$file" "N/A" "Timer usage without invalidation" "Medium" "Always invalidate timers in deinit or when they are no longer needed"
    increment_counter "$module" "Medium"
  fi
done

# Generate module summary
for module in $MODULES; do
  high_count=$(grep "^$module " "$HIGH_COUNT_FILE" | awk '{print $2}')
  medium_count=$(grep "^$module " "$MEDIUM_COUNT_FILE" | awk '{print $2}')
  low_count=$(grep "^$module " "$LOW_COUNT_FILE" | awk '{print $2}')
  total_count=$(grep "^$module " "$TOTAL_COUNT_FILE" | awk '{print $2}')
  
  echo "\"$module\",\"$high_count\",\"$medium_count\",\"$low_count\",\"$total_count\"" >> "$SUMMARY_FILE"
done

# Calculate totals
TOTAL_HIGH=$(awk '{sum += $2} END {print sum}' "$HIGH_COUNT_FILE")
TOTAL_MEDIUM=$(awk '{sum += $2} END {print sum}' "$MEDIUM_COUNT_FILE")
TOTAL_LOW=$(awk '{sum += $2} END {print sum}' "$LOW_COUNT_FILE")
TOTAL_ALL=$(awk '{sum += $2} END {print sum}' "$TOTAL_COUNT_FILE")

echo "\"TOTAL\",\"$TOTAL_HIGH\",\"$TOTAL_MEDIUM\",\"$TOTAL_LOW\",\"$TOTAL_ALL\"" >> "$SUMMARY_FILE"

echo ""
echo "Performance Issues Summary by Module:"
echo "---------------------------------------------------------------"
echo "Module         | High  | Medium | Low   | Total"
echo "---------------------------------------------------------------"

# Print module summary
for module in $MODULES; do
  high_count=$(grep "^$module " "$HIGH_COUNT_FILE" | awk '{print $2}')
  medium_count=$(grep "^$module " "$MEDIUM_COUNT_FILE" | awk '{print $2}')
  low_count=$(grep "^$module " "$LOW_COUNT_FILE" | awk '{print $2}')
  total_count=$(grep "^$module " "$TOTAL_COUNT_FILE" | awk '{print $2}')
  
  printf "%-14s | %-5s | %-6s | %-5s | %-5s\n" \
    "$module" "$high_count" "$medium_count" "$low_count" "$total_count"
done

echo "---------------------------------------------------------------"
printf "%-14s | %-5s | %-6s | %-5s | %-5s\n" \
  "TOTAL" "$TOTAL_HIGH" "$TOTAL_MEDIUM" "$TOTAL_LOW" "$TOTAL_ALL"
echo ""

# Clean up temporary files
rm "$HIGH_COUNT_FILE" "$MEDIUM_COUNT_FILE" "$LOW_COUNT_FILE" "$TOTAL_COUNT_FILE"

echo "Analysis complete! Results saved to:"
echo "1. Detailed report: $CSV_FILE"
echo "2. Module summary: $SUMMARY_FILE"
echo ""
echo "You can open these CSV files in Excel for a detailed analysis of performance issues by module."
