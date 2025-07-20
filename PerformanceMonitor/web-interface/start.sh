#!/bin/bash

# Start the Swift Performance Analyzer Web Interface

echo "Starting Swift Performance Analyzer Web Interface..."
echo "This interface uses performance analysis scripts for reporting"

# Create metrics_data directory if it doesn't exist
mkdir -p metrics_data

# Start the server
node server.js

# The server will run until you press Ctrl+C
