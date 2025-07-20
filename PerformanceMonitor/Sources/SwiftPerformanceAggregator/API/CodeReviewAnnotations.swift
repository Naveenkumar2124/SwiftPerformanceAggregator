import Foundation
import Logging

/// Handles the generation of code review annotations based on performance metrics
public class CodeReviewAnnotations {
    private let logger = Logger(label: "com.windsurf.code-review-annotations")
    private let storage: MetricsStorage
    
    public init(storage: MetricsStorage) {
        self.storage = storage
    }
    
    /// Generate annotations for a code review
    public func generateAnnotations(
        for filePaths: [String],
        projectName: String,
        commitHash: String?,
        completion: @escaping (Result<[CodeAnnotation], Error>) -> Void
    ) {
        logger.info("Generating annotations for \(filePaths.count) files in project \(projectName)")
        
        // Get metrics for the files
        let timeRange = TimeRange.last(days: 30) // Look at recent metrics
        
        storage.retrieveMetrics(for: projectName, timeRange: timeRange) { [weak self] result in
            guard let self = self else {
                completion(.failure(StorageError.storageFailure("CodeReviewAnnotations instance was deallocated")))
                return
            }
            
            switch result {
            case .success(let allMetrics):
                // Filter metrics for the specific commit if provided
                let metrics = commitHash != nil ? 
                    allMetrics.filter { $0.commitHash == commitHash } : 
                    allMetrics
                
                // Filter metrics for the specified files
                let relevantMetrics = metrics.filter { metric in
                    if let filePath = metric.filePath {
                        return filePaths.contains { path in
                            filePath.contains(path)
                        }
                    }
                    return false
                }
                
                if relevantMetrics.isEmpty {
                    self.logger.warning("No relevant metrics found for the specified files")
                    completion(.success([]))
                    return
                }
                
                // Generate annotations
                let annotations = self.createAnnotations(from: relevantMetrics)
                self.logger.info("Generated \(annotations.count) annotations")
                completion(.success(annotations))
                
            case .failure(let error):
                self.logger.error("Failed to retrieve metrics: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Create code annotations from performance metrics
    private func createAnnotations(from metrics: [PerformanceMetric]) -> [CodeAnnotation] {
        var annotations: [CodeAnnotation] = []
        
        // Group metrics by file path
        let metricsByFile = Dictionary(grouping: metrics) { $0.filePath ?? "unknown" }
        
        for (filePath, fileMetrics) in metricsByFile {
            // Group by line number if available
            let metricsByLine = Dictionary(grouping: fileMetrics) { $0.lineNumber ?? 0 }
            
            for (lineNumber, lineMetrics) in metricsByLine {
                if lineNumber > 0 {
                    // Create line-specific annotation
                    annotations.append(createLineAnnotation(
                        filePath: filePath,
                        lineNumber: lineNumber,
                        metrics: lineMetrics
                    ))
                }
            }
            
            // Create file-level annotation for metrics without line numbers
            let metricsWithoutLines = fileMetrics.filter { $0.lineNumber == nil }
            if !metricsWithoutLines.isEmpty {
                annotations.append(createFileAnnotation(
                    filePath: filePath,
                    metrics: metricsWithoutLines
                ))
            }
        }
        
        return annotations
    }
    
    /// Create an annotation for a specific line
    private func createLineAnnotation(filePath: String, lineNumber: Int, metrics: [PerformanceMetric]) -> CodeAnnotation {
        // Group metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type }
        
        // Create message
        var message = "Performance metrics for this line:\n"
        
        for (type, typeMetrics) in metricsByType {
            let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
            message += "- \(type.displayName): \(String(format: "%.2f", avgValue)) \(typeMetrics.first?.unit ?? "")\n"
        }
        
        // Determine severity based on the metrics
        let severity = determineSeverity(metrics: metrics)
        
        return CodeAnnotation(
            filePath: filePath,
            lineNumber: lineNumber,
            message: message,
            severity: severity,
            metrics: metrics
        )
    }
    
    /// Create an annotation for an entire file
    private func createFileAnnotation(filePath: String, metrics: [PerformanceMetric]) -> CodeAnnotation {
        // Group metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type }
        
        // Create message
        var message = "Performance metrics for this file:\n"
        
        for (type, typeMetrics) in metricsByType {
            let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
            message += "- \(type.displayName): \(String(format: "%.2f", avgValue)) \(typeMetrics.first?.unit ?? "")\n"
        }
        
        // Add recommendations based on the metrics
        let recommendations = generateRecommendations(metrics: metrics)
        if !recommendations.isEmpty {
            message += "\nRecommendations:\n"
            for recommendation in recommendations {
                message += "- \(recommendation)\n"
            }
        }
        
        // Determine severity based on the metrics
        let severity = determineSeverity(metrics: metrics)
        
        return CodeAnnotation(
            filePath: filePath,
            lineNumber: 1, // File-level annotation at the top of the file
            message: message,
            severity: severity,
            metrics: metrics
        )
    }
    
    /// Generate recommendations based on performance metrics
    private func generateRecommendations(metrics: [PerformanceMetric]) -> [String] {
        var recommendations: [String] = []
        
        // Group metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type }
        
        // Check for high CPU time
        if let cpuMetrics = metricsByType[.cpuTime], !cpuMetrics.isEmpty {
            let avgCpuTime = cpuMetrics.map { $0.value }.reduce(0, +) / Double(cpuMetrics.count)
            if avgCpuTime > 0.5 {
                recommendations.append("Consider optimizing CPU-intensive operations")
            }
        }
        
        // Check for high memory usage
        if let memoryMetrics = metricsByType[.memoryUsage], !memoryMetrics.isEmpty {
            let avgMemory = memoryMetrics.map { $0.value }.reduce(0, +) / Double(memoryMetrics.count)
            if avgMemory > 200 {
                recommendations.append("Review memory allocation patterns to reduce usage")
            }
        }
        
        // Check for long build times
        if let buildMetrics = metricsByType[.buildDuration], !buildMetrics.isEmpty {
            let avgBuildTime = buildMetrics.map { $0.value }.reduce(0, +) / Double(buildMetrics.count)
            if avgBuildTime > 5.0 {
                recommendations.append("Consider refactoring to improve compile time")
            }
        }
        
        return recommendations
    }
    
    /// Determine the severity of an annotation based on metrics
    private func determineSeverity(metrics: [PerformanceMetric]) -> CodeAnnotation.Severity {
        // Check for concerning metrics
        for metric in metrics {
            switch metric.type {
            case .cpuTime:
                if metric.value > 1.0 {
                    return .warning
                }
            case .memoryUsage:
                if metric.value > 300 {
                    return .warning
                }
            case .buildDuration:
                if metric.value > 10.0 {
                    return .warning
                }
            default:
                break
            }
        }
        
        return .info
    }
}

/// Represents an annotation in a code review
import Vapor

public struct CodeAnnotation: Codable, Content {
    public let filePath: String
    public let lineNumber: Int
    public let message: String
    public let severity: Severity
    public let metrics: [PerformanceMetric]
    
    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }
    
    public init(
        filePath: String,
        lineNumber: Int,
        message: String,
        severity: Severity,
        metrics: [PerformanceMetric]
    ) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.message = message
        self.severity = severity
        self.metrics = metrics
    }
}
