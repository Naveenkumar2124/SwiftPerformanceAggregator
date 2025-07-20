const express = require('express');
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = 3001;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname)));

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// API endpoint to analyze project using simple-performance-report.sh
app.post('/api/analyze', (req, res) => {
    const { projectPath } = req.body;
    
    if (!projectPath) {
        return res.status(400).json({ error: 'Project path is required' });
    }
    
    // Check if project path exists
    if (!fs.existsSync(projectPath)) {
        return res.status(400).json({ error: 'Project path does not exist' });
    }
    
    // Path to the performance report script
    const scriptPath = path.join(__dirname, '..', 'simple-performance-report.sh');
    const moduleScriptPath = path.join(__dirname, '..', 'simple-module-report.sh');
    
    // Use module report script as fallback if performance report script doesn't exist
    const actualScriptPath = fs.existsSync(scriptPath) ? scriptPath : moduleScriptPath;
    
    // Check if any script exists
    if (!fs.existsSync(actualScriptPath)) {
        return res.status(500).json({ error: 'Analysis script not found. Neither simple-performance-report.sh nor simple-module-report.sh was found.' });
    }
    
    console.log(`Analyzing project at ${projectPath}...`);
    
    // Execute the script with project path as command-line argument
    // Use spawn with shell option for better handling of paths with spaces and special characters
    const { spawn } = require('child_process');
    console.log(`Executing script: ${actualScriptPath} with path: ${projectPath}`);
    const child = spawn('bash', [actualScriptPath, projectPath], {
        shell: true,
        env: { ...process.env, PATH: process.env.PATH }
    });
    
    let stdoutData = '';
    let stderrData = '';
    
    child.stdout.on('data', (data) => {
        const dataStr = data.toString();
        stdoutData += dataStr;
        console.log(`stdout: ${dataStr}`);
    });
    
    child.stderr.on('data', (data) => {
        const dataStr = data.toString();
        stderrData += dataStr;
        console.error(`stderr: ${dataStr}`);
    });
    
    child.on('close', (code) => {
        console.log(`Child process exited with code ${code}`);
        console.log(`Full stdout: ${stdoutData}`);
        console.log(`Full stderr: ${stderrData}`);
        
        if (code !== 0) {
            console.error(`Error: Process exited with code ${code}`);
            return res.status(500).json({ error: stderrData || 'Error analyzing project' });
        }
        
        try {
            console.log(`Analysis complete.`);
            // Find the CSV file path in the output - handle both script output formats
            const match = stdoutData.match(/Results saved to[:\s]+(.+\.csv)/) || 
                        stdoutData.match(/Detailed report: (.+\.csv)/) || 
                        stdoutData.match(/Analysis complete! Results saved to (.+\.csv)/);
            if (!match) {
                console.log('Output from script:', stdoutData);
                // Try to find any CSV file in the metrics_data directory
                const metricsDir = path.join(__dirname, '..', 'metrics_data');
                if (fs.existsSync(metricsDir)) {
                    const files = fs.readdirSync(metricsDir);
                    const csvFiles = files.filter(file => file.endsWith('.csv'));
                    if (csvFiles.length > 0) {
                        // Sort by modification time (newest first)
                        csvFiles.sort((a, b) => {
                            return fs.statSync(path.join(metricsDir, b)).mtime.getTime() - 
                                   fs.statSync(path.join(metricsDir, a)).mtime.getTime();
                        });
                        const csvFile = path.join(metricsDir, csvFiles[0]);
                        console.log(`Using most recent CSV file: ${csvFile}`);
                        const csvData = fs.readFileSync(csvFile, 'utf8');
                        const issues = parseCSV(csvData);
                        return res.json({
                            success: true,
                            projectPath,
                            issues,
                            timestamp: new Date().toISOString()
                        });
                    }
                }
                throw new Error('Could not find CSV file path in output');
            }
            
            const csvFile = match[1].trim();
            console.log(`Found CSV file: ${csvFile}`);
            
            // Check if CSV file exists
            if (!fs.existsSync(csvFile)) {
                throw new Error(`CSV file not found: ${csvFile}`);
            }
            
            // Read CSV file
            console.log(`Reading CSV file from: ${csvFile}`);
            if (!fs.existsSync(csvFile)) {
                console.error(`CSV file does not exist at path: ${csvFile}`);
                throw new Error(`CSV file not found: ${csvFile}`);
            }
            
            const csvData = fs.readFileSync(csvFile, 'utf8');
            console.log(`CSV file size: ${csvData.length} bytes`);
            
            // Parse CSV data
            const issues = parseCSV(csvData);
            
            return res.json({
                success: true,
                projectPath,
                issues,
                timestamp: new Date().toISOString()
            });
        } catch (err) {
            console.error(`Error parsing output: ${err.message}`);
            return res.status(500).json({ error: 'Error parsing analysis results' });
        }
    });
});

// Helper function to parse CSV
function parseCSV(csvData) {
    console.log('Parsing CSV data...');
    try {
        if (!csvData || !csvData.trim()) {
            console.error('Empty CSV data received');
            return [];
        }
        
        const lines = csvData.split('\n');
        console.log(`CSV has ${lines.length} lines`);
        
        if (lines.length === 0) {
            console.error('No lines found in CSV');
            return [];
        }
        
        // Log the first line to debug header issues
        console.log(`CSV header line: ${lines[0]}`);
        const headers = lines[0].split(',').map(header => header.replace(/"/g, ''));
        console.log(`Parsed headers: ${headers.join(', ')}`);
    
    const issues = [];
    for (let i = 1; i < lines.length; i++) {
        if (!lines[i].trim()) continue;
        
        // Handle commas within quoted fields
        const values = [];
        let inQuotes = false;
        let currentValue = '';
        
        for (let char of lines[i]) {
            if (char === '"') {
                inQuotes = !inQuotes;
            } else if (char === ',' && !inQuotes) {
                values.push(currentValue);
                currentValue = '';
            } else {
                currentValue += char;
            }
        }
        values.push(currentValue);
        
        const issue = {};
        headers.forEach((header, index) => {
            issue[header] = values[index] || '';
        });
        
        // Extract module and feature from file path if not provided
        if (!issue.Module && !issue.Feature) {
            const filePath = issue['File Path'];
            if (filePath) {
                const parts = filePath.split('/').filter(Boolean);
                if (parts.length >= 2) {
                    issue.Module = parts[0];
                    issue.Feature = parts[1];
                }
            }
        }
        
        issues.push(issue);
    }
    
    console.log(`Successfully parsed ${issues.length} issues from CSV`);
    return issues;
    } catch (err) {
        console.error(`Error in parseCSV: ${err.message}`);
        console.error(err.stack);
        return [];
    }
}

// Start server
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
    console.log(`Open your browser and navigate to http://localhost:${PORT} to use the Swift Performance Analyzer`);
    console.log(`Using simple-performance-report.sh for analysis`);
});
