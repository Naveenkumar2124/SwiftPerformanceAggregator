import Foundation

public protocol BaseCollector {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    
    func collectMetrics(for projectPath: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void)
    func isAvailable() -> Bool
    func getSupportedMetricTypes() -> [MetricType]
}

// Default implementations
public extension BaseCollector {
    func isAvailable() -> Bool {
        return true
    }
    
    var description: String {
        return "Collects performance metrics from \(name)"
    }
}

public enum CollectorError: Error, LocalizedError {
    case executionFailed(String)
    case dataParsingFailed(String)
    case toolNotFound(String)
    case unsupportedProject(String)
    case timeout(String)
    
    public var errorDescription: String? {
        switch self {
        case .executionFailed(let details):
            return "Execution failed: \(details)"
        case .dataParsingFailed(let details):
            return "Failed to parse data: \(details)"
        case .toolNotFound(let tool):
            return "Required tool not found: \(tool)"
        case .unsupportedProject(let reason):
            return "Unsupported project: \(reason)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        }
    }
}
