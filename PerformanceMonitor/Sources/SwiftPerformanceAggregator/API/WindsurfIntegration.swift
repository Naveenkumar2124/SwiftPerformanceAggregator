import Foundation
import Vapor
import Logging

public class WindsurfIntegration {
    private let logger = Logger(label: "com.windsurf.integration")
    private let aggregator: MetricsAggregator
    private let app: Application
    private let configuration: Configuration
    private let codeReviewIntegration: CodeReviewIntegration
    private let codeReviewAnnotations: CodeReviewAnnotations
    
    public init(aggregator: MetricsAggregator, configuration: Configuration) {
        self.aggregator = aggregator
        self.configuration = configuration
        
        // Initialize code review integration components
        self.codeReviewIntegration = CodeReviewIntegration(storage: aggregator.storage, configuration: configuration)
        self.codeReviewAnnotations = CodeReviewAnnotations(storage: aggregator.storage)
        
        // Initialize Vapor application
        // Note: In a fully async environment, you would use Application.make(_:_:) instead
        self.app = Application(.development)
        configureMiddleware()
        configureRoutes()
        
        logger.info("Initialized Windsurf integration")
    }
    
    private func configureMiddleware() {
        // Configure CORS if needed
        let corsConfiguration = CORSMiddleware.Configuration(
            allowedOrigin: .all,
            allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
            allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent]
        )
        app.middleware.use(CORSMiddleware(configuration: corsConfiguration))
        
