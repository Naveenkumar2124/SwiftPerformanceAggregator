#!/bin/bash

# Test script to verify path access
TEST_PATH="${1}"

echo "Testing path access for: $TEST_PATH"

if [ -d "$TEST_PATH" ]; then
  echo "SUCCESS: Directory exists at $TEST_PATH"
  echo "Contents:"
  ls -la "$TEST_PATH" 2>&1 || echo "ERROR: Cannot list directory contents"
else
  echo "ERROR: Directory does not exist at $TEST_PATH"
fi

echo "Current working directory: $(pwd)"
echo "Script location: $0"
echo "Test complete."
