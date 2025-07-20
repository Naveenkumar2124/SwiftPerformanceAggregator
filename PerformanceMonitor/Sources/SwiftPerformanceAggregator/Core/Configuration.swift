import Foundation

public struct Configuration: Codable {
    public let projectName: String
    public let enabledCollectors: [String]
    public let visualizationOptions: VisualizationOptions
    public let windsurf: WindsurfConfiguration?
    public let storage: StorageConfiguration
    public let baselineCommit: String?
    
    public struct VisualizationOptions: Codable {
        public let enabledCharts: [ChartType]
        public let defaultTimeRange: TimeRange
        public let colorScheme: ColorScheme
        
        public enum ChartType: String, Codable, CaseIterable {
            case timeline
            case heatmap
            case comparison
            case distribution
            case breakdown
        }
        
        public enum ColorScheme: String, Codable {
            case light
            case dark
            case system
        }
        
        public init(
            enabledCharts: [ChartType] = ChartType.allCases,
            defaultTimeRange: TimeRange = .last(days: 30),
            colorScheme: ColorScheme = .system
        ) {
            self.enabledCharts = enabledCharts
            self.defaultTimeRange = defaultTimeRange
            self.colorScheme = colorScheme
        }
    }
    
    public struct WindsurfConfiguration: Codable {
        public let apiEndpoint: URL
        public let apiKey: String
        public let enableWebhooks: Bool
        public let webhookEndpoint: URL?
        
        public init(
            apiEndpoint: URL,
            apiKey: String,
            enableWebhooks: Bool = true,
            webhookEndpoint: URL? = nil
        ) {
            self.apiEndpoint = apiEndpoint
            self.apiKey = apiKey
            self.enableWebhooks = enableWebhooks
            self.webhookEndpoint = webhookEndpoint
        }
    }
    
    public struct StorageConfiguration: Codable {
        public enum StorageType: String, Codable {
            case memory
            case file
            case sqlite
            case influxDB
        }
        
        public let type: StorageType
        public let path: String?
        public let connectionString: String?
        public let retentionDays: Int
        
        public init(
            type: StorageType = .memory,
            path: String? = nil,
            connectionString: String? = nil,
            retentionDays: Int = 90
        ) {
            self.type = type
            self.path = path
            self.connectionString = connectionString
            self.retentionDays = retentionDays
        }
    }
    
    public init(
        projectName: String,
        enabledCollectors: [String] = ["instruments", "xctest", "metrickit", "buildTime"],
        visualizationOptions: VisualizationOptions = VisualizationOptions(),
        windsurf: WindsurfConfiguration? = nil,
        storage: StorageConfiguration = StorageConfiguration(),
        baselineCommit: String? = nil
    ) {
        self.projectName = projectName
        self.enabledCollectors = enabledCollectors
        self.visualizationOptions = visualizationOptions
        self.windsurf = windsurf
        self.storage = storage
        self.baselineCommit = baselineCommit
    }
    
    public static func load(from url: URL) throws -> Configuration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Configuration.self, from: data)
    }
    
    public static func defaultConfig(for projectName: String) -> Configuration {
        return Configuration(projectName: projectName)
    }
    
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

public struct TimeRange: Codable {
    public let start: Date
    public let end: Date
    
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
    
    public static func last(days: Int) -> TimeRange {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        return TimeRange(start: start, end: end)
    }
    
    public static func last(hours: Int) -> TimeRange {
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hours, to: end)!
        return TimeRange(start: start, end: end)
    }
}
