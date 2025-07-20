#!/bin/bash

# Set project path
PROJECT_PATH="/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen"

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
echo "Issue Type,File Path,Line Number,Issue Description,Severity,Recommendation" > "$CSV_FILE"

# Function to add an issue to the CSV file
# Parameters: issue_type, file_path, line_number, description, severity, recommendation
add_issue() {
  local issue_type="$1"
  local file_path="$2"
  local line_number="$3"
  local description="$4"
  local severity="$5"
  local recommendation="$6"
  
  # Escape any commas in the fields
  description=$(echo "$description" | sed 's/,/\\,/g')
  recommendation=$(echo "$recommendation" | sed 's/,/\\,/g')
  
  # Get relative path for better readability
  local rel_path=${file_path#$PROJECT_PATH/}
  
  echo "\"$issue_type\",\"$rel_path\",\"$line_number\",\"$description\",\"$severity\",\"$recommendation\"" >> "$CSV_FILE"
}

# Function to find main thread blocking operations
find_main_thread_blocking() {
  echo "Finding main thread blocking operations..."
  
  # Find synchronous network calls on main thread
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ $line =~ ^([0-9]+):(.*URLSession.shared.dataTask.*) ]]; then
        line_number="${BASH_REMATCH[1]}"
        code_snippet="${BASH_REMATCH[2]}"
        if ! grep -q "DispatchQueue.global" <(echo "$code_snippet") && ! grep -q "background" <(echo "$code_snippet"); then
          add_issue "Main Thread Blocking" "$file" "$line_number" "Synchronous network call on main thread" "High" "Move network operations to a background queue using DispatchQueue.global().async"
        fi
      fi
    done < <(grep -n "URLSession.shared.dataTask" "$file")
  done
  
  # Find database operations on main thread
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ $line =~ ^([0-9]+):(.*) ]]; then
        line_number="${BASH_REMATCH[1]}"
        code_snippet="${BASH_REMATCH[2]}"
        if ! grep -q "DispatchQueue.global" <(echo "$code_snippet") && ! grep -q "background" <(echo "$code_snippet"); then
          add_issue "Main Thread Blocking" "$file" "$line_number" "Database operation potentially on main thread" "High" "Move database operations to a background queue using DispatchQueue.global().async"
        fi
      fi
    done < <(grep -n -E "save\(\)|fetch|query|execute" "$file")
  done
  
  # Find heavy operations in viewDidLoad/viewWillAppear
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    in_lifecycle_method=false
    line_number=0
    method_start_line=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
      ((line_number++))
      
      if [[ "$line" =~ func\ (viewDidLoad|viewWillAppear) ]]; then
        in_lifecycle_method=true
        method_start_line=$line_number
        method_name=$(echo "$line" | grep -o "func \(viewDidLoad\|viewWillAppear\)")
      elif [[ "$in_lifecycle_method" == true && "$line" =~ ^[[:space:]]*} ]]; then
        in_lifecycle_method=false
      elif [[ "$in_lifecycle_method" == true ]]; then
        if [[ "$line" =~ for\ |while\ |repeat\ |switch\  ]]; then
          add_issue "Main Thread Blocking" "$file" "$line_number" "Heavy operation in $method_name" "Medium" "Move heavy operations out of view lifecycle methods or use background processing"
        fi
      fi
    done < "$file"
  done
}

# Function to find slow table/collection view implementations
find_slow_list_views() {
  echo "Finding slow table/collection view implementations..."
  
  # Find missing cell reuse
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    if grep -q "UITableViewCell" "$file" || grep -q "UICollectionViewCell" "$file"; then
      if ! grep -q "dequeueReusableCell" "$file"; then
        add_issue "Slow List View" "$file" "N/A" "Missing cell reuse" "High" "Use dequeueReusableCell pattern for better scrolling performance"
      fi
    fi
  done
  
  # Find complex cellForRowAt methods
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    in_cell_method=false
    line_number=0
    method_start_line=0
    line_count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
      ((line_number++))
      
      if [[ "$line" =~ (cellForRowAt|cellForItemAt) ]]; then
        in_cell_method=true
        method_start_line=$line_number
        line_count=0
      elif [[ "$in_cell_method" == true && "$line" =~ ^[[:space:]]*} ]]; then
        in_cell_method=false
        if [[ $line_count -gt 30 ]]; then
          add_issue "Slow List View" "$file" "$method_start_line" "Complex cell configuration method ($line_count lines)" "Medium" "Simplify cell configuration logic or move complex operations to a background queue"
        fi
      elif [[ "$in_cell_method" == true ]]; then
        ((line_count++))
      fi
    done < "$file"
  done
}

# Function to find image loading issues
find_image_loading_issues() {
  echo "Finding image loading issues..."
  
  # Find large image loading without resizing
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ $line =~ ^([0-9]+):(.*) ]]; then
        line_number="${BASH_REMATCH[1]}"
        code_snippet="${BASH_REMATCH[2]}"
        if ! grep -q "resize" <(echo "$code_snippet"); then
          add_issue "Image Loading" "$file" "$line_number" "Loading image without resizing" "Medium" "Resize images before displaying them to reduce memory usage"
        fi
      fi
    done < <(grep -n -E "UIImage\(named:|UIImage\(contentsOfFile:" "$file")
  done
  
  # Find missing image caching
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    if grep -q -E "UIImage\(data:|UIImage\(contentsOfFile:" "$file"; then
      if ! grep -q -E "SDWebImage|Kingfisher|AlamofireImage|Nuke" "$file"; then
        add_issue "Image Loading" "$file" "N/A" "Missing image caching" "Medium" "Use an image caching library like SDWebImage or Kingfisher"
      fi
    fi
  done
}

