import Foundation

public enum MetricSource: String, Codable, Sendable {
    case instruments
    case xctest
    case metricKit
    case buildTime
    case custom
    
    public var displayName: String {
        switch self {
        case .instruments: return "Instruments"
        case .xctest: return "XCTest"
        case .metricKit: return "MetricKit"
        case .buildTime: return "Build Time"
        case .custom: return "Custom"
        }
    }
}

public enum MetricType: String, Codable, Sendable {
    case cpuTime
    case memoryUsage
    case diskIO
    case networkLatency
    case buildDuration
    case startupTime
    case frameRate
    case energyImpact
    case custom
    
    public var displayName: String {
        switch self {
        case .cpuTime: return "CPU Time"
        case .memoryUsage: return "Memory Usage"
        case .diskIO: return "Disk I/O"
        case .networkLatency: return "Network Latency"
        case .buildDuration: return "Build Duration"
        case .startupTime: return "Startup Time"
        case .frameRate: return "Frame Rate"
        case .energyImpact: return "Energy Impact"
        case .custom: return "Custom"
        }
    }
    
    public var defaultUnit: String {
        switch self {
        case .cpuTime: return "seconds"
        case .memoryUsage: return "MB"
        case .diskIO: return "MB/s"
        case .networkLatency: return "ms"
        case .buildDuration: return "seconds"
        case .startupTime: return "seconds"
        case .frameRate: return "fps"
        case .energyImpact: return "mAh"
        case .custom: return ""
        }
    }
}

import Vapor

public struct PerformanceMetric: Codable, Identifiable, Equatable, Content {
    public let id: UUID
    public let source: MetricSource
    public let type: MetricType
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let metadata: [String: String]
    
    // File and location information
    public let filePath: String?
    public let functionName: String?
    public let lineNumber: Int?
    
    // Commit information if available
    public let commitHash: String?
    public let branchName: String?
    public let projectName: String
    
    // Custom source and type names for when using .custom
    public let customSourceName: String?
    public let customTypeName: String?
    
    public init(
        id: UUID = UUID(),
        source: MetricSource,
        type: MetricType,
        value: Double,
        unit: String? = nil,
        timestamp: Date = Date(),
        metadata: [String: String] = [:],
        filePath: String? = nil,
        functionName: String? = nil,
        lineNumber: Int? = nil,
        commitHash: String? = nil,
        branchName: String? = nil,
        projectName: String,
        customSourceName: String? = nil,
        customTypeName: String? = nil
    ) {
        self.id = id
        self.source = source
        self.type = type
        self.value = value
        self.unit = unit ?? type.defaultUnit
        self.timestamp = timestamp
        self.metadata = metadata
        self.filePath = filePath
        self.functionName = functionName
        self.lineNumber = lineNumber
        self.commitHash = commitHash
        self.branchName = branchName
        self.projectName = projectName
        self.customSourceName = customSourceName
        self.customTypeName = customTypeName
    }
    
    public static func == (lhs: PerformanceMetric, rhs: PerformanceMetric) -> Bool {
        return lhs.id == rhs.id
    }
    
    public var displaySource: String {
        if source == .custom, let customName = customSourceName {
            return customName
        }
        return source.displayName
    }
    
    public var displayType: String {
        if type == .custom, let customName = customTypeName {
            return customName
        }
        return type.displayName
    }
    
    public var displayValue: String {
        return "\(String(format: "%.2f", value)) \(unit)"
    }
}

public struct PerformanceReport: Codable, Content {
    public let projectName: String
    public let metrics: [PerformanceMetric]
    public let generatedAt: Date
    public let baselineComparison: BaselineComparison?
    
    public struct BaselineComparison: Codable, Sendable {
        public let baselineId: String
        public let improvements: [MetricComparison]
        public let regressions: [MetricComparison]
        public let unchanged: [MetricComparison]
        
        public struct MetricComparison: Codable, Sendable {
            public let metricId: UUID
            public let baselineValue: Double
            public let currentValue: Double
            public let percentChange: Double
        }
    }
}
