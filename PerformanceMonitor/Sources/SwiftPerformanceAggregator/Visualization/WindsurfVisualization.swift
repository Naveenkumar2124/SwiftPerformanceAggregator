import Foundation
import SwiftUI

/// Visualization components specifically designed for Windsurf UI integration
public struct WindsurfVisualization {
    /// Generate visualization components for Windsurf UI
    public static func generateVisualizationData(
        metrics: [PerformanceMetric],
        codeReviewInsights: CodeReviewInsights? = nil
    ) -> WindsurfVisualizationData {
        // Create timeline chart
        let timelineChart = ChartFactory.createTimelineChart(
            metrics: metrics,
            title: "Performance Metrics Timeline"
        )
        
        // Create metric cards
        let metricCards = createMetricCards(metrics: metrics)
        
        // Create file impact visualization if we have code review insights
        let fileImpactData = codeReviewInsights.map { createFileImpactData(insights: $0) }
        
        // Create recommendations
        let recommendations = codeReviewInsights?.recommendations ?? []
        
        return WindsurfVisualizationData(
            charts: [timelineChart],
            metricCards: metricCards,
            fileImpactData: fileImpactData,
            recommendations: recommendations
        )
    }
    
    /// Create metric cards for key performance indicators
    private static func createMetricCards(metrics: [PerformanceMetric]) -> [MetricCard] {
        // Group metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type }
        
        var cards: [MetricCard] = []
        
        // Create a card for each metric type
        for (type, typeMetrics) in metricsByType {
            // Calculate average value
            let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
            
            // Calculate trend
            let trend: MetricCard.Trend
            
            if typeMetrics.count >= 2 {
                // Sort by timestamp
                let sortedMetrics = typeMetrics.sorted { $0.timestamp < $1.timestamp }
                
                // Split into first half and second half
                let midpoint = sortedMetrics.count / 2
                let firstHalf = Array(sortedMetrics[0..<midpoint])
                let secondHalf = Array(sortedMetrics[midpoint...])
                
                // Calculate averages for each half
                let firstAvg = firstHalf.map { $0.value }.reduce(0, +) / Double(firstHalf.count)
                let secondAvg = secondHalf.map { $0.value }.reduce(0, +) / Double(secondHalf.count)
                
                // Calculate percent change
                let percentChange = ((secondAvg - firstAvg) / firstAvg) * 100
                
                // Determine trend (assuming lower values are better for most metrics)
                if abs(percentChange) < 5 {
                    trend = .stable
                } else if percentChange < 0 {
                    trend = .improving
                } else {
                    trend = .degrading
                }
            } else {
                trend = .unknown
            }
            
            // Create card
            cards.append(MetricCard(
                title: type.displayName,
                value: avgValue,
                unit: typeMetrics.first?.unit ?? "",
                trend: trend,
                samples: typeMetrics.count
            ))
        }
        
        return cards
    }
    
    /// Create file impact visualization data from code review insights
    private static func createFileImpactData(insights: CodeReviewInsights) -> FileImpactData {
        var fileImpacts: [FileImpactData.FileImpact] = []
        
        for fileInsight in insights.fileInsights {
            // Create impact data for each file
            fileImpacts.append(FileImpactData.FileImpact(
                filePath: fileInsight.filePath,
                fileName: URL(fileURLWithPath: fileInsight.filePath).lastPathComponent,
                impactLevel: impactLevelFromPerformanceImpact(fileInsight.overallImpact),
                metrics: fileInsight.metrics.map { metric in
                    FileImpactData.MetricImpact(
                        name: metric.metricType,
                        value: metric.value,
                        unit: metric.unit,
                        impactLevel: impactLevelFromPerformanceImpact(metric.impact)
                    )
                }
            ))
        }
        
        return FileImpactData(
            reviewId: insights.reviewId,
            commitHash: insights.commitHash,
            files: fileImpacts,
            dataSource: insights.dataSource.rawValue
        )
    }
    
    /// Convert performance impact to impact level
    private static func impactLevelFromPerformanceImpact(_ impact: CodeReviewInsights.PerformanceImpact) -> FileImpactData.ImpactLevel {
        switch impact {
        case .good:
            return .low
        case .neutral:
            return .medium
        case .concerning:
            return .high
        }
    }
}

/// Data structure for Windsurf UI visualization
public struct WindsurfVisualizationData: Codable, Sendable {
    public let charts: [ChartData]
    public let metricCards: [MetricCard]
    public let fileImpactData: FileImpactData?
    public let recommendations: [String]
    
    public init(
        charts: [ChartData],
        metricCards: [MetricCard],
        fileImpactData: FileImpactData?,
        recommendations: [String]
    ) {
        self.charts = charts
        self.metricCards = metricCards
        self.fileImpactData = fileImpactData
        self.recommendations = recommendations
    }
    
    /// Convert to JSON for API responses
    public func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// Metric card for displaying key performance indicators
public struct MetricCard: Codable, Sendable {
    public let title: String
    public let value: Double
    public let unit: String
    public let trend: Trend
    public let samples: Int
    
    public enum Trend: String, Codable, Sendable {
        case improving
        case stable
        case degrading
        case unknown
    }
    
    public init(
        title: String,
        value: Double,
        unit: String,
        trend: Trend,
        samples: Int
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.trend = trend
        self.samples = samples
    }
}

/// File impact visualization data
public struct FileImpactData: Codable, Sendable {
    public let reviewId: String
    public let commitHash: String
    public let files: [FileImpact]
    public let dataSource: String
    
    public enum ImpactLevel: String, Codable, Sendable {
        case low
        case medium
        case high
    }
    
    public struct FileImpact: Codable, Sendable {
        public let filePath: String
        public let fileName: String
        public let impactLevel: ImpactLevel
        public let metrics: [MetricImpact]
    }
    
    public struct MetricImpact: Codable, Sendable {
        public let name: String
        public let value: Double
        public let unit: String
        public let impactLevel: ImpactLevel
    }
}
