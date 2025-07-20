document.addEventListener('DOMContentLoaded', function() {
    // Global variables
    let analysisResults = null;
    let charts = {};
    
    // Initialize DataTables
    const initDataTables = () => {
        $('#topFilesTable').DataTable({
            pageLength: 10,
            order: [[1, 'desc']]
        });
        
        $('#moduleTable').DataTable({
            pageLength: 10,
            order: [[1, 'desc']]
        });
        
        $('#featureTable').DataTable({
            pageLength: 10,
            order: [[2, 'desc']]
        });
        
        // Initialize issues table with custom filtering
        $('#issuesTable').DataTable({
            pageLength: 25,
            order: [[6, 'desc'], [0, 'asc'], [1, 'asc']],
            initComplete: function() {
                // Apply custom filtering when DataTable is initialized
                setupCustomFilters();
            }
        });
    };
    
    // Setup custom filters for DataTable
    function setupCustomFilters() {
        const table = $('#issuesTable').DataTable();
        
        // Issue Type filter
        $('#issueTypeFilter').on('change', function() {
            const selectedType = $(this).val();
            table.column(4).search(selectedType ? '^' + $.fn.dataTable.util.escapeRegex(selectedType) + '$' : '', true, false).draw();
        });
        
        // Module filter
        $('#moduleFilter').on('change', function() {
            const selectedModule = $(this).val();
            table.column(0).search(selectedModule ? '^' + $.fn.dataTable.util.escapeRegex(selectedModule) + '$' : '', true, false).draw();
        });
        
        // Search input
        $('#issueSearch').on('keyup', function() {
            table.search(this.value).draw();
        });
    }
    
    // Set default project path
    document.getElementById('projectPath').value = '/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen';
    
    // Handle browse button click - just set a default path
    document.getElementById('browseButton').addEventListener('click', function() {
        document.getElementById('projectPath').value = '/Users/naveen/Documents/Pepsico/Code/Repo/Communication/pep-swift-shngen';
    });
    
    // Handle form submission
    document.getElementById('analyzeForm').addEventListener('submit', function(e) {
        e.preventDefault();
        
        const projectPath = document.getElementById('projectPath').value;
        if (!projectPath) {
            alert('Please enter a project path');
            return;
        }
        
        // Show loading modal
        const loadingModal = new bootstrap.Modal(document.getElementById('loadingModal'));
        loadingModal.show();
        
        // Analyze project using simple-performance-report.sh
        analyzeProject(projectPath, loadingModal);
    });
    
    // Analyze project using simple-performance-report.sh
    function analyzeProject(projectPath, loadingModal) {
        const progressBar = document.querySelector('.progress-bar');
        const loadingStatus = document.getElementById('loadingStatus');
        
        // Set initial progress
        progressBar.style.width = '10%';
        loadingStatus.textContent = 'Starting analysis...';
        
        // Prepare request data
        const requestData = {
            projectPath: projectPath
        };
        
        // Send request to analyze endpoint
        fetch('/api/analyze', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(requestData)
        })
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            // Analysis complete
            loadingModal.hide();
            
            // Store results
            analysisResults = data;
            
            // Display results
            displayResults(analysisResults);
        })
        .catch(error => {
            console.error('Error analyzing project:', error);
            loadingModal.hide();
            alert('Error analyzing project: ' + error.message);
        });
        
        // Simulate progress updates (since we don't have real-time progress)
        let progress = 10;
        const progressInterval = setInterval(() => {
            if (progress < 90) {
                progress += 5;
                progressBar.style.width = `${progress}%`;
                
                // Update status message based on progress
                if (progress < 30) {
                    loadingStatus.textContent = 'Finding main thread blocking operations...';
                } else if (progress < 50) {
                    loadingStatus.textContent = 'Finding large view controllers and view models...';
                } else if (progress < 70) {
                    loadingStatus.textContent = 'Finding potential memory leaks...';
                } else {
                    loadingStatus.textContent = 'Generating report...';
                }
            } else {
                clearInterval(progressInterval);
            }
        }, 1000);
    }
    
    // Display analysis results
    function displayResults(results) {
        // Show results section
        document.getElementById('resultsSection').classList.remove('d-none');
        
        // Display summary charts
        displaySummaryCharts(results);
        
        // Display top files table
        displayTopFiles(results);
        
        // Display module breakdown
        displayModuleBreakdown(results);
        
        // Display feature breakdown
        displayFeatureBreakdown(results);
        
        // Display all issues
        displayAllIssues(results);
        
        // Initialize DataTables
        initDataTables();
        
        // Scroll to results
        document.getElementById('resultsSection').scrollIntoView({ behavior: 'smooth' });
    }
    
    // Display summary charts
    function displaySummaryCharts(results) {
        // Count issues by severity
        const severityCounts = {
            'High': 0,
            'Medium': 0,
            'Low': 0
        };
        
        // Count issues by type
        const typeCounts = {};
        
        results.issues.forEach(issue => {
            // Count by severity
            severityCounts[issue.Severity]++;
            
            // Count by type
            if (!typeCounts[issue['Issue Type']]) {
                typeCounts[issue['Issue Type']] = 0;
            }
            typeCounts[issue['Issue Type']]++;
        });
        
        // Create severity chart
        const severityCtx = document.getElementById('severityChart').getContext('2d');
        charts.severityChart = new Chart(severityCtx, {
            type: 'pie',
            data: {
                labels: Object.keys(severityCounts),
                datasets: [{
                    data: Object.values(severityCounts),
                    backgroundColor: ['#dc3545', '#fd7e14', '#0d6efd'],
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'right'
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                const label = context.label || '';
                                const value = context.raw || 0;
                                const total = context.dataset.data.reduce((a, b) => a + b, 0);
                                const percentage = Math.round((value / total) * 100);
                                return `${label}: ${value} (${percentage}%)`;
                            }
                        }
                    }
                }
            }
        });
        
        // Create issue type chart
        const typeCtx = document.getElementById('issueTypeChart').getContext('2d');
        charts.issueTypeChart = new Chart(typeCtx, {
            type: 'bar',
            data: {
                labels: Object.keys(typeCounts),
                datasets: [{
                    label: 'Issues',
                    data: Object.values(typeCounts),
                    backgroundColor: '#0d6efd',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                indexAxis: 'y',
                plugins: {
                    legend: {
                        display: false
                    }
                },
                scales: {
                    x: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Number of Issues'
                        }
                    }
                }
            }
        });
    }
    
    // Display top files table
    function displayTopFiles(results) {
        // Count issues by file
        const fileCounts = {};
        
        results.issues.forEach(issue => {
            if (!fileCounts[issue['File Path']]) {
                fileCounts[issue['File Path']] = {
                    total: 0,
                    high: 0,
                    medium: 0,
                    low: 0
                };
            }
            
            fileCounts[issue['File Path']].total++;
            
            if (issue.Severity === 'High') {
                fileCounts[issue['File Path']].high++;
            } else if (issue.Severity === 'Medium') {
                fileCounts[issue['File Path']].medium++;
            } else {
                fileCounts[issue['File Path']].low++;
            }
        });
        
        // Sort files by total issues
        const sortedFiles = Object.keys(fileCounts).sort((a, b) => {
            return fileCounts[b].total - fileCounts[a].total;
        });
        
        // Get top 10 files
        const topFiles = sortedFiles.slice(0, 10);
        
        // Display in table
        const tableBody = document.getElementById('topFilesTableBody');
        tableBody.innerHTML = '';
        
        topFiles.forEach(file => {
            const counts = fileCounts[file];
            const row = document.createElement('tr');
            
            row.innerHTML = `
                <td class="file-path">${file}</td>
                <td class="issue-count">${counts.total}</td>
                <td class="severity-high">${counts.high}</td>
                <td class="severity-medium">${counts.medium}</td>
                <td>${counts.low}</td>
            `;
            
            tableBody.appendChild(row);
        });
    }
    
    // Display module breakdown
    function displayModuleBreakdown(results) {
        // Count issues by module
        const moduleCounts = {};
        
        results.issues.forEach(issue => {
            if (!moduleCounts[issue.Module]) {
                moduleCounts[issue.Module] = {
                    total: 0,
                    high: 0,
                    medium: 0,
                    low: 0
                };
            }
            
            moduleCounts[issue.Module].total++;
            
            if (issue.Severity === 'High') {
                moduleCounts[issue.Module].high++;
            } else if (issue.Severity === 'Medium') {
                moduleCounts[issue.Module].medium++;
            } else {
                moduleCounts[issue.Module].low++;
            }
        });
        
        // No need to calculate code quality score and technical debt anymore
        
        // Sort modules by total issues
        const sortedModules = Object.keys(moduleCounts).sort((a, b) => {
            return moduleCounts[b].total - moduleCounts[a].total;
        });
        
        // Display in table
        const tableBody = document.getElementById('moduleTableBody');
        tableBody.innerHTML = '';
        
        sortedModules.forEach(module => {
            const counts = moduleCounts[module];
            const row = document.createElement('tr');
            
            row.innerHTML = `
                <td>${module}</td>
                <td class="issue-count">${counts.total}</td>
                <td class="severity-high">${counts.high}</td>
                <td class="severity-medium">${counts.medium}</td>
                <td>${counts.low}</td>
                <td>
                    <button class="btn btn-sm btn-primary btn-view-details" 
                            data-module="${module}" 
                            onclick="filterIssuesByModule('${module}')">
                        View Details
                    </button>
                </td>
            `;
            
            tableBody.appendChild(row);
        });
        
        const moduleCtx = document.getElementById('moduleChart').getContext('2d');
        charts.moduleChart = new Chart(moduleCtx, {
            type: 'bar',
            data: {
                labels: sortedModules,
                datasets: [
                    {
                        label: 'High',
                        data: sortedModules.map(m => moduleCounts[m].high),
                        backgroundColor: '#dc3545',
                        stack: 'Stack 0'
                    },
                    {
                        label: 'Medium',
                        data: sortedModules.map(m => moduleCounts[m].medium),
                        backgroundColor: '#fd7e14',
                        stack: 'Stack 0'
                    },
                    {
                        label: 'Low',
                        data: sortedModules.map(m => moduleCounts[m].low),
                        backgroundColor: '#0d6efd',
                        stack: 'Stack 0'
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'Issues by Module'
                    }
                },
                scales: {
                    x: {
                        stacked: true
                    },
                    y: {
                        stacked: true,
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Number of Issues'
                        }
                    }
                }
            }
        });
    }
    
    // Display feature breakdown
    function displayFeatureBreakdown(results) {
        // Count issues by feature
        const featureCounts = {};
        
        results.issues.forEach(issue => {
            const key = `${issue.Module}|${issue.Feature}`;
            
            if (!featureCounts[key]) {
                featureCounts[key] = {
                    module: issue.Module,
                    feature: issue.Feature,
                    total: 0,
                    high: 0,
                    medium: 0,
                    low: 0
                };
            }
            
            featureCounts[key].total++;
            
            if (issue.Severity === 'High') {
                featureCounts[key].high++;
            } else if (issue.Severity === 'Medium') {
                featureCounts[key].medium++;
            } else {
                featureCounts[key].low++;
            }
        });
        
        // Sort features by total issues
        const sortedFeatures = Object.keys(featureCounts).sort((a, b) => {
            return featureCounts[b].total - featureCounts[a].total;
        });
        
        // Display in table
        const tableBody = document.getElementById('featureTableBody');
        tableBody.innerHTML = '';
        
        sortedFeatures.forEach(key => {
            const counts = featureCounts[key];
            const row = document.createElement('tr');
            
            row.innerHTML = `
                <td>${counts.module}</td>
                <td>${counts.feature}</td>
                <td class="issue-count">${counts.total}</td>
                <td class="severity-high">${counts.high}</td>
                <td class="severity-medium">${counts.medium}</td>
                <td>${counts.low}</td>
                <td>
                    <button class="btn btn-sm btn-primary btn-view-details" 
                            data-module="${counts.module}" 
                            data-feature="${counts.feature}" 
                            onclick="filterIssuesByFeature('${counts.module}', '${counts.feature}')">
                        View Details
                    </button>
                </td>
            `;
            
            tableBody.appendChild(row);
        });
        
        // Create feature chart (top 10)
        const topFeatures = sortedFeatures.slice(0, 10);
        const featureCtx = document.getElementById('featureChart').getContext('2d');
        
        charts.featureChart = new Chart(featureCtx, {
            type: 'bar',
            data: {
                labels: topFeatures.map(key => {
                    const counts = featureCounts[key];
                    return `${counts.module}/${counts.feature}`;
                }),
                datasets: [
                    {
                        label: 'High',
                        data: topFeatures.map(key => featureCounts[key].high),
                        backgroundColor: '#dc3545',
                        stack: 'Stack 0'
                    },
                    {
                        label: 'Medium',
                        data: topFeatures.map(key => featureCounts[key].medium),
                        backgroundColor: '#fd7e14',
                        stack: 'Stack 0'
                    },
                    {
                        label: 'Low',
                        data: topFeatures.map(key => featureCounts[key].low),
                        backgroundColor: '#0d6efd',
                        stack: 'Stack 0'
                    }
                ]
            },
            options: {
                responsive: true,
                indexAxis: 'y',
                plugins: {
                    title: {
                        display: true,
                        text: 'Top 10 Features by Issue Count'
                    }
                },
                scales: {
                    x: {
                        stacked: true,
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Number of Issues'
                        }
                    },
                    y: {
                        stacked: true
                    }
                }
            }
        });
    }
    
    // Display all issues
    function displayAllIssues(results) {
        const tableBody = document.getElementById('issuesTableBody');
        tableBody.innerHTML = '';
        
        // Populate issue type filter
        const issueTypeFilter = document.getElementById('issueTypeFilter');
        issueTypeFilter.innerHTML = '<option value="">All Issue Types</option>';
        
        // Populate module filter
        const moduleFilter = document.getElementById('moduleFilter');
        moduleFilter.innerHTML = '<option value="">All Modules</option>';
        
        // Get unique issue types and modules
        const issueTypes = new Set();
        const modules = new Set();
        
        results.issues.forEach(issue => {
            if (issue['Issue Type']) issueTypes.add(issue['Issue Type']);
            if (issue.Module) modules.add(issue.Module);
        });
        
        // Add options to filters
        Array.from(issueTypes).sort().forEach(type => {
            const option = document.createElement('option');
            option.value = type;
            option.textContent = type;
            issueTypeFilter.appendChild(option);
        });
        
        Array.from(modules).sort().forEach(module => {
            const option = document.createElement('option');
            option.value = module;
            option.textContent = module;
            moduleFilter.appendChild(option);
        });
        
        // Display all issues
        results.issues.forEach(issue => {
            const row = document.createElement('tr');
            
            // Ensure Feature is populated
            const feature = issue.Feature || 'General';
            
            // Ensure Description is populated
            const description = issue.Description || issue['Issue Type'] || '';
            
            const severityClass = issue.Severity === 'High' ? 'severity-high' : 
                                (issue.Severity === 'Medium' ? 'severity-medium' : 'severity-low');
            
            row.innerHTML = `
                <td>${issue.Module || ''}</td>
                <td>${issue.Feature || ''}</td>
                <td class="file-path">${issue['File Path'] || ''}</td>
                <td>${issue['Line Number'] || ''}</td>
                <td>${issue['Issue Type'] || ''}</td>
                <td>${issue.Description || ''}</td>
                <td class="${severityClass}">${issue.Severity || ''}</td>
                <td>${issue.Impact || ''}</td>
                <td class="recommendation">${issue.Recommendation || ''}</td>
            `;
            
            tableBody.appendChild(row);
        });
    }
    
    // Filter issues by module
    window.filterIssuesByModule = function(module) {
        // Switch to details tab
        document.getElementById('details-tab').click();
        
        // Set the module filter
        document.getElementById('moduleFilter').value = module;
        
        // Apply DataTable filter
        const table = $('#issuesTable').DataTable();
        table.column(0).search('^' + $.fn.dataTable.util.escapeRegex(module) + '$', true, false).draw();
    };
    
    // Filter issues by feature
    window.filterIssuesByFeature = function(module, feature) {
        // Switch to details tab
        document.getElementById('details-tab').click();
        
        // Set the module filter
        document.getElementById('moduleFilter').value = module;
        
        // Apply DataTable filters
        const table = $('#issuesTable').DataTable();
        
        // Apply module filter
        table.column(0).search('^' + $.fn.dataTable.util.escapeRegex(module) + '$', true, false);
        
        // Apply feature filter
        table.column(1).search('^' + $.fn.dataTable.util.escapeRegex(feature) + '$', true, false).draw();
    };
    
    // Export to CSV
    document.getElementById('exportCSV').addEventListener('click', function() {
        if (!analysisResults) return;
        
        let csvContent = "data:text/csv;charset=utf-8,";
        csvContent += "Module,Feature,File Path,Line Number,Issue Type,Description,Severity,Impact,Recommendation\n";
        
        analysisResults.issues.forEach(issue => {
            csvContent += `"${issue.Module || ''}","${issue.Feature || ''}","${issue['File Path'] || ''}","${issue['Line Number'] || ''}","${issue['Issue Type'] || ''}","${issue.Description || ''}","${issue.Severity || ''}","${issue.Impact || ''}","${issue.Recommendation || ''}"\n`;
        });
        
        const encodedUri = encodeURI(csvContent);
        const link = document.createElement("a");
        link.setAttribute("href", encodedUri);
        link.setAttribute("download", `performance_issues_${new Date().toISOString().split('T')[0]}.csv`);
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    });
    
    // Export to PDF
    document.getElementById('exportPDF').addEventListener('click', function() {
        if (!analysisResults) return;
        
        const { jsPDF } = window.jspdf;
        const doc = new jsPDF();
        
        // Add title
        doc.setFontSize(18);
        doc.text("Swift Performance Analysis Report", 14, 22);
        
        // Add project info
        doc.setFontSize(12);
        doc.text(`Project: ${analysisResults.projectPath}`, 14, 32);
        doc.text(`Analysis Date: ${new Date().toLocaleDateString()}`, 14, 38);
        doc.text(`Total Issues: ${analysisResults.issues.length}`, 14, 44);
        
        // Add summary table
        const severityCounts = {
            'High': 0,
            'Medium': 0,
            'Low': 0
        };
        
        analysisResults.issues.forEach(issue => {
            severityCounts[issue.Severity]++;
        });
        
        doc.autoTable({
            startY: 50,
            head: [['Severity', 'Count']],
            body: [
                ['High', severityCounts.High],
                ['Medium', severityCounts.Medium],
                ['Low', severityCounts.Low],
                ['Total', analysisResults.issues.length]
            ],
            theme: 'grid'
        });
        
        // Add issues table
        const issuesData = analysisResults.issues.map(issue => [
            issue.Module || '',
            issue.Feature || '',
            issue['File Path'] || '',
            issue['Line Number'] || '',
            issue['Issue Type'] || '',
            issue.Severity || ''
        ]);
        
        doc.autoTable({
            startY: doc.lastAutoTable.finalY + 10,
            head: [['Module', 'Feature', 'File Path', 'Line', 'Issue Type', 'Severity']],
            body: issuesData,
            theme: 'grid',
            styles: { fontSize: 8 },
            columnStyles: {
                0: { cellWidth: 25 },
                1: { cellWidth: 25 },
                2: { cellWidth: 60 },
                3: { cellWidth: 15 },
                4: { cellWidth: 30 },
                5: { cellWidth: 20 }
            },
            margin: { top: 60 }
        });
        
        // Save PDF
        doc.save(`performance_analysis_${new Date().toISOString().split('T')[0]}.pdf`);
    });
});
