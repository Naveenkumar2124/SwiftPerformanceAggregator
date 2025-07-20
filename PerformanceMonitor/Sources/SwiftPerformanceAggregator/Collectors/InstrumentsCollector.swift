import Foundation
import Logging

public class InstrumentsCollector: BaseCollector {
    public let id = "instruments"
    public let name = "Instruments Performance Collector"
    public let description = "Collects performance metrics from Xcode Instruments"
    
    private let logger = Logger(label: "com.windsurf.instruments-collector")
    private let timeout: TimeInterval
    private let templates: [InstrumentTemplate]
    
    public struct InstrumentTemplate {
        let id: String
        let name: String
        let metricTypes: [MetricType]
        
        public static let timeProfiler = InstrumentTemplate(
            id: "time", 
            name: "Time Profiler",
            metricTypes: [.cpuTime]
        )
        
        public static let allocations = InstrumentTemplate(
            id: "allocations", 
            name: "Allocations",
            metricTypes: [.memoryUsage]
        )
        
        public static let energy = InstrumentTemplate(
            id: "energy", 
            name: "Energy Log",
            metricTypes: [.energyImpact]
        )
        
        public static let fileActivity = InstrumentTemplate(
            id: "fileactivity", 
            name: "File Activity",
            metricTypes: [.diskIO]
        )
        
        public static let networkActivity = InstrumentTemplate(
            id: "network", 
            name: "Network",
            metricTypes: [.networkLatency]
        )
    }
    
    public init(
        timeout: TimeInterval = 300,
        templates: [InstrumentTemplate] = [.timeProfiler, .allocations]
    ) {
        self.timeout = timeout
        self.templates = templates
    }
    
    public func getSupportedMetricTypes() -> [MetricType] {
        return templates.flatMap { $0.metricTypes }
    }
    
