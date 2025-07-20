import Foundation
import Logging

public class BuildTimeCollector: BaseCollector {
    public let id = "buildTime"
    public let name = "Build Time Collector"
    public let description = "Collects build time metrics from Swift projects"
    
    private let logger = Logger(label: "com.windsurf.buildtime-collector")
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval = 600) {
        self.timeout = timeout
    }
    
    public func getSupportedMetricTypes() -> [MetricType] {
        return [.buildDuration]
    }
    
    public func isAvailable() -> Bool {
        // Check if xcodebuild is available
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["xcodebuild"]
        
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
        // Find Xcode project or workspace
        guard let (projectFile, schemeName) = findXcodeProjectInfo(at: projectPath) else {
            completion(.failure(CollectorError.unsupportedProject("No Xcode project found")))
            return
        }
        
        // Measure build time
        measureBuildTime(projectFile: projectFile, scheme: schemeName, projectName: projectName) { result in
            switch result {
            case .success(let buildMetrics):
                completion(.success(buildMetrics))
            case .failure(let error):
                completion(.failure(error))
            }
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
    
    private func measureBuildTime(projectFile: String, scheme: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        let isWorkspace = projectFile.hasSuffix(".xcworkspace")
        
        // Clean first to ensure consistent build times
        cleanProject(projectFile: projectFile, scheme: scheme, isWorkspace: isWorkspace) { cleanResult in
            switch cleanResult {
            case .success:
                // Now perform the timed build
                self.timedBuild(projectFile: projectFile, scheme: scheme, isWorkspace: isWorkspace) { buildResult in
                    switch buildResult {
                    case .success(let buildTime):
                        // Create metrics
                        let metric = PerformanceMetric(
                            source: .buildTime,
                            type: .buildDuration,
                            value: buildTime,
                            unit: "seconds",
                            timestamp: Date(),
                            metadata: [
                                "scheme": scheme,
                                "configuration": "Debug"
                            ],
                            projectName: projectName
                        )
                        
                        // Also collect per-file build times if possible
                        self.collectPerFileBuildTimes(projectFile: projectFile, scheme: scheme, isWorkspace: isWorkspace, projectName: projectName) { fileMetricsResult in
                            switch fileMetricsResult {
                            case .success(let fileMetrics):
                                // Combine overall build time with per-file metrics
                                var allMetrics = [metric]
                                allMetrics.append(contentsOf: fileMetrics)
                                completion(.success(allMetrics))
                            case .failure(_):
                                // If per-file metrics fail, just return the overall build time
                                completion(.success([metric]))
                            }
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func cleanProject(projectFile: String, scheme: String, isWorkspace: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        
        // Build arguments based on project type
        var arguments = ["xcodebuild", "clean"]
        if isWorkspace {
            arguments.append(contentsOf: ["-workspace", projectFile])
        } else {
            arguments.append(contentsOf: ["-project", projectFile])
        }
        arguments.append(contentsOf: ["-scheme", scheme])
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        logger.info("Cleaning project with command: xcrun \(arguments.joined(separator: " "))")
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                completion(.failure(CollectorError.timeout("Project clean")))
            }
        }
        
        do {
            try process.run()
            
            // Schedule timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout / 2, execute: timeoutWorkItem)
            
            process.waitUntilExit()
            
            // Cancel timeout since process completed
            timeoutWorkItem.cancel()
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                logger.info("Project cleaned successfully")
                completion(.success(()))
            } else {
                logger.error("Project clean failed with exit code: \(process.terminationStatus)")
                completion(.failure(CollectorError.executionFailed("Clean failed with exit code \(process.terminationStatus): \(errorOutput)")))
            }
        } catch {
            timeoutWorkItem.cancel()
            logger.error("Failed to clean project: \(error)")
            completion(.failure(CollectorError.executionFailed(error.localizedDescription)))
        }
    }
    
    private func timedBuild(projectFile: String, scheme: String, isWorkspace: Bool, completion: @escaping (Result<Double, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        
        // Build arguments based on project type
        var arguments = ["xcodebuild", "build"]
        if isWorkspace {
            arguments.append(contentsOf: ["-workspace", projectFile])
        } else {
            arguments.append(contentsOf: ["-project", projectFile])
        }
        arguments.append(contentsOf: ["-scheme", scheme, "-configuration", "Debug"])
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        logger.info("Building project with command: xcrun \(arguments.joined(separator: " "))")
        
        // Record start time
        let startTime = Date()
        
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
            
            // Calculate build time
            let buildTime = Date().timeIntervalSince(startTime)
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                logger.info("Project built successfully in \(String(format: "%.2f", buildTime)) seconds")
                completion(.success(buildTime))
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
    
    private func collectPerFileBuildTimes(projectFile: String, scheme: String, isWorkspace: Bool, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        // Use Build Time Analyzer approach to collect per-file build times
        // This requires parsing the build log with -showBuildTimingSummary flag
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        
        // Build arguments based on project type
        var arguments = ["xcodebuild", "build"]
        if isWorkspace {
            arguments.append(contentsOf: ["-workspace", projectFile])
        } else {
            arguments.append(contentsOf: ["-project", projectFile])
        }
        arguments.append(contentsOf: ["-scheme", scheme, "-configuration", "Debug", "-showBuildTimingSummary"])
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        logger.info("Collecting per-file build times")
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                completion(.failure(CollectorError.timeout("Per-file build time collection")))
            }
        }
        
        do {
            try process.run()
            
            // Schedule timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
            
            process.waitUntilExit()
            
            // Cancel timeout since process completed
            timeoutWorkItem.cancel()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                // Parse build timing summary
                let metrics = parseBuildTimingSummary(output, projectName: projectName)
                logger.info("Collected \(metrics.count) per-file build time metrics")
                completion(.success(metrics))
            } else {
                logger.warning("Failed to collect per-file build times, continuing with overall build time only")
                completion(.success([]))
            }
        } catch {
            timeoutWorkItem.cancel()
            logger.warning("Failed to collect per-file build times: \(error)")
            completion(.success([]))
        }
    }
    
    private func parseBuildTimingSummary(_ output: String, projectName: String) -> [PerformanceMetric] {
        var metrics: [PerformanceMetric] = []
        
        // Look for the build timing summary section
        let lines = output.components(separatedBy: .newlines)
        var inTimingSummary = false
        
        for line in lines {
            if line.contains("Build Timing Summary") {
                inTimingSummary = true
                continue
            }
            
            if inTimingSummary {
                // Parse lines like:
                // CompileSwift normal x86_64 /path/to/File.swift
                //     0.3 seconds
                
                if line.contains("CompileSwift") && line.contains(".swift") {
                    // Extract file path
                    if let filePath = line.components(separatedBy: " ").last {
                        // Look for the time on the next line
                        if let nextLineIndex = lines.firstIndex(of: line)?.advanced(by: 1),
                           nextLineIndex < lines.count {
                            let timeLine = lines[nextLineIndex]
                            if let timeString = timeLine.components(separatedBy: " ").first,
                               let buildTime = Double(timeString) {
                                
                                // Create metric
                                let metric = PerformanceMetric(
                                    source: .buildTime,
                                    type: .buildDuration,
                                    value: buildTime,
                                    unit: "seconds",
                                    timestamp: Date(),
                                    metadata: [
                                        "fileType": "swift",
                                        "operation": "compile"
                                    ],
                                    filePath: filePath,
                                    projectName: projectName
                                )
                                
                                metrics.append(metric)
                            }
                        }
                    }
                }
                
                // End of timing summary
                if line.contains("Total") {
                    break
                }
            }
        }
        
        return metrics
    }
}
