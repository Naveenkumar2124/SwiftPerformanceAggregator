import Foundation
import SwiftUI

// Chart component models for visualization in Windsurf UI
public struct ChartData: Codable, Sendable {
    public let chartType: ChartType
    public let title: String
    public let subtitle: String?
    public let data: [DataPoint]
    public let xAxisLabel: String?
    public let yAxisLabel: String?
    public let series: [Series]
    
    public init(
        chartType: ChartType,
        title: String,
        subtitle: String? = nil,
        data: [DataPoint] = [],
        xAxisLabel: String? = nil,
        yAxisLabel: String? = nil,
        series: [Series] = []
    ) {
        self.chartType = chartType
        self.title = title
        self.subtitle = subtitle
        self.data = data
        self.xAxisLabel = xAxisLabel
        self.yAxisLabel = yAxisLabel
        self.series = series
    }
    
    public enum ChartType: String, Codable, Sendable {
        case line
        case bar
        case scatter
        case pie
        case heatmap
        case timeline
    }
    
    public struct DataPoint: Codable, Identifiable, Sendable {
        public let id: UUID
        public let x: Double
        public let y: Double
        public let label: String?
        public let category: String?
        public let color: String?
        
        public init(
            id: UUID = UUID(),
            x: Double,
            y: Double,
            label: String? = nil,
            category: String? = nil,
            color: String? = nil
        ) {
            self.id = id
            self.x = x
            self.y = y
            self.label = label
            self.category = category
            self.color = color
        }
    }
    
    public struct Series: Codable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let data: [DataPoint]
        public let color: String?
        
        public init(
            id: UUID = UUID(),
            name: String,
            data: [DataPoint],
            color: String? = nil
        ) {
            self.id = id
            self.name = name
            self.data = data
            self.color = color
        }
    }
}

// Chart factory to create different chart types from performance metrics
public class ChartFactory {
    public static func createTimelineChart(
        metrics: [PerformanceMetric],
        title: String,
        subtitle: String? = nil
    ) -> ChartData {
        // Group metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type }
        
        // Create series for each metric type
        var series: [ChartData.Series] = []
        
        for (type, typeMetrics) in metricsByType {
            // Sort metrics by timestamp
            let sortedMetrics = typeMetrics.sorted { $0.timestamp < $1.timestamp }
            
            // Create data points
            let dataPoints = sortedMetrics.map { metric in
                ChartData.DataPoint(
                    x: metric.timestamp.timeIntervalSince1970,
                    y: metric.value,
                    label: "\(metric.displayType): \(metric.displayValue)",
                    category: metric.displayType
                )
            }
            
            // Add series
            series.append(ChartData.Series(
                name: type.displayName,
                data: dataPoints,
                color: colorForMetricType(type)
            ))
        }
        
        return ChartData(
            chartType: .line,
            title: title,
            subtitle: subtitle,
            xAxisLabel: "Time",
            yAxisLabel: "Value",
            series: series
        )
    }
    
    public static func createComparisonChart(
        baselineMetrics: [PerformanceMetric],
        currentMetrics: [PerformanceMetric],
        title: String,
        subtitle: String? = nil
    ) -> ChartData {
        // Group metrics by type
        let baselineByType = Dictionary(grouping: baselineMetrics) { $0.type }
        let currentByType = Dictionary(grouping: currentMetrics) { $0.type }
        
        // Create data points for comparison
        var dataPoints: [ChartData.DataPoint] = []
        
        // Get all metric types
        let allTypes = Set(baselineByType.keys).union(currentByType.keys)
        
        for type in allTypes {
            // Calculate average values
            let baselineAvg = baselineByType[type]?.map { $0.value }.reduce(0, +) ?? 0
            let baselineCount = baselineByType[type]?.count ?? 1
            let baselineValue = baselineAvg / Double(baselineCount)
            
            let currentAvg = currentByType[type]?.map { $0.value }.reduce(0, +) ?? 0
            let currentCount = currentByType[type]?.count ?? 1
            let currentValue = currentAvg / Double(currentCount)
            
            // Calculate percent change
            let percentChange = baselineValue > 0 ? ((currentValue - baselineValue) / baselineValue) * 100 : 0
            
            // Add data point
            dataPoints.append(ChartData.DataPoint(
                x: 0, // x position for bar chart
                y: percentChange,
                label: "\(type.displayName): \(String(format: "%.2f%%", percentChange))",
                category: type.displayName,
                color: percentChange > 0 ? "#FF4136" : "#2ECC40" // Red for regression, green for improvement
            ))
        }
        
        return ChartData(
            chartType: .bar,
            title: title,
            subtitle: subtitle,
            data: dataPoints,
            xAxisLabel: "Metric Type",
            yAxisLabel: "Percent Change (%)"
        )
    }
    
    public static func createHeatmapChart(
        metrics: [PerformanceMetric],
        title: String,
        subtitle: String? = nil
    ) -> ChartData {
        // Filter metrics with file paths
        let metricsWithPaths = metrics.filter { $0.filePath != nil }
        
        // Group by file path
        let metricsByFile = Dictionary(grouping: metricsWithPaths) { $0.filePath! }
        
        // Create data points
        var dataPoints: [ChartData.DataPoint] = []
        
        for (filePath, fileMetrics) in metricsByFile {
            // Calculate average value for this file
            let avgValue = fileMetrics.map { $0.value }.reduce(0, +) / Double(fileMetrics.count)
            
            // Add data point
            dataPoints.append(ChartData.DataPoint(
                x: Double(dataPoints.count), // Position in heatmap
                y: avgValue,
                label: URL(fileURLWithPath: filePath).lastPathComponent,
                category: fileMetrics.first?.type.displayName ?? "Unknown"
            ))
        }
        
        return ChartData(
            chartType: .heatmap,
            title: title,
            subtitle: subtitle,
            data: dataPoints,
            xAxisLabel: "File",
            yAxisLabel: "Performance Impact"
        )
    }
    
    // Helper function to assign colors to metric types
    private static func colorForMetricType(_ type: MetricType) -> String {
        switch type {
        case .cpuTime:
            return "#FF4136" // Red
        case .memoryUsage:
            return "#0074D9" // Blue
        case .diskIO:
            return "#2ECC40" // Green
        case .networkLatency:
            return "#FF851B" // Orange
        case .buildDuration:
            return "#B10DC9" // Purple
        case .startupTime:
            return "#FFDC00" // Yellow
        case .frameRate:
            return "#01FF70" // Lime
        case .energyImpact:
            return "#F012BE" // Fuchsia
        case .custom:
            return "#AAAAAA" // Gray
        }
    }
}

// JSON encoder/decoder extensions for chart data
public extension ChartData {
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    static func fromJSON(_ json: String) -> ChartData? {
        guard let data = json.data(using: .utf8) else { return nil }
        
        let decoder = JSONDecoder()
        
        do {
            return try decoder.decode(ChartData.self, from: data)
        } catch {
            return nil
        }
    }
}
