import Foundation
import Logging

/// Handles the integration of performance metrics with code review systems
public class CodeReviewIntegration {
    private let logger = Logger(label: "com.windsurf.code-review-integration")
    private let storage: MetricsStorage
    private let configuration: Configuration
    
    public init(storage: MetricsStorage, configuration: Configuration) {
        self.storage = storage
        self.configuration = configuration
        logger.info("Initialized CodeReviewIntegration for project: \(configuration.projectName)")
    }
    
    /// Process a code review event and generate performance insights
    public func processCodeReviewEvent(reviewId: String, commitHash: String, filePaths: [String], completion: @escaping (Result<CodeReviewInsights, Error>) -> Void) {
        logger.info("Processing code review #\(reviewId) for commit \(commitHash)")
        
        // Get metrics for this commit
        storage.retrieveMetricsForCommit(commitHash, projectName: configuration.projectName) { [weak self] result in
            guard let self = self else {
                completion(.failure(CodeReviewError.processingFailed("CodeReviewIntegration instance was deallocated")))
                return
            }
            
            switch result {
            case .success(let commitMetrics):
                if commitMetrics.isEmpty {
                    self.logger.warning("No metrics found for commit \(commitHash)")
                    
                    // Try to find metrics for the most recent commit
                    self.findRecentMetrics(completion: { recentResult in
                        switch recentResult {
                        case .success(let recentMetrics):
                            // Generate insights with a note that they're from a different commit
                            let insights = self.generateInsights(
                                reviewId: reviewId,
                                commitHash: commitHash,
                                filePaths: filePaths,
                                metrics: recentMetrics,
                                isFromDifferentCommit: true
                            )
                            completion(.success(insights))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    })
                } else {
                    // Generate insights from the commit metrics
                    let insights = self.generateInsights(
                        reviewId: reviewId,
                        commitHash: commitHash,
                        filePaths: filePaths,
                        metrics: commitMetrics,
                        isFromDifferentCommit: false
                    )
                    completion(.success(insights))
                }
            case .failure(let error):
                self.logger.error("Error retrieving metrics for commit \(commitHash): \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Find metrics from recent commits if no metrics are available for the current commit
    private func findRecentMetrics(completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        storage.retrieveLatestMetrics(for: configuration.projectName, limit: 50) { result in
            switch result {
            case .success(let metrics):
                if metrics.isEmpty {
                    completion(.failure(CodeReviewError.noMetricsAvailable))
                } else {
                    completion(.success(metrics))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Generate insights from performance metrics
    private func generateInsights(reviewId: String, commitHash: String, filePaths: [String], metrics: [PerformanceMetric], isFromDifferentCommit: Bool) -> CodeReviewInsights {
        // Filter metrics relevant to the files in the review
        let relevantMetrics = metrics.filter { metric in
            if let filePath = metric.filePath {
                return filePaths.contains { reviewPath in
                    filePath.contains(reviewPath)
                }
            }
            return false
        }
        
        // Group metrics by file
        let metricsByFile = Dictionary(grouping: relevantMetrics) { $0.filePath ?? "unknown" }
        
        // Create file insights
        var fileInsights: [CodeReviewInsights.FileInsight] = []
        
        for (filePath, fileMetrics) in metricsByFile {
            let metricsByType = Dictionary(grouping: fileMetrics) { $0.type }
            
            var typeInsights: [CodeReviewInsights.MetricTypeInsight] = []
            
            for (type, typeMetrics) in metricsByType {
                let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
                
                typeInsights.append(CodeReviewInsights.MetricTypeInsight(
                    metricType: type.displayName,
                    value: avgValue,
                    unit: typeMetrics.first?.unit ?? "",
                    impact: determinePerformanceImpact(type: type, value: avgValue)
                ))
            }
            
            fileInsights.append(CodeReviewInsights.FileInsight(
                filePath: filePath,
                metrics: typeInsights,
                overallImpact: determineOverallImpact(typeInsights)
            ))
        }
        
        // Create overall project metrics
        let overallMetrics = metrics.filter { $0.filePath == nil }
        let overallMetricsByType = Dictionary(grouping: overallMetrics) { $0.type }
        
        var overallTypeInsights: [CodeReviewInsights.MetricTypeInsight] = []
        
        for (type, typeMetrics) in overallMetricsByType {
            let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
            
            overallTypeInsights.append(CodeReviewInsights.MetricTypeInsight(
                metricType: type.displayName,
                value: avgValue,
                unit: typeMetrics.first?.unit ?? "",
                impact: determinePerformanceImpact(type: type, value: avgValue)
            ))
        }
        
        // Generate recommendations
        let recommendations = generateRecommendations(fileInsights: fileInsights, overallInsights: overallTypeInsights)
        
        return CodeReviewInsights(
            reviewId: reviewId,
            commitHash: commitHash,
            timestamp: Date(),
            fileInsights: fileInsights,
            overallMetrics: overallTypeInsights,
            recommendations: recommendations,
            dataSource: isFromDifferentCommit ? .historical : .currentCommit
        )
    }
    
    /// Determine the performance impact of a metric
    private func determinePerformanceImpact(type: MetricType, value: Double) -> CodeReviewInsights.PerformanceImpact {
        // In a real implementation, this would compare against historical data
        // and thresholds to determine if this is good, neutral, or concerning
        
        // For this example, we'll use some reasonable defaults
        switch type {
        case .cpuTime:
            if value < 0.1 {
                return .good
            } else if value < 0.5 {
                return .neutral
            } else {
                return .concerning
            }
            
        case .memoryUsage:
            if value < 50 {
                return .good
            } else if value < 200 {
                return .neutral
            } else {
                return .concerning
            }
            
        case .buildDuration:
            if value < 1.0 {
                return .good
            } else if value < 5.0 {
                return .neutral
            } else {
                return .concerning
            }
            
        case .startupTime:
            if value < 0.5 {
                return .good
            } else if value < 2.0 {
                return .neutral
            } else {
                return .concerning
            }
            
        default:
            return .neutral
        }
    }
    
    /// Determine the overall impact of multiple metrics
    private func determineOverallImpact(_ insights: [CodeReviewInsights.MetricTypeInsight]) -> CodeReviewInsights.PerformanceImpact {
        if insights.isEmpty {
            return .neutral
        }
        
        let concerningCount = insights.filter { $0.impact == .concerning }.count
        let goodCount = insights.filter { $0.impact == .good }.count
        
        if concerningCount > 0 {
            return .concerning
        } else if goodCount > 0 {
            return .good
        } else {
            return .neutral
        }
    }
    
    /// Generate recommendations based on insights
    private func generateRecommendations(fileInsights: [CodeReviewInsights.FileInsight], overallInsights: [CodeReviewInsights.MetricTypeInsight]) -> [String] {
        var recommendations: [String] = []
        
        // Check for concerning file insights
        let concerningFiles = fileInsights.filter { $0.overallImpact == .concerning }
        if !concerningFiles.isEmpty {
            for file in concerningFiles {
                let concerningMetrics = file.metrics.filter { $0.impact == .concerning }
                for metric in concerningMetrics {
                    switch metric.metricType {
                    case "CPU Time":
                        recommendations.append("Consider optimizing CPU usage in \(URL(fileURLWithPath: file.filePath).lastPathComponent)")
                    case "Memory Usage":
                        recommendations.append("Review memory allocation patterns in \(URL(fileURLWithPath: file.filePath).lastPathComponent)")
                    case "Build Duration":
                        recommendations.append("Check for complex templates or large inline functions in \(URL(fileURLWithPath: file.filePath).lastPathComponent)")
                    default:
                        recommendations.append("Review \(metric.metricType.lowercased()) performance in \(URL(fileURLWithPath: file.filePath).lastPathComponent)")
                    }
                }
            }
        }
        
        // Check for concerning overall insights
        let concerningOverall = overallInsights.filter { $0.impact == .concerning }
        if !concerningOverall.isEmpty {
            for metric in concerningOverall {
                switch metric.metricType {
                case "Startup Time":
                    recommendations.append("Consider optimizing app launch sequence to improve startup time")
                case "Energy Impact":
                    recommendations.append("Review background processing and network activity to reduce energy impact")
                default:
                    recommendations.append("Consider overall \(metric.metricType.lowercased()) optimizations")
                }
            }
        }
        
        // If no specific recommendations, provide general guidance
        if recommendations.isEmpty && !fileInsights.isEmpty {
            recommendations.append("No significant performance concerns detected in this code review")
        }
        
        return recommendations
    }
}

/// Insights generated from performance metrics for code reviews
public struct CodeReviewInsights: Codable {
    public let reviewId: String
    public let commitHash: String
    public let timestamp: Date
    public let fileInsights: [FileInsight]
    public let overallMetrics: [MetricTypeInsight]
    public let recommendations: [String]
    public let dataSource: DataSource
    
    public enum DataSource: String, Codable {
        case currentCommit
        case historical
    }
    
    public enum PerformanceImpact: String, Codable {
        case good
        case neutral
        case concerning
    }
    
    public struct FileInsight: Codable {
        public let filePath: String
        public let metrics: [MetricTypeInsight]
        public let overallImpact: PerformanceImpact
    }
    
    public struct MetricTypeInsight: Codable {
        public let metricType: String
        public let value: Double
        public let unit: String
        public let impact: PerformanceImpact
    }
}

public enum CodeReviewError: Error {
    case noMetricsAvailable
    case processingFailed(String)
}
