import Foundation
import ArgumentParser
import SwiftPerformanceAggregator
import Logging

// Configure logging
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

var logger = Logger(label: "com.windsurf.spa-cli")

// Define the main command
struct SPACommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "spa-cli",
        abstract: "Swift Performance Aggregator CLI",
        discussion: "A tool for collecting, analyzing, and visualizing performance metrics from Swift projects.",
        version: "1.0.0",
        subcommands: [
            CollectCommand.self,
            ReportCommand.self,
            ServeCommand.self,
            ConfigCommand.self
        ],
        defaultSubcommand: CollectCommand.self
    )
}

// Command to collect performance metrics
struct CollectCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "collect",
        abstract: "Collect performance metrics from a Swift project"
    )
    
    @Option(name: .long, help: "Path to the Swift project")
    var project: String
    
    @Option(name: .long, help: "Project name (defaults to directory name)")
    var projectName: String?
    
    @Option(name: .long, help: "Path to configuration file")
    var config: String?
    
    @Option(name: .long, help: "Git commit hash")
    var commit: String?
    
    @Option(name: .long, help: "Git branch name")
    var branch: String?
    
    @Flag(name: .long, help: "Enable verbose logging")
    var verbose: Bool = false
    
    func run() throws {
        if verbose {
            // Set log level to debug if verbose
            // Note: We can't bootstrap the logging system again, so we'll just create a new logger with debug level
            logger.logLevel = .debug
        }
        
        // Resolve project path
        let projectPath = URL(fileURLWithPath: project).path
        
        // Determine project name
        let resolvedProjectName = projectName ?? URL(fileURLWithPath: projectPath).lastPathComponent
        
        logger.info("Starting performance metrics collection for \(resolvedProjectName) at \(projectPath)")
        
        // Load configuration
        let configuration: Configuration
        if let configPath = config {
            logger.info("Loading configuration from \(configPath)")
            configuration = try Configuration.load(from: URL(fileURLWithPath: configPath))
        } else {
            logger.info("Using default configuration")
            configuration = Configuration.defaultConfig(for: resolvedProjectName)
        }
        
        // Create storage
        let storage: MetricsStorage
        switch configuration.storage.type {
        case .memory:
            storage = InMemoryStorage()
        case .file:
            let storageDir = configuration.storage.path.map { URL(fileURLWithPath: $0) } ?? 
                             FileManager.default.temporaryDirectory.appendingPathComponent("spa-metrics")
            storage = try FileStorage(storageDirectory: storageDir)
        default:
            logger.warning("Unsupported storage type \(configuration.storage.type.rawValue), falling back to file storage")
            let storageDir = FileManager.default.temporaryDirectory.appendingPathComponent("spa-metrics")
            storage = try FileStorage(storageDirectory: storageDir)
        }
        
        // Create metrics aggregator
        let aggregator = MetricsAggregator(configuration: configuration, storage: storage)
        
        // Register collectors
        aggregator.registerDefaultCollectors()
        
        // Create a semaphore to wait for collection to complete
        let semaphore = DispatchSemaphore(value: 0)
        var collectionResult: Result<[PerformanceMetric], Error>?
        
        // Collect metrics
        aggregator.collectMetrics(for: projectPath) { result in
            collectionResult = result
            semaphore.signal()
        }
        
        // Wait for collection to complete
        semaphore.wait()
        
        // Process result
        switch collectionResult! {
        case .success(let metrics):
            logger.info("Successfully collected \(metrics.count) metrics")
            
            // Group metrics by type
            let metricsByType = Dictionary(grouping: metrics) { $0.type }
            for (type, typeMetrics) in metricsByType {
                logger.info("  - \(type.displayName): \(typeMetrics.count) metrics")
            }
            
            // Print summary
            print("\nPerformance Metrics Summary:")
            print("----------------------------")
            print("Project: \(resolvedProjectName)")
            print("Total metrics collected: \(metrics.count)")
            
            for (type, typeMetrics) in metricsByType {
                let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
                print("  \(type.displayName): \(String(format: "%.2f", avgValue)) \(typeMetrics.first?.unit ?? "")")
            }
            
        case .failure(let error):
            logger.error("Failed to collect metrics: \(error)")
            throw error
        }
    }
}