        // Add logging middleware
        app.middleware.use(LoggingMiddleware())
    }
    
    private func configureRoutes() {
        // API endpoints for Windsurf integration
        
        // Health check endpoint
        app.get("health") { req -> String in
            return "Swift Performance Metrics Aggregator is running"
        }
        
        // Endpoint to trigger metrics collection
        app.post("collect") { req -> EventLoopFuture<CollectionResponse> in
            struct CollectionRequest: Content {
                let projectPath: String
                let branch: String?
                let commit: String?
            }
            
            do {
                let collectionRequest = try req.content.decode(CollectionRequest.self)
                
                let promise = req.eventLoop.makePromise(of: CollectionResponse.self)
                
                self.aggregator.collectMetrics(for: collectionRequest.projectPath) { result in
                    switch result {
                    case .success(let metrics):
                        let response = CollectionResponse(
                            success: true,
                            metricCount: metrics.count,
                            message: "Successfully collected \\(metrics.count) metrics"
                        )
                        promise.succeed(response)
                    case .failure(let error):
                        promise.fail(error)
                    }
                }
                
                return promise.futureResult
            } catch {
                return req.eventLoop.makeFailedFuture(error)
            }
        }
        
        // Endpoint to retrieve metrics for visualization
        app.get("metrics") { req -> EventLoopFuture<String> in
            guard let startDateString = req.query[String.self, at: "startDate"],
                  let endDateString = req.query[String.self, at: "endDate"],
                  let startDate = ISO8601DateFormatter().date(from: startDateString),
                  let endDate = ISO8601DateFormatter().date(from: endDateString) else {
                throw Abort(.badRequest, reason: "Missing or invalid query parameters")
            }
            
            let projectName = req.query[String.self, at: "project"] ?? self.configuration.projectName
            let timeRange = TimeRange(start: startDate, end: endDate)
            
            let promise = req.eventLoop.makePromise(of: String.self)
            
            self.aggregator.storage.retrieveMetrics(for: projectName, timeRange: timeRange) { result in
                switch result {
                case .success(let metrics):
                    // Convert metrics to JSON string
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        encoder.dateEncodingStrategy = .iso8601
                        let data = try encoder.encode(metrics)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            promise.succeed(jsonString)
                        } else {
                            promise.fail(Abort(.internalServerError, reason: "Failed to encode metrics"))
                        }
                    } catch {
                        promise.fail(error)
                    }
                case .failure(let error):
                    promise.fail(error)
                }
            }
            
            return promise.futureResult
        }
        
        // Endpoint to get a performance report
        app.get("report") { req -> EventLoopFuture<String> in
            let days = req.query[Int.self, at: "days"] ?? 30
            let timeRange = TimeRange.last(days: days)
            
            let promise = req.eventLoop.makePromise(of: String.self)
            
            self.aggregator.generateReport(timeRange: timeRange) { result in
                switch result {
                case .success(let report):
                    // Convert report to JSON string
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        encoder.dateEncodingStrategy = .iso8601
                        let data = try encoder.encode(report)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            promise.succeed(jsonString)
                        } else {
                            promise.fail(Abort(.internalServerError, reason: "Failed to encode report"))
                        }
                    } catch {
                        promise.fail(error)
                    }
                case .failure(let error):
                    promise.fail(error)
                }
            }
            
            return promise.futureResult
        }
        
        // Webhook endpoint for Windsurf code review events
        app.post("webhook", "code-review") { req -> EventLoopFuture<WebhookResponse> in
            struct CodeReviewEvent: Content {
                let reviewId: String
                let projectName: String
                let filePaths: [String]
                let commitHash: String
            }
            
            do {
                let event = try req.content.decode(CodeReviewEvent.self)
                
                // Process the code review event and generate insights
                let promise = req.eventLoop.makePromise(of: WebhookResponse.self)
                
                self.codeReviewIntegration.processCodeReviewEvent(
                    reviewId: event.reviewId,
                    commitHash: event.commitHash,
                    filePaths: event.filePaths
                ) { result in
                    switch result {
                    case .success(_):
                        let response = WebhookResponse(
                            success: true,
                            message: "Generated performance recommendations",
                            reviewId: event.reviewId
                        )
                        promise.succeed(response)
                    case .failure(let error):
                        promise.fail(error)
                    }
                }
                
                return promise.futureResult
            } catch {
                return req.eventLoop.makeFailedFuture(error)
            }
        }
        
        // Endpoint to get visualization data for Windsurf UI
        app.get("visualizations", ":type") { req -> EventLoopFuture<String> in
            guard let type = req.parameters.get("type") else {
                throw Abort(.badRequest, reason: "Missing visualization type")
            }
            
            let days = req.query[Int.self, at: "days"] ?? 30
            let timeRange = TimeRange.last(days: days)
            let projectName = req.query[String.self, at: "project"] ?? self.configuration.projectName
            
            let promise = req.eventLoop.makePromise(of: String.self)
            
            self.generateVisualizationData(type: type, projectName: projectName, timeRange: timeRange) { result in
                switch result {
                case .success(let data):
                    // Convert to JSON string
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        let jsonData = try JSONSerialization.data(withJSONObject: ["type": data.type, "title": data.title, "data": data.data], options: .prettyPrinted)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            promise.succeed(jsonString)
                        } else {
                            promise.fail(Abort(.internalServerError, reason: "Failed to encode visualization data"))
                        }
                    } catch {
                        promise.fail(error)
                    }
                case .failure(let error):
                    promise.fail(error)
                }
            }
            
            return promise.futureResult
        }
        
        // Endpoint to get code review annotations
        app.get("annotations") { req -> EventLoopFuture<String> in
            guard let projectName = req.query[String.self, at: "project"] else {
                throw Abort(.badRequest, reason: "Missing project name")
            }
            
            let commitHash = req.query[String.self, at: "commit"]
            let filePaths = req.query[String.self, at: "files"]?.components(separatedBy: ",") ?? []
            
            if filePaths.isEmpty {
                throw Abort(.badRequest, reason: "No files specified")
            }
            
            let promise = req.eventLoop.makePromise(of: String.self)
            
            self.codeReviewAnnotations.generateAnnotations(
                for: filePaths,
                projectName: projectName,
                commitHash: commitHash
            ) { result in
                switch result {
                case .success(let annotations):
                    // Convert annotations to JSON string
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        encoder.dateEncodingStrategy = .iso8601
                        let data = try encoder.encode(annotations)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            promise.succeed(jsonString)
                        } else {
                            promise.fail(Abort(.internalServerError, reason: "Failed to encode annotations"))
                        }
                    } catch {
                        promise.fail(error)
                    }
                case .failure(let error):
                    promise.fail(error)
                }
            }
            
            return promise.futureResult
        }
        
        // Endpoint to get Windsurf visualization components
        app.get("windsurf-visualization") { req -> EventLoopFuture<String> in
            guard let projectName = req.query[String.self, at: "project"] else {
                throw Abort(.badRequest, reason: "Missing project name")
            }
            
            let days = req.query[Int.self, at: "days"] ?? 30
            let timeRange = TimeRange.last(days: days)
            let commitHash = req.query[String.self, at: "commit"]
            let reviewId = req.query[String.self, at: "reviewId"]
            
            let promise = req.eventLoop.makePromise(of: String.self)
            
            self.generateWindsurfVisualization(
                projectName: projectName,
                timeRange: timeRange,
                commitHash: commitHash,
                reviewId: reviewId
            ) { result in
                switch result {
                case .success(let visualizationData):
                    // Convert response to JSON string
                    do {
                        let response = WindsurfVisualizationResponse(
                            success: true,
                            data: visualizationData
                        )
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        encoder.dateEncodingStrategy = .iso8601
                        let data = try encoder.encode(response)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            promise.succeed(jsonString)
                        } else {
                            promise.fail(Abort(.internalServerError, reason: "Failed to encode visualization data"))
                        }
                    } catch {
                        promise.fail(error)
                    }
                case .failure(let error):
                    promise.fail(error)
                }
            }
            
            return promise.futureResult
        }
    }
    
    // Generate Windsurf visualization data
    private func generateWindsurfVisualization(
        projectName: String,
        timeRange: TimeRange,
        commitHash: String?,
        reviewId: String?,
        completion: @escaping (Result<WindsurfVisualizationData, Error>) -> Void
    ) {
        // Get metrics for the project
        aggregator.storage.retrieveMetrics(for: projectName, timeRange: timeRange) { metricsResult in
            switch metricsResult {
            case .success(let metrics):
                // If we have a review ID, get code review insights
                if let reviewId = reviewId, let commitHash = commitHash {
                    // Get file paths from metrics
                    let filePaths = Array(Set(metrics.compactMap { $0.filePath }))
                    
                    self.codeReviewIntegration.processCodeReviewEvent(
                        reviewId: reviewId,
                        commitHash: commitHash,
                        filePaths: filePaths
                    ) { insightsResult in
                        switch insightsResult {
                        case .success(_):
                            // Generate visualization with insights
                            let visualizationData = WindsurfVisualization.generateVisualizationData(
                                metrics: metrics
                                // Use the insights in a future implementation
                            )
                            completion(.success(visualizationData))
                            
                        case .failure(_):
                            // Fall back to basic visualization without insights
                            let visualizationData = WindsurfVisualization.generateVisualizationData(
                                metrics: metrics
                            )
                            completion(.success(visualizationData))
                        }
                    }
                } else {
                    // Generate basic visualization without code review insights
                    let visualizationData = WindsurfVisualization.generateVisualizationData(
                        metrics: metrics
                    )
                    completion(.success(visualizationData))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func generateVisualizationData(type: String, projectName: String, timeRange: TimeRange, completion: @escaping (Result<VisualizationData, Error>) -> Void) {
        aggregator.storage.retrieveMetrics(for: projectName, timeRange: timeRange) { result in
            switch result {
            case .success(let metrics):
                if metrics.isEmpty {
                    completion(.success(VisualizationData(
                        type: type,
                        title: "No data available",
                        data: [:]
                    )))
                    return
                }
                
                switch type {
                case "timeline":
                    self.generateTimelineData(metrics: metrics, completion: completion)
                    
                case "heatmap":
                    self.generateHeatmapData(metrics: metrics, completion: completion)
                    
                case "comparison":
                    self.generateComparisonData(metrics: metrics, completion: completion)
                    
                default:
                    completion(.failure(Abort(.badRequest, reason: "Unsupported visualization type: \\(type)")))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func generateTimelineData(metrics: [PerformanceMetric], completion: @escaping (Result<VisualizationData, Error>) -> Void) {
        // Group metrics by type
        let metricsByType = Dictionary(grouping: metrics) { $0.type }
        
        // Create data series for each metric type
        var series: [[String: Any]] = []
        
        for (type, typeMetrics) in metricsByType {
            // Sort by timestamp
            let sortedMetrics = typeMetrics.sorted { $0.timestamp < $1.timestamp }
            
            // Create data points
            let dataPoints = sortedMetrics.map { metric -> [String: Any] in
                return [
                    "x": Int(metric.timestamp.timeIntervalSince1970),
                    "y": metric.value,
                    "label": "\(metric.displayType): \(metric.displayValue)"
                ]
            }
            
            // Add series
            series.append([
                "name": type.displayName,
                "data": dataPoints
            ])
        }
        
        // Create visualization data
        let data: [String: Any] = [
            "series": series
        ]
        
        completion(.success(VisualizationData(
            type: "timeline",
            title: "Performance Metrics Timeline",
            data: data
        )))
    }
    
    private func generateHeatmapData(metrics: [PerformanceMetric], completion: @escaping (Result<VisualizationData, Error>) -> Void) {
        // Filter metrics with file paths
        let metricsWithPaths = metrics.filter { $0.filePath != nil }
        
        // Group by file path
        let metricsByFile = Dictionary(grouping: metricsWithPaths) { $0.filePath! }
        
        // Create heatmap data
        var heatmapData: [[String: Any]] = []
        
        for (filePath, fileMetrics) in metricsByFile {
            // Calculate average value for this file
            let avgValue = fileMetrics.map { $0.value }.reduce(0, +) / Double(fileMetrics.count)
            
            // Add data point
            heatmapData.append([
                "name": URL(fileURLWithPath: filePath).lastPathComponent,
                "path": filePath,
                "value": avgValue
            ])
        }
        
        let data: [String: Any] = [
            "heatmap": heatmapData
        ]
        
        completion(.success(VisualizationData(
            type: "heatmap",
            title: "Performance Hotspots",
            data: data
        )))
    }
    
    private func generateComparisonData(metrics: [PerformanceMetric], completion: @escaping (Result<VisualizationData, Error>) -> Void) {
        // Group by commit hash
        let metricsByCommit = Dictionary(grouping: metrics.filter { $0.commitHash != nil }) { $0.commitHash! }
        
        // Create comparison data
        var comparisonData: [[String: Any]] = []
        
        for (commit, commitMetrics) in metricsByCommit {
            // Group by metric type
            let metricsByType = Dictionary(grouping: commitMetrics) { $0.type }
            
            var typeValues: [String: Double] = [:]
            
            for (type, typeMetrics) in metricsByType {
                let avgValue = typeMetrics.map { $0.value }.reduce(0, +) / Double(typeMetrics.count)
                typeValues[type.displayName] = avgValue
            }
            
            // Add data point
            comparisonData.append([
                "commit": String(commit.prefix(7)),
                "values": typeValues
            ])
        }
        
        let data: [String: Any] = [
            "comparison": comparisonData
        ]
        
        completion(.success(VisualizationData(
            type: "comparison",
            title: "Commit Performance Comparison",
            data: data
        )))
    }
    
    public func start() throws {
        // Start the server
        if let windsurf = configuration.windsurf {
            // Configure API key authentication if provided
            if !windsurf.apiKey.isEmpty {
                app.middleware.use(APIKeyMiddleware(apiKey: windsurf.apiKey))
            }
        }
        
        // Start on a specific port
        app.http.server.configuration.port = 8080
        
        try app.run()
    }
    
    public func shutdown() {
        app.shutdown()
    }
}

// Response models
struct CollectionResponse: Content {
    let success: Bool
    let metricCount: Int
    let message: String
}

struct WebhookResponse: Content {
    let success: Bool
    let message: String
    let reviewId: String
}

struct VisualizationData: Content {
    let type: String
    let title: String
    let data: String // JSON string representation of the data
    
    init(type: String, title: String, data: [String: Any]) {
        self.type = type
        self.title = title
        
        // Convert dictionary to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.data = jsonString
        } else {
            self.data = "{}"
        }
    }
}

struct WindsurfVisualizationResponse: Content {
    let success: Bool
    let data: WindsurfVisualizationData
}

// Custom middleware for API key authentication
struct APIKeyMiddleware: Middleware {
    let apiKey: String
    
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        // Check for API key in header
        guard let providedKey = request.headers.first(name: "X-API-Key"),
              providedKey == apiKey else {
            return request.eventLoop.makeFailedFuture(Abort(.unauthorized, reason: "Invalid API key"))
        }
        
        return next.respond(to: request)
    }
}

// Custom logging middleware
struct LoggingMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        let start = Date()
        let logger = Logger(label: "com.windsurf.api")
        
        logger.info("\(request.method) \(request.url.path)")
        
        return next.respond(to: request).always { result in
            let duration = Date().timeIntervalSince(start) * 1000
            
            switch result {
            case .success(let response):
                logger.info("\(request.method) \(request.url.path) - \(response.status.code) (\(String(format: "%.2f", duration))ms)")
            case .failure(let error):
                logger.error("\(request.method) \(request.url.path) - Failed: \(error) (\(String(format: "%.2f", duration))ms)")
            }
        }
    }
}
