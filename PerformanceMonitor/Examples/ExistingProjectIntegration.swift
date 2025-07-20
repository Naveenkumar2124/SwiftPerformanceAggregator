import Foundation
import SwiftPerformanceAggregator

/// Example showing how to integrate the Swift Performance Metrics Aggregator with an existing project
class ExistingProjectIntegration {
    /// Path to your existing Swift project
    let projectPath: String
    /// Name of your project
    let projectName: String
    /// Configuration for the performance metrics aggregator
    let configuration: Configuration
    /// Storage for performance metrics
    let storage: MetricsStorage
    /// Metrics aggregator instance
    let aggregator: MetricsAggregator
    
    init(projectPath: String, projectName: String) {
        self.projectPath = projectPath
        self.projectName = projectName
        
        // Create configuration
        self.configuration = Configuration(
            projectName: projectName,
            enabledCollectors: ["xctest", "instruments", "metrickit", "buildTime"],
            visualizationOptions: Configuration.VisualizationOptions(
                enabledCharts: [.timeline, .heatmap, .comparison],
                defaultTimeRange: TimeRange.last(days: 30),
                colorScheme: .system
            ),
            windsurf: Configuration.WindsurfConfiguration(
                apiEndpoint: URL(string: "https://your-windsurf-instance.com/api")!,
                apiKey: "YOUR_API_KEY",
                enableWebhooks: true
            ),
            storage: Configuration.StorageConfiguration(
                type: .file,
                path: "\(NSHomeDirectory())/Library/Application Support/PerformanceMetrics",
                retentionDays: 90
            )
        )
        
        // Create storage
        do {
            let storageDir = URL(fileURLWithPath: self.configuration.storage.path ?? "\(NSHomeDirectory())/Library/Application Support/PerformanceMetrics")
            self.storage = try FileStorage(storageDirectory: storageDir)
        } catch {
            print("Error creating storage: \(error)")
            // Fall back to in-memory storage
            self.storage = InMemoryStorage()
        }
        
        // Create aggregator
        self.aggregator = MetricsAggregator(configuration: self.configuration, storage: self.storage)
        
        // Register collectors
        aggregator.registerDefaultCollectors()
    }
    
    /// Collect performance metrics from the project
    func collectMetrics(completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        print("Collecting performance metrics for \(projectName) at \(projectPath)")
        
        aggregator.collectMetrics(for: projectPath) { result in
            switch result {
            case .success(let metrics):
                print("Successfully collected \(metrics.count) metrics")
                
                // Group metrics by type for reporting
                let metricsByType = Dictionary(grouping: metrics, by: { $0.type })
                
                // Print summary
                print("\nPerformance Metrics Summary:")
                print("----------------------------")
                
                for (type, typeMetrics) in metricsByType {
                    let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
                    print("  \(type.displayName): \(String(format: "%.2f", avgValue)) \(typeMetrics.first?.unit ?? "")")
                }
                
                completion(.success(metrics))
                
            case .failure(let error):
                print("Error collecting metrics: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Generate a performance report
    func generateReport(completion: @escaping (Result<PerformanceReport, Error>) -> Void) {
        print("Generating performance report for \(projectName)")
        
        aggregator.generateReport { result in
            switch result {
            case .success(let report):
                print("Successfully generated report with \(report.metrics.count) metrics")
                completion(.success(report))
                
            case .failure(let error):
                print("Error generating report: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Start the API server for Windsurf integration
    func startAPIServer() {
        print("Starting API server for Windsurf integration")
        
        let integration = WindsurfIntegration(aggregator: aggregator, configuration: configuration)
        
        do {
            try integration.start()
            print("API server started successfully")
        } catch {
            print("Error starting API server: \(error)")
        }
    }
}

// Example usage
func runExample() {
    // Replace with your project path and name
    let integration = ExistingProjectIntegration(
        projectPath: "/path/to/your/swift/project",
        projectName: "YourSwiftApp"
    )
    
    // Collect metrics
    integration.collectMetrics { result in
        switch result {
        case .success(let metrics):
            print("Collected \(metrics.count) metrics")
            
            // Generate report
            integration.generateReport { reportResult in
                switch reportResult {
                case .success(let report):
                    print("Generated report with \(report.metrics.count) metrics")
                case .failure(let error):
                    print("Error generating report: \(error)")
                }
            }
            
        case .failure(let error):
            print("Error: \(error)")
        }
    }
    
    // Start API server (uncomment to enable)
    // integration.startAPIServer()
}

// Uncomment to run the example
// runExample()