// Command to generate a performance report
struct ReportCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate a performance report"
    )
    
    @Option(name: .long, help: "Project name")
    var project: String
    
    @Option(name: .long, help: "Path to configuration file")
    var config: String?
    
    @Option(name: .long, help: "Number of days to include in the report")
    var days: Int = 30
    
    @Option(name: .long, help: "Output format (json, text)")
    var format: String = "text"
    
    @Option(name: .long, help: "Output file path (defaults to stdout)")
    var output: String?
    
    func run() throws {
        // Load configuration
        let configuration: Configuration
        if let configPath = config {
            logger.info("Loading configuration from \(configPath)")
            configuration = try Configuration.load(from: URL(fileURLWithPath: configPath))
        } else {
            logger.info("Using default configuration for project \(project)")
            configuration = Configuration.defaultConfig(for: project)
        }
        
        // Create storage
        let storage: MetricsStorage
        switch configuration.storage.type {
        case .memory:
            storage = InMemoryStorage()
        case .file:
            let storageDir = configuration.storage.path.map { URL(fileURLWithPath: $0) } ?? 
                             FileManager.default.temporaryDirectory.appendingPathComponent("spa-metrics")
            storage = try FileStorage(storageDirectory: storageDir)
        default:
            logger.warning("Unsupported storage type \(configuration.storage.type.rawValue), falling back to file storage")
            let storageDir = FileManager.default.temporaryDirectory.appendingPathComponent("spa-metrics")
            storage = try FileStorage(storageDirectory: storageDir)
        }
        
        // Create metrics aggregator
        let aggregator = MetricsAggregator(configuration: configuration, storage: storage)
        
        // Create a semaphore to wait for report generation to complete
        let semaphore = DispatchSemaphore(value: 0)
        var reportResult: Result<PerformanceReport, Error>?
        
        // Generate report
        let timeRange = TimeRange.last(days: days)
        aggregator.generateReport(timeRange: timeRange) { result in
            reportResult = result
            semaphore.signal()
        }
        
        // Wait for report generation to complete
        semaphore.wait()
        
        // Process result
        switch reportResult! {
        case .success(let report):
            logger.info("Successfully generated report with \(report.metrics.count) metrics")
            
            // Output report
            switch format.lowercased() {
            case "json":
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                
                let jsonData = try encoder.encode(report)
                let jsonString = String(data: jsonData, encoding: .utf8)!
                
                if let outputPath = output {
                    try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    logger.info("Report written to \(outputPath)")
                } else {
                    print(jsonString)
                }
                
            case "text":
                let reportText = formatReportAsText(report)
                
                if let outputPath = output {
                    try reportText.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    logger.info("Report written to \(outputPath)")
                } else {
                    print(reportText)
                }
                
            default:
                throw ValidationError("Unsupported output format: \(format)")
            }
            
        case .failure(let error):
            logger.error("Failed to generate report: \(error)")
            throw error
        }
    }
    
    private func formatReportAsText(_ report: PerformanceReport) -> String {
        var text = """
        Performance Report
        =================
        Project: \(report.projectName)
        Generated: \(formatDate(report.generatedAt))
        Metrics: \(report.metrics.count)
        
        """
        
        // Group metrics by type
        let metricsByType = Dictionary(grouping: report.metrics) { $0.type }
        
        text += "Metrics by Type:\n"
        for (type, typeMetrics) in metricsByType {
            let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
            text += "  \(type.displayName): \(String(format: "%.2f", avgValue)) \(typeMetrics.first?.unit ?? "") (\(typeMetrics.count) samples)\n"
        }
        
        // Add baseline comparison if available
        if let comparison = report.baselineComparison {
            text += "\nBaseline Comparison (vs \(comparison.baselineId)):\n"
            
            if !comparison.improvements.isEmpty {
                text += "  Improvements:\n"
                for improvement in comparison.improvements {
                    let percentChange = abs(improvement.percentChange)
                    text += "    - \(String(format: "%.2f%%", percentChange)) improvement\n"
                }
            }
            
            if !comparison.regressions.isEmpty {
                text += "  Regressions:\n"
                for regression in comparison.regressions {
                    text += "    - \(String(format: "%.2f%%", regression.percentChange)) regression\n"
                }
            }
        }
        
        return text
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// Command to start the API server
struct ServeCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the performance metrics API server"
    )
    
    @Option(name: .long, help: "Path to configuration file")
    var config: String?
    
    @Option(name: .long, help: "Project name")
    var project: String?
    
    @Option(name: .long, help: "Port to listen on")
    var port: Int = 8080
    
    func run() throws {
        // Load configuration
        let configuration: Configuration
        if let configPath = config {
            logger.info("Loading configuration from \(configPath)")
            configuration = try Configuration.load(from: URL(fileURLWithPath: configPath))
        } else if let projectName = project {
            logger.info("Using default configuration for project \(projectName)")
            configuration = Configuration.defaultConfig(for: projectName)
        } else {
            throw ValidationError("Either --config or --project must be specified")
        }
        
        // Create storage
        let storage: MetricsStorage
        switch configuration.storage.type {
        case .memory:
            storage = InMemoryStorage()
        case .file:
            let storageDir = configuration.storage.path.map { URL(fileURLWithPath: $0) } ?? 
                             FileManager.default.temporaryDirectory.appendingPathComponent("spa-metrics")
            storage = try FileStorage(storageDirectory: storageDir)
        default:
            logger.warning("Unsupported storage type \(configuration.storage.type.rawValue), falling back to file storage")
            let storageDir = FileManager.default.temporaryDirectory.appendingPathComponent("spa-metrics")
            storage = try FileStorage(storageDirectory: storageDir)
        }
        
        // Create metrics aggregator
        let aggregator = MetricsAggregator(configuration: configuration, storage: storage)
        
        // Create Windsurf integration
        let integration = WindsurfIntegration(aggregator: aggregator, configuration: configuration)
        
        logger.info("Starting API server on port \(port)")
        print("Swift Performance Metrics API server starting on port \(port)")
        print("Press Ctrl+C to stop")
        
        // Start the server
        try integration.start()
    }
}

// Command to manage configuration
struct ConfigCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage configuration"
    )
    
    @Option(name: .long, help: "Project name")
    var project: String
    
    @Option(name: .long, help: "Output path for configuration file")
    var output: String
    
    @Flag(name: .long, help: "Create a default configuration file")
    var createDefault: Bool = false
    
    func run() throws {
        if createDefault {
            // Create default configuration
            let config = Configuration.defaultConfig(for: project)
            
            // Save to file
            try config.save(to: URL(fileURLWithPath: output))
            
            logger.info("Created default configuration for project \(project) at \(output)")
            print("Default configuration created at \(output)")
        } else {
            throw ValidationError("No action specified. Use --create-default to create a default configuration.")
        }
    }
}

// Run the command
SPACommand.main()
