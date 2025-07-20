import Foundation
import Logging

public class XCTestCollector: BaseCollector {
    public let id = "xctest"
    public let name = "XCTest Performance Collector"
    public let description = "Collects performance metrics from XCTest performance tests"
    
    private let logger = Logger(label: "com.windsurf.xctest-collector")
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval = 300) {
        self.timeout = timeout
    }
    
    public func getSupportedMetricTypes() -> [MetricType] {
        return [.cpuTime, .memoryUsage]
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
        // Check if project has XCTest performance tests
        guard projectContainsPerformanceTests(at: projectPath) else {
            completion(.failure(CollectorError.unsupportedProject("No performance tests found in project")))
            return
        }
        
        // Run the tests and collect performance metrics
        runPerformanceTests(at: projectPath) { result in
            switch result {
            case .success(let testResults):
                let metrics = self.parseTestResults(testResults, projectName: projectName)
                completion(.success(metrics))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func projectContainsPerformanceTests(at path: String) -> Bool {
        // Search for files containing "measure" blocks which indicate performance tests
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-r", "--include=*.swift", "measure\\s*{", path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                logger.info("Found performance tests in project")
                return true
            } else {
                logger.warning("No performance tests found in project")
                return false
            }
        } catch {
            logger.error("Error searching for performance tests: \(error)")
            return false
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
    
    private func runPerformanceTests(at path: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let (projectPath, schemeName) = findXcodeProjectInfo(at: path) else {
            completion(.failure(CollectorError.unsupportedProject("No Xcode project found")))
            return
        }
        
        let isWorkspace = projectPath.hasSuffix(".xcworkspace")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        
        // Create a temporary directory for test results
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Build arguments based on project type
        var arguments = ["xcodebuild", "test"]
        if isWorkspace {
            arguments.append(contentsOf: ["-workspace", projectPath])
        } else {
            arguments.append(contentsOf: ["-project", projectPath])
        }
        arguments.append(contentsOf: ["-scheme", schemeName])
        arguments.append(contentsOf: ["-resultBundlePath", tempDir.path])
        
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        logger.info("Running performance tests with command: xcrun \(arguments.joined(separator: " "))")
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                completion(.failure(CollectorError.timeout("Performance test execution")))
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
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                logger.info("Performance tests completed successfully")
                completion(.success(output + "\n" + errorOutput))
            } else {
                logger.error("Performance tests failed with exit code: \(process.terminationStatus)")
                completion(.failure(CollectorError.executionFailed("Tests failed with exit code \(process.terminationStatus): \(errorOutput)")))
            }
        } catch {
            timeoutWorkItem.cancel()
            logger.error("Failed to run performance tests: \(error)")
            completion(.failure(CollectorError.executionFailed(error.localizedDescription)))
        }
    }
    
    private func parseTestResults(_ results: String, projectName: String) -> [PerformanceMetric] {
        var metrics: [PerformanceMetric] = []
        
        // Parse the test results to extract performance metrics
        // Example output line: 
        // Test Case '-[MyAppTests.PerformanceTests testPerformance_calculation]' measured [Time, seconds] average: 0.001, relative standard deviation: 23.432%, values: [0.002000, 0.001000, 0.001000, 0.001000, 0.001000], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
        
        let lines = results.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("measured [") && line.contains("average:") {
                // Extract test name
                var testName = ""
                if let testNameRange = line.range(of: "-\\[.*?\\]", options: .regularExpression) {
                    testName = String(line[testNameRange])
                        .replacingOccurrences(of: "-[", with: "")
                        .replacingOccurrences(of: "]", with: "")
                }
                
                // Extract metric type
                var metricTypeStr = ""
                if let metricRange = line.range(of: "measured \\[.*?\\]", options: .regularExpression) {
                    metricTypeStr = String(line[metricRange])
                        .replacingOccurrences(of: "measured [", with: "")
                        .replacingOccurrences(of: "]", with: "")
                }
                
                // Extract average value
                var averageValue: Double = 0
                if let avgRange = line.range(of: "average: [0-9.]+", options: .regularExpression) {
                    let avgStr = String(line[avgRange])
                        .replacingOccurrences(of: "average: ", with: "")
                    averageValue = Double(avgStr) ?? 0
                }
                
                // Determine metric type and unit
                let metricType: MetricType
                let unit: String
                
                if metricTypeStr.lowercased().contains("time") {
                    metricType = .cpuTime
                    unit = "seconds"
                } else if metricTypeStr.lowercased().contains("memory") {
                    metricType = .memoryUsage
                    unit = "MB"
                } else {
                    metricType = .custom
                    unit = ""
                }
                
                // Extract function name if needed in the future
                let _ = testName.components(separatedBy: ".").last ?? ""
                
                // Create the metric
                let metric = PerformanceMetric(
                    source: .xctest,
                    type: metricType,
                    value: averageValue,
                    unit: unit,
                    timestamp: Date(),
                    metadata: [
                        "test": testName,
                        "suite": ""
                    ],
                    projectName: projectName
                )
                
                metrics.append(metric)
                logger.info("Parsed performance metric: \(metricType) = \(averageValue) \(unit) for test \(testName)")
            }
        }
        
        return metrics
    }
}
