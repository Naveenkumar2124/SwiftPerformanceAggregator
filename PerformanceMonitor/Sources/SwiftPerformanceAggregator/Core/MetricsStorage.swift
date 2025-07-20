import Foundation

public protocol MetricsStorage {
    func storeMetrics(_ metrics: [PerformanceMetric], completion: @escaping (Result<Void, Error>) -> Void)
    func retrieveMetrics(for projectName: String, timeRange: TimeRange, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void)
    func retrieveMetricsForCommit(_ commitHash: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void)
    func retrieveMetricsByType(_ type: MetricType, projectName: String, timeRange: TimeRange, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void)
    func retrieveLatestMetrics(for projectName: String, limit: Int, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void)
    func deleteMetrics(olderThan date: Date, completion: @escaping (Result<Int, Error>) -> Void)
}

public enum StorageError: Error {
    case storageFailure(String)
    case dataNotFound
    case invalidData
    case connectionFailed
}

// In-memory implementation for testing and simple use cases
public class InMemoryStorage: MetricsStorage {
    private var metrics: [PerformanceMetric] = []
    private let queue = DispatchQueue(label: "com.windsurf.metrics-storage", attributes: .concurrent)
    
    public init() {}
    
    public func storeMetrics(_ metrics: [PerformanceMetric], completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async(flags: .barrier) {
            self.metrics.append(contentsOf: metrics)
            completion(.success(()))
        }
    }
    
    public func retrieveMetrics(for projectName: String, timeRange: TimeRange, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        queue.async {
            let filteredMetrics = self.metrics.filter { metric in
                return metric.projectName == projectName &&
                       metric.timestamp >= timeRange.start &&
                       metric.timestamp <= timeRange.end
            }
            completion(.success(filteredMetrics))
        }
    }
    
    public func retrieveMetricsForCommit(_ commitHash: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        queue.async {
            let filteredMetrics = self.metrics.filter { metric in
                return metric.projectName == projectName &&
                       metric.commitHash == commitHash
            }
            completion(.success(filteredMetrics))
        }
    }
    
    public func retrieveMetricsByType(_ type: MetricType, projectName: String, timeRange: TimeRange, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        queue.async {
            let filteredMetrics = self.metrics.filter { metric in
                return metric.projectName == projectName &&
                       metric.type == type &&
                       metric.timestamp >= timeRange.start &&
                       metric.timestamp <= timeRange.end
            }
            completion(.success(filteredMetrics))
        }
    }
    
    public func retrieveLatestMetrics(for projectName: String, limit: Int, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        queue.async {
            let filteredMetrics = self.metrics
                .filter { $0.projectName == projectName }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(limit)
            completion(.success(Array(filteredMetrics)))
        }
    }
    
    public func deleteMetrics(olderThan date: Date, completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async(flags: .barrier) {
            let countBefore = self.metrics.count
            self.metrics = self.metrics.filter { $0.timestamp >= date }
            let deleted = countBefore - self.metrics.count
            completion(.success(deleted))
        }
    }
}

// File-based storage implementation
public class FileStorage: MetricsStorage {
    private let fileManager = FileManager.default
    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.windsurf.file-storage", attributes: .concurrent)
    