# Function to find navigation issues
find_navigation_issues() {
  echo "Finding navigation performance issues..."
  
  # Find heavy view controller initialization
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    if grep -q "UIViewController" "$file"; then
      in_init_method=false
      line_number=0
      method_start_line=0
      line_count=0
      
      while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        
        if [[ "$line" =~ (init\(|viewDidLoad) ]]; then
          in_init_method=true
          method_start_line=$line_number
          line_count=0
          method_name=$(echo "$line" | grep -o "init\(.*\)\|viewDidLoad")
        elif [[ "$in_init_method" == true && "$line" =~ ^[[:space:]]*} ]]; then
          in_init_method=false
          if [[ $line_count -gt 50 ]]; then
            add_issue "Navigation" "$file" "$method_start_line" "Heavy initialization in $method_name ($line_count lines)" "High" "Break down initialization into smaller methods and defer non-essential setup"
          fi
        elif [[ "$in_init_method" == true ]]; then
          ((line_count++))
        fi
      done < "$file"
    fi
  done
  
  # Find excessive view controllers in navigation stack
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    push_count=$(grep -c "navigationController?.pushViewController" "$file")
    if [[ $push_count -gt 5 ]]; then
      add_issue "Navigation" "$file" "N/A" "Excessive navigation pushes ($push_count)" "Medium" "Consider flattening navigation hierarchy or using a coordinator pattern"
    fi
  done
}

# Function to find memory leaks
find_memory_leaks() {
  echo "Finding potential memory leaks..."
  
  # Find strong reference cycles in closures
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ $line =~ ^([0-9]+):(.*) ]]; then
        line_number="${BASH_REMATCH[1]}"
        code_snippet="${BASH_REMATCH[2]}"
        if ! grep -q "weak" <(echo "$code_snippet") && ! grep -q "unowned" <(echo "$code_snippet"); then
          add_issue "Memory Leak" "$file" "$line_number" "Potential strong reference cycle in closure" "High" "Use [weak self] or [unowned self] in closure capture list"
        fi
      fi
    done < <(grep -n -E "\{\s*\[self\]|\{\s*\(\)" "$file")
  done
  
  # Find delegate properties not marked weak
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ $line =~ ^([0-9]+):(.*delegate.*) ]]; then
        line_number="${BASH_REMATCH[1]}"
        code_snippet="${BASH_REMATCH[2]}"
        if [[ "$code_snippet" =~ var|let ]] && ! grep -q "weak" <(echo "$code_snippet") && ! grep -q "protocol" <(echo "$code_snippet"); then
          add_issue "Memory Leak" "$file" "$line_number" "Delegate property not marked as weak" "High" "Mark delegate properties as weak to prevent retain cycles"
        fi
      fi
    done < <(grep -n "delegate" "$file")
  done
}

# Function to find excessive resource usage
find_excessive_resource_usage() {
  echo "Finding excessive resource usage..."
  
  # Find timer usage without invalidation
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    if grep -q "Timer" "$file" && ! grep -q "invalidate" "$file"; then
      add_issue "Resource Usage" "$file" "N/A" "Timer usage without invalidation" "Medium" "Always invalidate timers in deinit or when they are no longer needed"
    fi
  done
  
  # Find large static arrays/dictionaries
  find "$PROJECT_PATH" -name "*.swift" -print0 | while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ $line =~ ^([0-9]+):(.*(let|var).*\[) ]]; then
        line_number="${BASH_REMATCH[1]}"
        code_snippet="${BASH_REMATCH[2]}"
        if [[ ${#code_snippet} -gt 200 ]]; then
          add_issue "Resource Usage" "$file" "$line_number" "Large static collection" "Low" "Consider lazy loading or pagination for large data collections"
        fi
      fi
    done < <(grep -n -E "(let|var).*\[" "$file")
  done
}

# Run all analysis functions
find_main_thread_blocking
find_slow_list_views
find_image_loading_issues
find_navigation_issues
find_memory_leaks
find_excessive_resource_usage

# Convert CSV to Excel (XLSX) format
echo "Analysis complete! Results saved to $CSV_FILE"
echo "You can open this CSV file in Excel for a detailed report of performance issues."

# Count issues by severity
HIGH_COUNT=$(grep -c "\"High\"" "$CSV_FILE")
MEDIUM_COUNT=$(grep -c "\"Medium\"" "$CSV_FILE")
LOW_COUNT=$(grep -c "\"Low\"" "$CSV_FILE")
TOTAL_COUNT=$((HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))

echo ""
echo "Performance Issues Summary:"
echo "-------------------------"
echo "High Severity: $HIGH_COUNT issues"
echo "Medium Severity: $MEDIUM_COUNT issues"
echo "Low Severity: $LOW_COUNT issues"
echo "Total: $TOTAL_COUNT issues"