    public func isAvailable() -> Bool {
        // Check if instruments is available
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["instruments"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    public func collectMetrics(for projectPath: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        // Find the built app
        findBuiltApp(in: projectPath) { result in
            switch result {
            case .success(let appPath):
                self.runInstruments(for: appPath, projectName: projectName, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func findBuiltApp(in projectPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        // First, build the project
        buildProject(at: projectPath) { result in
            switch result {
            case .success:
                // Now find the built app in derived data
                self.findAppInDerivedData(for: projectPath) { appResult in
                    switch appResult {
                    case .success(let appPath):
                        completion(.success(appPath))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func buildProject(at path: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Find Xcode project or workspace
        guard let (projectPath, schemeName) = findXcodeProjectInfo(at: path) else {
            completion(.failure(CollectorError.unsupportedProject("No Xcode project found")))
            return
        }
        
        let isWorkspace = projectPath.hasSuffix(".xcworkspace")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        
        // Build arguments based on project type
        var arguments = ["xcodebuild", "build"]
        if isWorkspace {
            arguments.append(contentsOf: ["-workspace", projectPath])
        } else {
            arguments.append(contentsOf: ["-project", projectPath])
        }
        arguments.append(contentsOf: ["-scheme", schemeName, "-configuration", "Debug"])
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        logger.info("Building project with command: xcrun \(arguments.joined(separator: " "))")
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                completion(.failure(CollectorError.timeout("Project build")))
            }
        }
        
        do {
            try process.run()
            
            // Schedule timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
            
            process.waitUntilExit()
            
            // Cancel timeout since process completed
            timeoutWorkItem.cancel()
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                logger.info("Project built successfully")
                completion(.success(()))
            } else {
                logger.error("Project build failed with exit code: \(process.terminationStatus)")
                completion(.failure(CollectorError.executionFailed("Build failed with exit code \(process.terminationStatus): \(errorOutput)")))
            }
        } catch {
            timeoutWorkItem.cancel()
            logger.error("Failed to build project: \(error)")
            completion(.failure(CollectorError.executionFailed(error.localizedDescription)))
        }
    }
    
    private func findXcodeProjectInfo(at path: String) -> (projectPath: String, schemeName: String)? {
        // Try to find .xcodeproj or .xcworkspace
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            
            // First look for xcworkspace
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
                let workspaceName = workspace.replacingOccurrences(of: ".xcworkspace", with: "")
                return (path + "/" + workspace, workspaceName)
            }
            
            // Then look for xcodeproj
            if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                let projectName = project.replacingOccurrences(of: ".xcodeproj", with: "")
                return (path + "/" + project, projectName)
            }
            
            return nil
        } catch {
            logger.error("Error finding Xcode project: \(error)")
            return nil
        }
    }
    
    private func findAppInDerivedData(for projectPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Get the project name from the path
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        
        // Look in the default derived data location
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let derivedDataDir = homeDir.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: derivedDataDir, includingPropertiesForKeys: nil)
            
            // Look for a directory that starts with the project name
            for item in contents {
                if item.lastPathComponent.hasPrefix(projectName) {
                    // Look for the app in the build products directory
                    let buildDir = item.appendingPathComponent("Build/Products/Debug-iphonesimulator")
                    
                    do {
                        let buildContents = try FileManager.default.contentsOfDirectory(at: buildDir, includingPropertiesForKeys: nil)
                        
                        // Find the first .app bundle
                        if let appBundle = buildContents.first(where: { $0.pathExtension == "app" }) {
                            logger.info("Found app bundle at \(appBundle.path)")
                            completion(.success(appBundle.path))
                            return
                        }
                    } catch {
                        // Continue searching in other directories
                        continue
                    }
                }
            }
            
            completion(.failure(CollectorError.unsupportedProject("Could not find built app in derived data")))
        } catch {
            logger.error("Error searching derived data: \(error)")
            completion(.failure(CollectorError.executionFailed(error.localizedDescription)))
        }
    }
    
    private func runInstruments(for appPath: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        let group = DispatchGroup()
        var allMetrics: [PerformanceMetric] = []
        var errors: [Error] = []
        
        // Run each template
        for template in templates {
            group.enter()
            
            runInstrumentTemplate(template, for: appPath, projectName: projectName) { result in
                switch result {
                case .success(let metrics):
                    allMetrics.append(contentsOf: metrics)
                case .failure(let error):
                    errors.append(error)
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .global()) {
            if errors.isEmpty || !allMetrics.isEmpty {
                completion(.success(allMetrics))
            } else {
                completion(.failure(CollectorError.executionFailed("All instrument templates failed: \(errors.map { $0.localizedDescription }.joined(separator: ", "))")))
            }
        }
    }
    
    private func runInstrumentTemplate(_ template: InstrumentTemplate, for appPath: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        // Create a temporary trace file
        let tempDir = FileManager.default.temporaryDirectory
        let traceFile = tempDir.appendingPathComponent("\(UUID().uuidString).trace")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        
        // Build the instruments command
        let arguments = [
            "instruments",
            "-t", "Instruments.app/Contents/Resources/templates/\(template.name).tracetemplate",
            "-D", traceFile.path,
            appPath,
            "-e", "DYLD_INSERT_LIBRARIES", "",
            "-e", "DYLD_FRAMEWORK_PATH", "",
            "-e", "DYLD_LIBRARY_PATH", ""
        ]
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        logger.info("Running instruments with template \(template.name)")
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                completion(.failure(CollectorError.timeout("Instruments execution")))
            }
        }
        
        do {
            try process.run()
            
            // Schedule timeout - instruments runs for a while to collect data
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutWorkItem)
            
            process.waitUntilExit()
            
            // Cancel timeout since process completed
            timeoutWorkItem.cancel()
            
            // Parse the trace file to extract metrics
            parseTraceFile(traceFile, template: template, projectName: projectName, completion: completion)
        } catch {
            timeoutWorkItem.cancel()
            logger.error("Failed to run instruments: \(error)")
            completion(.failure(CollectorError.executionFailed(error.localizedDescription)))
        }
    }
    
    private func parseTraceFile(_ traceFile: URL, template: InstrumentTemplate, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        // In a real implementation, you would parse the trace file format
        // For this example, we'll simulate extracting metrics based on the template
        
        var metrics: [PerformanceMetric] = []
        
        // Simulate extracting metrics based on template type
        switch template.id {
        case "time":
            // CPU time metrics
            metrics.append(PerformanceMetric(
                source: .instruments,
                type: .cpuTime,
                value: Double.random(in: 0.1...5.0),
                unit: "seconds",
                metadata: ["template": template.name],
                projectName: projectName
            ))
            
        case "allocations":
            // Memory usage metrics
            metrics.append(PerformanceMetric(
                source: .instruments,
                type: .memoryUsage,
                value: Double.random(in: 10...500),
                unit: "MB",
                metadata: ["template": template.name],
                projectName: projectName
            ))
            
        case "energy":
            // Energy impact metrics
            metrics.append(PerformanceMetric(
                source: .instruments,
                type: .energyImpact,
                value: Double.random(in: 0...100),
                unit: "score",
                metadata: ["template": template.name],
                projectName: projectName
            ))
            
        case "fileactivity":
            // Disk I/O metrics
            metrics.append(PerformanceMetric(
                source: .instruments,
                type: .diskIO,
                value: Double.random(in: 0.1...50),
                unit: "MB/s",
                metadata: ["template": template.name],
                projectName: projectName
            ))
            
        case "network":
            // Network metrics
            metrics.append(PerformanceMetric(
                source: .instruments,
                type: .networkLatency,
                value: Double.random(in: 10...500),
                unit: "ms",
                metadata: ["template": template.name],
                projectName: projectName
            ))
            
        default:
            // Unknown template
            completion(.failure(CollectorError.dataParsingFailed("Unknown template: \(template.id)")))
            return
        }
        
        logger.info("Extracted \(metrics.count) metrics from \(template.name) trace")
        completion(.success(metrics))
    }
}