    public init(storageDirectory: URL) throws {
        self.storageURL = storageDirectory.appendingPathComponent("metrics")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: storageURL.path) {
            try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        }
    }
    
    public func storeMetrics(_ metrics: [PerformanceMetric], completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async(flags: .barrier) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                // Group metrics by project for storage
                let metricsByProject = Dictionary(grouping: metrics) { $0.projectName }
                
                for (projectName, projectMetrics) in metricsByProject {
                    // Create project directory if needed
                    let projectDir = self.storageURL.appendingPathComponent(projectName)
                    if !self.fileManager.fileExists(atPath: projectDir.path) {
                        try self.fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
                    }
                    
                    // Store each metric in its own file
                    for metric in projectMetrics {
                        let metricFile = projectDir.appendingPathComponent("\(metric.id.uuidString).json")
                        let data = try encoder.encode(metric)
                        try data.write(to: metricFile)
                    }
                }
                
                completion(.success(()))
            } catch {
                completion(.failure(StorageError.storageFailure(error.localizedDescription)))
            }
        }
    }
    
    public func retrieveMetrics(for projectName: String, timeRange: TimeRange, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        queue.async {
            do {
                let projectDir = self.storageURL.appendingPathComponent(projectName)
                guard self.fileManager.fileExists(atPath: projectDir.path) else {
                    completion(.success([]))
                    return
                }
                
                let fileURLs = try self.fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)
                let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                var metrics: [PerformanceMetric] = []
                
                for fileURL in jsonFiles {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let metric = try decoder.decode(PerformanceMetric.self, from: data)
                        
                        if metric.timestamp >= timeRange.start && metric.timestamp <= timeRange.end {
                            metrics.append(metric)
                        }
                    } catch {
                        // Skip files that can't be decoded
                        continue
                    }
                }
                
                completion(.success(metrics))
            } catch {
                completion(.failure(StorageError.storageFailure(error.localizedDescription)))
            }
        }
    }
    
    public func retrieveMetricsForCommit(_ commitHash: String, projectName: String, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        queue.async {
            do {
                let projectDir = self.storageURL.appendingPathComponent(projectName)
                guard self.fileManager.fileExists(atPath: projectDir.path) else {
                    completion(.success([]))
                    return
                }
                
                let fileURLs = try self.fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)
                let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                var metrics: [PerformanceMetric] = []
                
                for fileURL in jsonFiles {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let metric = try decoder.decode(PerformanceMetric.self, from: data)
                        
                        if metric.commitHash == commitHash {
                            metrics.append(metric)
                        }
                    } catch {
                        // Skip files that can't be decoded
                        continue
                    }
                }
                
                completion(.success(metrics))
            } catch {
                completion(.failure(StorageError.storageFailure(error.localizedDescription)))
            }
        }
    }
    
    public func retrieveMetricsByType(_ type: MetricType, projectName: String, timeRange: TimeRange, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        retrieveMetrics(for: projectName, timeRange: timeRange) { result in
            switch result {
            case .success(let allMetrics):
                let filteredMetrics = allMetrics.filter { $0.type == type }
                completion(.success(filteredMetrics))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    public func retrieveLatestMetrics(for projectName: String, limit: Int, completion: @escaping (Result<[PerformanceMetric], Error>) -> Void) {
        // Use a very wide time range to get all metrics
        let now = Date()
        let distantPast = Date.distantPast
        let timeRange = TimeRange(start: distantPast, end: now)
        
        retrieveMetrics(for: projectName, timeRange: timeRange) { result in
            switch result {
            case .success(let allMetrics):
                let sortedMetrics = allMetrics.sorted { $0.timestamp > $1.timestamp }
                let limitedMetrics = Array(sortedMetrics.prefix(limit))
                completion(.success(limitedMetrics))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    public func deleteMetrics(olderThan date: Date, completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async(flags: .barrier) {
            do {
                var deletedCount = 0
                
                // Get all project directories
                let projectDirs = try self.fileManager.contentsOfDirectory(at: self.storageURL, includingPropertiesForKeys: nil)
                
                for projectDir in projectDirs {
                    guard projectDir.hasDirectoryPath else { continue }
                    
                    // Get all metric files in this project
                    let fileURLs = try self.fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)
                    let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    
                    for fileURL in jsonFiles {
                        do {
                            let data = try Data(contentsOf: fileURL)
                            let metric = try decoder.decode(PerformanceMetric.self, from: data)
                            
                            if metric.timestamp < date {
                                try self.fileManager.removeItem(at: fileURL)
                                deletedCount += 1
                            }
                        } catch {
                            // Skip files that can't be decoded or deleted
                            continue
                        }
                    }
                }
                
                completion(.success(deletedCount))
            } catch {
                completion(.failure(StorageError.storageFailure(error.localizedDescription)))
            }
        }
    }
}
