import Foundation
import SwiftUI

// Dashboard view models for Windsurf UI integration
public struct DashboardViewModel: Codable {
    public let projectName: String
    public let timeRange: TimeRange
    public let charts: [ChartData]
    public let metrics: [PerformanceMetric]
    public let summary: DashboardSummary
    
    public init(
        projectName: String,
        timeRange: TimeRange,
        charts: [ChartData],
        metrics: [PerformanceMetric],
        summary: DashboardSummary
    ) {
        self.projectName = projectName
        self.timeRange = timeRange
        self.charts = charts
        self.metrics = metrics
        self.summary = summary
    }
    
    // Generate dashboard view model from performance metrics
    public static func from(
        metrics: [PerformanceMetric],
        projectName: String,
        timeRange: TimeRange
    ) -> DashboardViewModel {
        // Create summary
        let summary = DashboardSummary.from(metrics: metrics)
        
        // Create charts
        var charts: [ChartData] = []
        
        // Timeline chart
        charts.append(ChartFactory.createTimelineChart(
            metrics: metrics,
            title: "Performance Metrics Timeline",
            subtitle: "Last \(Calendar.current.dateComponents([.day], from: timeRange.start, to: timeRange.end).day ?? 0) days"
        ))
        
        // Heatmap chart (if we have file paths)
        if metrics.contains(where: { $0.filePath != nil }) {
            charts.append(ChartFactory.createHeatmapChart(
                metrics: metrics,
                title: "Performance Hotspots",
                subtitle: "Files with highest performance impact"
            ))
        }
        
        // Comparison chart (if we have commit hashes)
        if let baselineCommit = metrics.first?.commitHash,
           let latestCommit = metrics.last?.commitHash,
           baselineCommit != latestCommit {
            
            let baselineMetrics = metrics.filter { $0.commitHash == baselineCommit }
            let latestMetrics = metrics.filter { $0.commitHash == latestCommit }
            
            charts.append(ChartFactory.createComparisonChart(
                baselineMetrics: baselineMetrics,
                currentMetrics: latestMetrics,
                title: "Performance Change",
                subtitle: "Comparing \(baselineCommit.prefix(7)) to \(latestCommit.prefix(7))"
            ))
        }
        
        return DashboardViewModel(
            projectName: projectName,
            timeRange: timeRange,
            charts: charts,
            metrics: metrics,
            summary: summary
        )
    }
    
    // Convert to JSON for API responses
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

// Summary of performance metrics for dashboard
public struct DashboardSummary: Codable {
    public let totalMetrics: Int
    public let metricsByType: [String: Int]
    public let averageValues: [String: Double]
    public let trendIndicators: [String: TrendIndicator]
    public let alerts: [PerformanceAlert]
    
    public enum TrendIndicator: String, Codable {
        case improving
        case stable
        case degrading
        case unknown
    }
    
    public struct PerformanceAlert: Codable, Identifiable {
        public let id: UUID
        public let title: String
        public let description: String
        public let severity: Severity
        public let metricType: String
        public let value: Double
        public let threshold: Double
        public let timestamp: Date
        
        public enum Severity: String, Codable {
            case info
            case warning
            case critical
        }
        
        public init(
            id: UUID = UUID(),
            title: String,
            description: String,
            severity: Severity,
            metricType: String,
            value: Double,
            threshold: Double,
            timestamp: Date
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.severity = severity
            self.metricType = metricType
            self.value = value
            self.threshold = threshold
            self.timestamp = timestamp
        }
    }
    
    public init(
        totalMetrics: Int,
        metricsByType: [String: Int],
        averageValues: [String: Double],
        trendIndicators: [String: TrendIndicator],
        alerts: [PerformanceAlert]
    ) {
        self.totalMetrics = totalMetrics
        self.metricsByType = metricsByType
        self.averageValues = averageValues
        self.trendIndicators = trendIndicators
        self.alerts = alerts
    }
    
