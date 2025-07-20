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
REPORT_FILE="$METRICS_DIR/app_performance_$TIMESTAMP.txt"

echo "APP PERFORMANCE ANALYSIS - $TIMESTAMP" > "$REPORT_FILE"
echo "===============================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Function to find main thread blocking operations
find_main_thread_blocking() {
  echo "Finding main thread blocking operations..."
  echo "MAIN THREAD BLOCKING OPERATIONS" >> "$REPORT_FILE"
  echo "----------------------------" >> "$REPORT_FILE"
  
  # Create temporary files for results
  TEMP_FILE=$(mktemp)
  
  echo "1. Synchronous network calls on main thread:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "URLSession.shared.dataTask" | while read -r file; do
    grep -n "URLSession.shared.dataTask" "$file" | grep -v "DispatchQueue.global" | grep -v "background" >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "2. Database operations on main thread:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "save\(\)|fetch|query|execute" | while read -r file; do
    grep -n -E "save\(\)|fetch|query|execute" "$file" | grep -v "DispatchQueue.global" | grep -v "background" | head -n 20 >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "3. Heavy operations in viewDidLoad/viewWillAppear:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "viewDidLoad|viewWillAppear" | while read -r file; do
    awk '/func viewDidLoad|func viewWillAppear/,/^    }/ { print }' "$file" | grep -E "for |while |repeat |switch " | head -n 20 >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find slow table/collection view implementations
find_slow_list_views() {
  echo "Finding slow table/collection view implementations..."
  echo "SLOW LIST VIEW IMPLEMENTATIONS" >> "$REPORT_FILE"
  echo "--------------------------" >> "$REPORT_FILE"
  
  # Create temporary file for results
  TEMP_FILE=$(mktemp)
  
  echo "1. Missing cell reuse:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "UITableViewCell|UICollectionViewCell" | while read -r file; do
    if grep -q "dequeueReusableCell" "$file"; then
      continue
    elif grep -q "UITableViewCell" "$file" || grep -q "UICollectionViewCell" "$file"; then
      echo "$file" >> "$TEMP_FILE"
    fi
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "2. Complex cellForRowAt methods:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "cellForRowAt\|cellForItemAt" | while read -r file; do
    awk '/cellForRowAt|cellForItemAt/,/^    }/ { print }' "$file" | grep -v "^$" | wc -l | while read -r lines; do
      if [ "$lines" -gt 30 ]; then
        echo "$file: $lines lines" >> "$TEMP_FILE"
      fi
    done
  done
  
  if [ -s "$TEMP_FILE" ]; then
    sort -t':' -k2 -nr "$TEMP_FILE" | head -n 10 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find image loading issues
find_image_loading_issues() {
  echo "Finding image loading issues..."
  echo "IMAGE LOADING ISSUES" >> "$REPORT_FILE"
  echo "-------------------" >> "$REPORT_FILE"
  
  # Create temporary file for results
  TEMP_FILE=$(mktemp)
  
  echo "1. Large image loading without resizing:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "UIImage\(named:|UIImage\(contentsOfFile:" | while read -r file; do
    grep -n -E "UIImage\(named:|UIImage\(contentsOfFile:" "$file" | grep -v "resize" >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "2. Missing image caching:" >> "$REPORT_FILE"
  # Look for image loading without SDWebImage or similar caching
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "UIImage\(data:|UIImage\(contentsOfFile:" | while read -r file; do
    if ! grep -q -E "SDWebImage|Kingfisher|AlamofireImage|Nuke" "$file"; then
      echo "$file" >> "$TEMP_FILE"
    fi
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find navigation issues
find_navigation_issues() {
  echo "Finding navigation performance issues..."
  echo "NAVIGATION PERFORMANCE ISSUES" >> "$REPORT_FILE"
  echo "---------------------------" >> "$REPORT_FILE"
  
  # Create temporary file for results
  TEMP_FILE=$(mktemp)
  
  echo "1. Heavy view controller initialization:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "init\(|viewDidLoad" | while read -r file; do
    if grep -q "UIViewController" "$file"; then
      INIT_LINES=$(awk '/init\(|viewDidLoad/,/^    }/ { print }' "$file" | grep -v "^$" | wc -l)
      if [ "$INIT_LINES" -gt 50 ]; then
        echo "$file: $INIT_LINES lines in init/viewDidLoad" >> "$TEMP_FILE"
      fi
    fi
  done
  
  if [ -s "$TEMP_FILE" ]; then
    sort -t':' -k2 -nr "$TEMP_FILE" | head -n 10 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "2. Excessive view controllers in navigation stack:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "navigationController?.pushViewController" | while read -r file; do
    PUSH_COUNT=$(grep -c "navigationController?.pushViewController" "$file")
    if [ "$PUSH_COUNT" -gt 5 ]; then
      echo "$file: $PUSH_COUNT push operations" >> "$TEMP_FILE"
    fi
  done
  
  if [ -s "$TEMP_FILE" ]; then
    sort -t':' -k2 -nr "$TEMP_FILE" | head -n 10 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find memory leaks
find_memory_leaks() {
  echo "Finding potential memory leaks..."
  echo "POTENTIAL MEMORY LEAKS" >> "$REPORT_FILE"
  echo "--------------------" >> "$REPORT_FILE"
  
  # Create temporary file for results
  TEMP_FILE=$(mktemp)
  
  echo "1. Strong reference cycles in closures:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "\{\s*\[self\]|\{\s*\(\)" | while read -r file; do
    grep -n -E "\{\s*\[self\]|\{\s*\(\)" "$file" | grep -v "weak" | grep -v "unowned" >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "2. Delegate properties not marked weak:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "delegate" | while read -r file; do
    grep -n "delegate" "$file" | grep -v "weak" | grep -v "protocol" | grep -E "var|let" >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" | head -n 20 >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  
  # Clean up
  rm "$TEMP_FILE"
}

# Function to find excessive resource usage
find_excessive_resource_usage() {
  echo "Finding excessive resource usage..."
  echo "EXCESSIVE RESOURCE USAGE" >> "$REPORT_FILE"
  echo "----------------------" >> "$REPORT_FILE"
  
  # Create temporary file for results
  TEMP_FILE=$(mktemp)
  
  echo "1. Large static arrays/dictionaries:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l -E "let.*\[|var.*\[" | while read -r file; do
    grep -n -E "let.*\[|var.*\[" "$file" | grep -E "\{|\[" | grep -v "=" | head -n 20 >> "$TEMP_FILE"
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  > "$TEMP_FILE"
  
  echo "2. Timer usage without invalidation:" >> "$REPORT_FILE"
  find "$PROJECT_PATH" -name "*.swift" -print0 | xargs -0 grep -l "Timer" | while read -r file; do
    if grep -q "Timer" "$file" && ! grep -q "invalidate" "$file"; then
      echo "$file" >> "$TEMP_FILE"
    fi
  done
  
  if [ -s "$TEMP_FILE" ]; then
    cat "$TEMP_FILE" >> "$REPORT_FILE"
  else
    echo "None found" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
  
  # Clean up
  rm "$TEMP_FILE"
}

# Run all analysis functions
find_main_thread_blocking
find_slow_list_views
find_image_loading_issues
find_navigation_issues
find_memory_leaks
find_excessive_resource_usage

echo "Analysis complete! Results saved to $REPORT_FILE"
echo "You can review this file for potential causes of application hangs and slow navigation."
