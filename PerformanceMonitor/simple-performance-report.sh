#!/bin/bash

# Set default project path
DEFAULT_PROJECT_PATH="Your Project Path"

# Allow overriding project path via command line argument
PROJECT_PATH="${1:-$DEFAULT_PROJECT_PATH}"

echo "Analyzing application performance issues for project at $PROJECT_PATH..."

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
CSV_FILE="$METRICS_DIR/performance_issues_$TIMESTAMP.csv"

# Create CSV header
echo "Issue Type,File Path,Line Number,Issue Description,Severity,Recommendation,Impact,Module,Feature" > "$CSV_FILE"

# Function to safely add an issue to the CSV file
add_issue() {
  local issue_type="$1"
  local file_path="$2"
  local line_number="$3"
  local description="$4"
  local severity="$5"
  local recommendation="$6"
  
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
  
  # Extract module and feature from file path
  local module="Other"
  local feature="General"
  local path_parts=($(echo "$rel_path" | tr '/' ' '))
  
  if [ ${#path_parts[@]} -ge 1 ] && [ -n "${path_parts[0]}" ]; then
    module="${path_parts[0]}"
    
    # Try to extract feature from second directory or filename
    if [ ${#path_parts[@]} -ge 2 ] && [ -n "${path_parts[1]}" ]; then
      feature="${path_parts[1]}"
      # If feature is a swift file, remove the extension
      feature=$(echo "$feature" | sed 's/\.swift$//')
    fi
  fi
  
  # Escape quotes and commas
  description=$(echo "$description" | sed 's/"/""/g')
  recommendation=$(echo "$recommendation" | sed 's/"/""/g')
  impact=$(echo "$impact" | sed 's/"/""/g')
  
  echo "\"$issue_type\",\"$rel_path\",\"$line_number\",\"$description\",\"$severity\",\"$recommendation\",\"$impact\",\"$module\",\"$feature\"" >> "$CSV_FILE"
}

echo "Finding main thread blocking database operations..."
# Find database operations (potentially on main thread)
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  grep -n "fetch" "$file" | head -n 20 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "Main Thread Blocking" "$file" "$line_number" "Database operation potentially on main thread" "High" "Move database operations to a background queue using DispatchQueue.global().async"
    fi
  done
done

echo "Finding large view controllers..."
# Find large view controllers
find "$PROJECT_PATH" -name "*ViewController*.swift" -type f | while read -r file; do
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "Large View Controller" "$file" "N/A" "View controller with $line_count lines" "High" "Break down large view controllers into smaller components"
  fi
done

echo "Finding large view models..."
# Find large view models
find "$PROJECT_PATH" -name "*ViewModel*.swift" -type f | while read -r file; do
  line_count=$(wc -l < "$file")
  if [ "$line_count" -gt 300 ]; then
    add_issue "Large View Model" "$file" "N/A" "View model with $line_count lines" "High" "Break down large view models into smaller components"
  fi
done

echo "Finding potential memory leaks in closures..."
# Find potential memory leaks in closures
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  grep -n "self\." "$file" | grep "{" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak self" "$file"; then
        add_issue "Memory Leak" "$file" "$line_number" "Potential strong reference cycle in closure" "High" "Use [weak self] in closure capture list"
      fi
    fi
  done
done

echo "Finding delegate properties not marked as weak..."
# Find delegate properties not marked as weak
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  grep -n "delegate" "$file" | grep "var" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      if ! grep -q "weak" <(echo "${BASH_REMATCH[2]}"); then
        add_issue "Memory Leak" "$file" "$line_number" "Delegate property not marked as weak" "High" "Mark delegate properties as weak to prevent retain cycles"
      fi
    fi
  done
done

echo "Finding force unwraps..."
# Find files with excessive force unwraps
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  unwrap_count=$(grep -o "!" "$file" | wc -l)
  if [ "$unwrap_count" -gt 20 ]; then
    add_issue "Crash Risk" "$file" "N/A" "File contains $unwrap_count force unwraps" "Medium" "Replace force unwraps with optional binding or nil coalescing"
  fi
done

echo "Finding complex UI update logic..."
# Find complex UI update logic in main thread
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  grep -n "DispatchQueue.main.async" "$file" | head -n 10 | while read -r line; do
    if [[ $line =~ ^([0-9]+):(.*) ]]; then
      line_number="${BASH_REMATCH[1]}"
      add_issue "UI Performance" "$file" "$line_number" "Complex UI update on main thread" "Medium" "Minimize work in main thread UI updates"
    fi
  done
done

echo "Finding timer usage without invalidation..."
# Find timer usage without invalidation
find "$PROJECT_PATH" -name "*.swift" -type f | while read -r file; do
  if grep -q "Timer" "$file" && ! grep -q "invalidate" "$file"; then
    add_issue "Resource Usage" "$file" "N/A" "Timer usage without invalidation" "Medium" "Always invalidate timers in deinit or when they are no longer needed"
  fi
done

# Count issues by severity
HIGH_COUNT=$(grep -c "\"High\"" "$CSV_FILE")
MEDIUM_COUNT=$(grep -c "\"Medium\"" "$CSV_FILE")
LOW_COUNT=$(grep -c "\"Low\"" "$CSV_FILE")
TOTAL_COUNT=$((HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))

# No need to calculate code quality score or tech debt anymore

# Count issues by module
echo "Analyzing issues by module..."
MODULE_COUNTS=$(cut -d'"' -f18 "$CSV_FILE" | grep -v "^Module$" | sort | uniq -c | sort -nr)

echo ""
echo "Performance Issues Summary:"
echo "-------------------------"
echo "High Severity: $HIGH_COUNT issues"
echo "Medium Severity: $MEDIUM_COUNT issues"
echo "Low Severity: $LOW_COUNT issues"
echo "Total: $TOTAL_COUNT issues"
echo ""
echo "Code Quality Score: $CODE_QUALITY/100"
echo "Estimated Technical Debt: $TECH_DEBT hours"
echo ""
echo "Issues by Module:"
echo "$MODULE_COUNTS"
echo ""
echo "Analysis complete! Results saved to $CSV_FILE"
echo "You can open this CSV file in Excel for a detailed report of performance issues."