    // Generate summary from performance metrics
    public static func from(metrics: [PerformanceMetric]) -> DashboardSummary {
        // Total metrics
        let totalMetrics = metrics.count
        
        // Metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type.displayName }
            .mapValues { $0.count }
        
        // Average values by type
        var averageValues: [String: Double] = [:]
        for (type, typeMetrics) in Dictionary(grouping: metrics, by: { $0.type.displayName }) {
            let sum = typeMetrics.map { $0.value }.reduce(0, +)
            averageValues[type] = sum / Double(typeMetrics.count)
        }
        
        // Trend indicators
        var trendIndicators: [String: TrendIndicator] = [:]
        
        // Sort metrics by timestamp
        let sortedMetrics = metrics.sorted { $0.timestamp < $1.timestamp }
        
        // Split into first half and second half to determine trend
        if sortedMetrics.count >= 4 {
            let midpoint = sortedMetrics.count / 2
            let firstHalf = Array(sortedMetrics[0..<midpoint])
            let secondHalf = Array(sortedMetrics[midpoint...])
            
            // Calculate trends for each metric type
            for (type, _) in metricsByType {
                let firstHalfOfType = firstHalf.filter { $0.type.displayName == type }
                let secondHalfOfType = secondHalf.filter { $0.type.displayName == type }
                
                if !firstHalfOfType.isEmpty && !secondHalfOfType.isEmpty {
                    let firstAvg = firstHalfOfType.map { $0.value }.reduce(0, +) / Double(firstHalfOfType.count)
                    let secondAvg = secondHalfOfType.map { $0.value }.reduce(0, +) / Double(secondHalfOfType.count)
                    
                    // Determine trend (assuming lower values are better for most metrics)
                    let percentChange = ((secondAvg - firstAvg) / firstAvg) * 100
                    
                    if abs(percentChange) < 5 {
                        trendIndicators[type] = .stable
                    } else if percentChange < 0 {
                        trendIndicators[type] = .improving
                    } else {
                        trendIndicators[type] = .degrading
                    }
                } else {
                    trendIndicators[type] = .unknown
                }
            }
        } else {
            // Not enough data for trend analysis
            for (type, _) in metricsByType {
                trendIndicators[type] = .unknown
            }
        }
        
        // Generate alerts
        var alerts: [PerformanceAlert] = []
        
        // Check for performance regressions
        for (type, indicator) in trendIndicators {
            if indicator == .degrading {
                if let value = averageValues[type] {
                    alerts.append(PerformanceAlert(
                        title: "\(type) Performance Degradation",
                        description: "\(type) metrics show a degrading trend",
                        severity: .warning,
                        metricType: type,
                        value: value,
                        threshold: 0, // No specific threshold for trend-based alerts
                        timestamp: Date()
                    ))
                }
            }
        }
        
        // Check for outliers (values more than 2 standard deviations from mean)
        for (type, typeMetrics) in Dictionary(grouping: metrics, by: { $0.type.displayName }) {
            let values = typeMetrics.map { $0.value }
            let mean = values.reduce(0, +) / Double(values.count)
            
            // Calculate standard deviation
            let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
            let stdDev = sqrt(variance)
            
            // Find outliers
            for metric in typeMetrics {
                if abs(metric.value - mean) > (2 * stdDev) {
                    alerts.append(PerformanceAlert(
                        title: "Outlier \(type) Value",
                        description: "Detected an unusual \(type) value of \(metric.displayValue)",
                        severity: .info,
                        metricType: type,
                        value: metric.value,
                        threshold: mean + (2 * stdDev),
                        timestamp: metric.timestamp
                    ))
                }
            }
        }
        
        return DashboardSummary(
            totalMetrics: totalMetrics,
            metricsByType: metricsByType,
            averageValues: averageValues,
            trendIndicators: trendIndicators,
            alerts: alerts
        )
    }
}

// Dashboard configuration for customizing the Windsurf UI integration
public struct DashboardConfiguration: Codable {
    public let refreshInterval: Int // in seconds
    public let defaultTimeRange: TimeRange
    public let enabledCharts: [String]
    public let thresholds: [MetricThreshold]
    
    public struct MetricThreshold: Codable {
        public let metricType: String
        public let warningThreshold: Double
        public let criticalThreshold: Double
        public let unit: String
        
        public init(
            metricType: String,
            warningThreshold: Double,
            criticalThreshold: Double,
            unit: String
        ) {
            self.metricType = metricType
            self.warningThreshold = warningThreshold
            self.criticalThreshold = criticalThreshold
            self.unit = unit
        }
    }
    
    public init(
        refreshInterval: Int = 300,
        defaultTimeRange: TimeRange = TimeRange.last(days: 7),
        enabledCharts: [String] = ["timeline", "heatmap", "comparison"],
        thresholds: [MetricThreshold] = []
    ) {
        self.refreshInterval = refreshInterval
        self.defaultTimeRange = defaultTimeRange
        self.enabledCharts = enabledCharts
        self.thresholds = thresholds
    }
    
    // Default configuration with common thresholds
    public static func defaultConfiguration() -> DashboardConfiguration {
        return DashboardConfiguration(
            thresholds: [
                MetricThreshold(
                    metricType: "CPU Time",
                    warningThreshold: 1.0,
                    criticalThreshold: 2.0,
                    unit: "seconds"
                ),
                MetricThreshold(
                    metricType: "Memory Usage",
                    warningThreshold: 200.0,
                    criticalThreshold: 500.0,
                    unit: "MB"
                ),
                MetricThreshold(
                    metricType: "Startup Time",
                    warningThreshold: 2.0,
                    criticalThreshold: 5.0,
                    unit: "seconds"
                )
            ]
        )
    }
}
