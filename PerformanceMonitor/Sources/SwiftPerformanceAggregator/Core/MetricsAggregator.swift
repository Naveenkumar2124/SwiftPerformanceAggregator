import Foundation
import Logging

public class MetricsAggregator {
    private let logger = Logger(label: "com.windsurf.metrics-aggregator")
    private var collectors: [BaseCollector] = []
    public let storage: MetricsStorage
    private let configuration: Configuration
    
    public init(configuration: Configuration, storage: MetricsStorage) {
        self.configuration = configuration
        self.storage = storage
        logger.info("Initialized MetricsAggregator for project: \(configuration.projectName)")
    }
    
    public func registerCollector(_ collector: BaseCollector) {
        // Only register collectors that are enabled in the configuration
        if configuration.enabledCollectors.contains(collector.id) {
            collectors.append(collector)
            logger.info("Registered collector: \(collector.name) (\(collector.id))")
        } else {
            logger.info("Skipped disabled collector: \(collector.name) (\(collector.id))")
        }
    }
    
    public func registerDefaultCollectors() {
        // Register all default collectors based on configuration
        if configuration.enabledCollectors.contains("xctest") {
            registerCollector(XCTestCollector())
        }
        
        if configuration.enabledCollectors.contains("instruments") {
            registerCollector(InstrumentsCollector())
        }
        
        if configuration.enabledCollectors.contains("metrickit") {
            registerCollector(MetricKitCollector())
        }
        
        if configuration.enabledCollectors.contains("buildTime") {
            registerCollector(BuildTimeCollector())
        }
        
        logger.info("Registered \(collectors.count) collectors")
    }
    
    public func collectMetrics(for projectPath: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        logger.info("Starting metrics collection for project at \(projectPath)")
        
        var allMetrics: [PerformanceMetric] = []
        let group = DispatchGroup()
        var collectionErrors: [Error] = []
        
        for collector in collectors {
            group.enter()
            collector.collectMetrics(for: projectPath, projectName: configuration.projectName) { result in
                switch result {
                case .success(let metrics):
                    allMetrics.append(contentsOf: metrics)
                    self.logger.info("\(collector.name) collected \(metrics.count) metrics")
                case .failure(let error):
                    self.logger.error("Error collecting metrics with \(collector.name): \(error)")
                    collectionErrors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .global()) {
            if collectionErrors.isEmpty || !allMetrics.isEmpty {
                // Store metrics in time series database even if some collectors failed
                self.storage.storeMetrics(allMetrics) { result in
                    switch result {
                    case .success:
                        self.logger.info("Successfully stored \(allMetrics.count) metrics")
                        completion(.success(allMetrics))
                    case .failure(let error):
                        self.logger.error("Failed to store metrics: \(error)")
                        completion(.failure(AggregatorError.storageError(error)))
                    }
                }
            } else {
                completion(.failure(AggregatorError.collectionFailed(collectionErrors)))
            }
        }
    }
    
    public func generateReport(timeRange: TimeRange? = nil, completion: @escaping (Result<PerformanceReport, Error>) -> Void) {
        let reportTimeRange = timeRange ?? configuration.visualizationOptions.defaultTimeRange
        
        storage.retrieveMetrics(for: configuration.projectName, timeRange: reportTimeRange) { result in
            switch result {
            case .success(let metrics):
                // If we have a baseline commit, generate comparison data
                if let baselineCommit = self.configuration.baselineCommit {
                    self.generateBaselineComparison(metrics: metrics, baselineCommit: baselineCommit) { baselineResult in
                        switch baselineResult {
                        case .success(let baselineComparison):
                            let report = PerformanceReport(
                                projectName: self.configuration.projectName,
                                metrics: metrics,
                                generatedAt: Date(),
                                baselineComparison: baselineComparison
                            )
                            completion(.success(report))
                        case .failure(_):
                            // Create report without baseline comparison
                            let report = PerformanceReport(
                                projectName: self.configuration.projectName,
                                metrics: metrics,
                                generatedAt: Date(),
                                baselineComparison: nil
                            )
                            completion(.success(report))
                        }
                    }
                } else {
                    // No baseline comparison
                    let report = PerformanceReport(
                        projectName: self.configuration.projectName,
                        metrics: metrics,
                        generatedAt: Date(),
                        baselineComparison: nil
                    )
                    completion(.success(report))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func generateBaselineComparison(
        metrics: [PerformanceMetric],
        baselineCommit: String,
        completion: @escaping (Result<PerformanceReport.BaselineComparison?, Error>) -> Void
    ) {
        // Fetch baseline metrics for the specified commit
        storage.retrieveMetricsForCommit(baselineCommit, projectName: configuration.projectName) { result in
            switch result {
            case .success(let baselineMetrics):
                if baselineMetrics.isEmpty {
                    completion(.success(nil))
                    return
                }
                
                var improvements: [PerformanceReport.BaselineComparison.MetricComparison] = []
                var regressions: [PerformanceReport.BaselineComparison.MetricComparison] = []
                var unchanged: [PerformanceReport.BaselineComparison.MetricComparison] = []
                
                // Group metrics by type for comparison
                let currentMetricsByType = Dictionary(grouping: metrics) { $0.type }
                let baselineMetricsByType = Dictionary(grouping: baselineMetrics) { $0.type }
                
                // Compare each metric type
                for (type, currentMetricsOfType) in currentMetricsByType {
                    guard let baselineMetricsOfType = baselineMetricsByType[type] else {
                        continue
                    }
                    
                    // Calculate averages for comparison
                    let currentAvg = currentMetricsOfType.map { $0.value }.reduce(0, +) / Double(currentMetricsOfType.count)
                    let baselineAvg = baselineMetricsOfType.map { $0.value }.reduce(0, +) / Double(baselineMetricsOfType.count)
                    
                    // Calculate percent change
                    let percentChange = ((currentAvg - baselineAvg) / baselineAvg) * 100
                    
                    // Create comparison object
                    let comparison = PerformanceReport.BaselineComparison.MetricComparison(
                        metricId: currentMetricsOfType.first!.id,
                        baselineValue: baselineAvg,
                        currentValue: currentAvg,
                        percentChange: percentChange
                    )
                    
                    // Categorize as improvement, regression, or unchanged
                    // Note: For some metrics like CPU time, lower is better, but for others like frame rate, higher is better
                    // This is a simplified approach - in a real implementation, you'd need logic based on metric type
                    if abs(percentChange) < 1.0 {
                        unchanged.append(comparison)
                    } else if percentChange < 0 {
                        // Assuming lower values are better (like CPU time)
                        improvements.append(comparison)
                    } else {
                        regressions.append(comparison)
                    }
                }
                
                let baselineComparison = PerformanceReport.BaselineComparison(
                    baselineId: baselineCommit,
                    improvements: improvements,
                    regressions: regressions,
                    unchanged: unchanged
                )
                
                completion(.success(baselineComparison))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

public enum AggregatorError: Error {
    case collectionFailed([Error])
    case storageError(Error)
    case invalidProjectPath
    case configurationError(String)
}
