#!/bin/bash

# Swift Performance Analyzer Web Interface Setup Script

echo "Setting up Swift Performance Analyzer Web Interface..."

# Create metrics_data directory if it doesn't exist
mkdir -p metrics_data

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install Node.js first."
    echo "You can download it from https://nodejs.org/"
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "npm is not installed. Please install npm first."
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
npm install

# Create a simple launcher script
cat > launch.sh << 'EOF'
#!/bin/bash

# Start the server
echo "Starting Swift Performance Analyzer Web Interface..."
echo "Once the server is running, open your browser and navigate to:"
echo "http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop the server when done."
node server.js
EOF

# Make the launcher script executable
chmod +x launch.sh

echo "Setup complete!"
echo "To start the Swift Performance Analyzer Web Interface, run:"
echo "./launch.sh"
