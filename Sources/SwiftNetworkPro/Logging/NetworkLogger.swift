import Foundation
import os.log
import Network

/// Comprehensive network logging system
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class NetworkLogger {
    
    // MARK: - Types
    
    /// Log level
    public enum Level: Int, CaseIterable, Comparable {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        case critical = 5
        
        public static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        public var name: String {
            switch self {
            case .verbose: return "VERBOSE"
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }
        
        public var emoji: String {
            switch self {
            case .verbose: return "💬"
            case .debug: return "🐛"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🚨"
            }
        }
        
        public var osLogType: OSLogType {
            switch self {
            case .verbose, .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
    }
    
    /// Log category
    public enum Category: String, CaseIterable {
        case network = "Network"
        case request = "Request"
        case response = "Response"
        case cache = "Cache"
        case security = "Security"
        case performance = "Performance"
        case websocket = "WebSocket"
        case graphql = "GraphQL"
        case upload = "Upload"
        case download = "Download"
        case proxy = "Proxy"
        case http2 = "HTTP2"
        case ssl = "SSL"
        case authentication = "Auth"
        case monitoring = "Monitor"
        case testing = "Testing"
    }
    
    /// Log entry
    public struct LogEntry {
        public let timestamp: Date
        public let level: Level
        public let category: Category
        public let message: String
        public let file: String
        public let function: String
        public let line: Int
        public let metadata: [String: Any]
        
        public var formattedMessage: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let timeString = formatter.string(from: timestamp)
            
            let fileComponent = URL(fileURLWithPath: file).lastPathComponent
            return "\(timeString) \(level.emoji) [\(category.rawValue)] \(message) (\(fileComponent):\(line))"
        }
    }
    
    /// Log destination
    public protocol LogDestination {
        func write(_ entry: LogEntry)
    }
    
    /// Console log destination
    public class ConsoleDestination: LogDestination {
        private let logger: Logger
        
        public init(subsystem: String = "com.swiftnetworkpro", category: String = "NetworkLogger") {
            self.logger = Logger(subsystem: subsystem, category: category)
        }
        
        public func write(_ entry: LogEntry) {
            logger.log(level: entry.level.osLogType, "\(entry.formattedMessage)")
        }
    }
    
    /// File log destination
    public class FileDestination: LogDestination {
        private let fileURL: URL
        private let maxFileSize: Int
        private let maxBackupFiles: Int
        private let queue = DispatchQueue(label: "com.swiftnetworkpro.filelog", qos: .utility)
        
        public init(fileURL: URL, maxFileSize: Int = 10 * 1024 * 1024, maxBackupFiles: Int = 5) {
            self.fileURL = fileURL
            self.maxFileSize = maxFileSize
            self.maxBackupFiles = maxBackupFiles
        }
        
        public func write(_ entry: LogEntry) {
            queue.async { [weak self] in
                self?.writeToFile(entry)
            }
        }
        
        private func writeToFile(_ entry: LogEntry) {
            let logString = entry.formattedMessage + "\n"
            
            do {
                // Create directory if needed
                let directory = fileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                
                // Append to file
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let fileHandle = try FileHandle(forWritingTo: fileURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logString.data(using: .utf8)!)
                    fileHandle.closeFile()
                    
                    // Check file size and rotate if needed
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int, fileSize > maxFileSize {
                        rotateLogFile()
                    }
                } else {
                    try logString.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Failed to write log entry: \(error)")
            }
        }
        
        private func rotateLogFile() {
            do {
                // Move existing backup files
                for i in stride(from: maxBackupFiles - 1, through: 1, by: -1) {
                    let oldFile = fileURL.appendingPathExtension("\(i)")
                    let newFile = fileURL.appendingPathExtension("\(i + 1)")
                    
                    if FileManager.default.fileExists(atPath: oldFile.path) {
                        _ = try? FileManager.default.removeItem(at: newFile)
                        try FileManager.default.moveItem(at: oldFile, to: newFile)
                    }
                }
                
                // Move current file to backup
                let backupFile = fileURL.appendingPathExtension("1")
                _ = try? FileManager.default.removeItem(at: backupFile)
                try FileManager.default.moveItem(at: fileURL, to: backupFile)
                
                // Remove oldest backup
                let oldestBackup = fileURL.appendingPathExtension("\(maxBackupFiles + 1)")
                _ = try? FileManager.default.removeItem(at: oldestBackup)
                
            } catch {
                print("Failed to rotate log file: \(error)")
            }
        }
    }
    
    /// Memory log destination (for testing)
    public class MemoryDestination: LogDestination {
        private var entries: [LogEntry] = []
        private let maxEntries: Int
        private let queue = DispatchQueue(label: "com.swiftnetworkpro.memorylog")
        
        public init(maxEntries: Int = 1000) {
            self.maxEntries = maxEntries
        }
        
        public func write(_ entry: LogEntry) {
            queue.async { [weak self] in
                self?.entries.append(entry)
                if let self = self, self.entries.count > self.maxEntries {
                    self.entries.removeFirst()
                }
            }
        }
        
        public func getEntries() -> [LogEntry] {
            return queue.sync { entries }
        }
        
        public func clear() {
            queue.async { [weak self] in
                self?.entries.removeAll()
            }
        }
    }
    
    /// Network request/response logger
    public class NetworkTrafficLogger {
        private let logger: NetworkLogger
        private let includeHeaders: Bool
        private let includeBody: Bool
        private let maxBodyLength: Int
        private let sensitiveHeaders: Set<String>
        
        public init(
            logger: NetworkLogger,
            includeHeaders: Bool = true,
            includeBody: Bool = true,
            maxBodyLength: Int = 1024,
            sensitiveHeaders: Set<String> = ["Authorization", "Cookie", "Set-Cookie", "X-API-Key"]
        ) {
            self.logger = logger
            self.includeHeaders = includeHeaders
            self.includeBody = includeBody
            self.maxBodyLength = maxBodyLength
            self.sensitiveHeaders = sensitiveHeaders
        }
        
        public func logRequest(_ request: URLRequest, id: String = UUID().uuidString) {
            var message = "→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")"
            var metadata: [String: Any] = ["requestId": id]
            
            if includeHeaders, let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                let sanitizedHeaders = sanitizeHeaders(headers)
                message += "\nHeaders: \(sanitizedHeaders)"
                metadata["headers"] = sanitizedHeaders
            }
            
            if includeBody, let body = request.httpBody {
                let bodyString = formatBody(body)
                if !bodyString.isEmpty {
                    message += "\nBody: \(bodyString)"
                    metadata["bodySize"] = body.count
                }
            }
            
            logger.log(level: .debug, category: .request, message: message, metadata: metadata)
        }
        
        public func logResponse(_ response: URLResponse?, data: Data?, error: Error?, duration: TimeInterval, requestId: String) {
            var message: String
            var level: Level
            var metadata: [String: Any] = [
                "requestId": requestId,
                "duration": duration
            ]
            
            if let error = error {
                message = "← ERROR: \(error.localizedDescription)"
                level = .error
                metadata["error"] = error.localizedDescription
            } else if let httpResponse = response as? HTTPURLResponse {
                let status = httpResponse.statusCode
                message = "← \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))"
                level = (200...299).contains(status) ? .debug : .warning
                metadata["statusCode"] = status
                
                if includeHeaders {
                    let sanitizedHeaders = sanitizeHeaders(httpResponse.allHeaderFields as? [String: String] ?? [:])
                    message += "\nHeaders: \(sanitizedHeaders)"
                    metadata["headers"] = sanitizedHeaders
                }
                
                if includeBody, let data = data {
                    let bodyString = formatBody(data)
                    if !bodyString.isEmpty {
                        message += "\nBody: \(bodyString)"
                        metadata["bodySize"] = data.count
                    }
                }
            } else {
                message = "← Response received (no HTTP response)"
                level = .debug
            }
            
            message += " (\(String(format: "%.3f", duration))s)"
            
            logger.log(level: level, category: .response, message: message, metadata: metadata)
        }
        
        private func sanitizeHeaders(_ headers: [String: String]) -> [String: String] {
            return headers.mapValues { key, value in
                return sensitiveHeaders.contains(key) ? "***" : value
            }
        }
        
        private func formatBody(_ data: Data) -> String {
            guard data.count > 0 else { return "" }
            
            let truncated = data.count > maxBodyLength
            let dataToFormat = truncated ? data.prefix(maxBodyLength) : data
            
            if let string = String(data: dataToFormat, encoding: .utf8) {
                return string + (truncated ? "... (\(data.count) bytes total)" : "")
            } else {
                return "<binary data: \(data.count) bytes>" + (truncated ? " (truncated)" : "")
            }
        }
    }
    
    // MARK: - Properties
    
    public static let shared = NetworkLogger()
    
    private var destinations: [LogDestination] = []
    private var minimumLevel: Level = .debug
    private var isEnabled: Bool = true
    private let queue = DispatchQueue(label: "com.swiftnetworkpro.logger", qos: .utility)
    
    // MARK: - Initialization
    
    public init() {
        // Add console destination by default
        addDestination(ConsoleDestination())
    }
    
    // MARK: - Public Methods
    
    /// Add log destination
    public func addDestination(_ destination: LogDestination) {
        queue.async { [weak self] in
            self?.destinations.append(destination)
        }
    }
    
    /// Remove all destinations
    public func clearDestinations() {
        queue.async { [weak self] in
            self?.destinations.removeAll()
        }
    }
    
    /// Set minimum log level
    public func setMinimumLevel(_ level: Level) {
        queue.async { [weak self] in
            self?.minimumLevel = level
        }
    }
    
    /// Enable/disable logging
    public func setEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.isEnabled = enabled
        }
    }
    
    /// Log message
    public func log(
        level: Level,
        category: Category,
        message: String,
        metadata: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled && level >= minimumLevel else { return }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        )
        
        queue.async { [weak self] in
            self?.destinations.forEach { $0.write(entry) }
        }
    }
    
    /// Convenience methods for different log levels
    public func verbose(_ message: String, category: Category = .network, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .verbose, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func debug(_ message: String, category: Category = .network, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func info(_ message: String, category: Category = .network, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func warning(_ message: String, category: Category = .network, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func error(_ message: String, category: Category = .network, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func critical(_ message: String, category: Category = .network, metadata: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .critical, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Create network traffic logger
    public func createTrafficLogger(
        includeHeaders: Bool = true,
        includeBody: Bool = true,
        maxBodyLength: Int = 1024
    ) -> NetworkTrafficLogger {
        return NetworkTrafficLogger(
            logger: self,
            includeHeaders: includeHeaders,
            includeBody: includeBody,
            maxBodyLength: maxBodyLength
        )
    }
}

// MARK: - Performance Logger

/// Performance monitoring and logging
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class PerformanceLogger {
    
    public struct Measurement {
        public let name: String
        public let startTime: Date
        public let endTime: Date
        public let duration: TimeInterval
        public let metadata: [String: Any]
        
        public init(name: String, startTime: Date, endTime: Date, metadata: [String: Any] = [:]) {
            self.name = name
            self.startTime = startTime
            self.endTime = endTime
            self.duration = endTime.timeIntervalSince(startTime)
            self.metadata = metadata
        }
    }
    
    private let logger: NetworkLogger
    private var activeMeasurements: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.swiftnetworkpro.performance")
    
    public init(logger: NetworkLogger = .shared) {
        self.logger = logger
    }
    
    /// Start measuring performance
    public func startMeasurement(_ name: String) {
        queue.async { [weak self] in
            self?.activeMeasurements[name] = Date()
        }
    }
    
    /// End measurement and log result
    public func endMeasurement(_ name: String, metadata: [String: Any] = [:]) {
        queue.async { [weak self] in
            guard let self = self,
                  let startTime = self.activeMeasurements.removeValue(forKey: name) else {
                return
            }
            
            let endTime = Date()
            let measurement = Measurement(name: name, startTime: startTime, endTime: endTime, metadata: metadata)
            
            var logMetadata = metadata
            logMetadata["duration"] = measurement.duration
            logMetadata["startTime"] = startTime
            logMetadata["endTime"] = endTime
            
            let level: NetworkLogger.Level = measurement.duration > 5.0 ? .warning : .debug
            self.logger.log(
                level: level,
                category: .performance,
                message: "Performance: \(name) took \(String(format: "%.3f", measurement.duration))s",
                metadata: logMetadata
            )
        }
    }
    
    /// Measure block execution
    public func measure<T>(_ name: String, metadata: [String: Any] = [:], block: () throws -> T) rethrows -> T {
        let startTime = Date()
        defer {
            let endTime = Date()
            let measurement = Measurement(name: name, startTime: startTime, endTime: endTime, metadata: metadata)
            
            var logMetadata = metadata
            logMetadata["duration"] = measurement.duration
            
            let level: NetworkLogger.Level = measurement.duration > 5.0 ? .warning : .debug
            logger.log(
                level: level,
                category: .performance,
                message: "Performance: \(name) took \(String(format: "%.3f", measurement.duration))s",
                metadata: logMetadata
            )
        }
        
        return try block()
    }
    
    /// Measure async block execution
    public func measure<T>(_ name: String, metadata: [String: Any] = [:], block: () async throws -> T) async rethrows -> T {
        let startTime = Date()
        defer {
            let endTime = Date()
            let measurement = Measurement(name: name, startTime: startTime, endTime: endTime, metadata: metadata)
            
            var logMetadata = metadata
            logMetadata["duration"] = measurement.duration
            
            let level: NetworkLogger.Level = measurement.duration > 5.0 ? .warning : .debug
            logger.log(
                level: level,
                category: .performance,
                message: "Performance: \(name) took \(String(format: "%.3f", measurement.duration))s",
                metadata: logMetadata
            )
        }
        
        return try await block()
    }
}

// MARK: - Log Analysis

/// Log analysis utilities
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class LogAnalyzer {
    
    public struct Statistics {
        public let totalEntries: Int
        public let entriesByLevel: [NetworkLogger.Level: Int]
        public let entriesByCategory: [NetworkLogger.Category: Int]
        public let timeRange: DateInterval?
        public let errorRate: Double
        public let averageRequestDuration: TimeInterval?
    }
    
    public static func analyze(entries: [NetworkLogger.LogEntry]) -> Statistics {
        var entriesByLevel: [NetworkLogger.Level: Int] = [:]
        var entriesByCategory: [NetworkLogger.Category: Int] = [:]
        var timestamps: [Date] = []
        var requestDurations: [TimeInterval] = []
        var errorCount = 0
        
        for entry in entries {
            timestamps.append(entry.timestamp)
            
            entriesByLevel[entry.level, default: 0] += 1
            entriesByCategory[entry.category, default: 0] += 1
            
            if entry.level >= .error {
                errorCount += 1
            }
            
            if let duration = entry.metadata["duration"] as? TimeInterval {
                requestDurations.append(duration)
            }
        }
        
        let timeRange: DateInterval? = {
            guard let minTime = timestamps.min(), let maxTime = timestamps.max() else {
                return nil
            }
            return DateInterval(start: minTime, end: maxTime)
        }()
        
        let errorRate = entries.isEmpty ? 0.0 : Double(errorCount) / Double(entries.count)
        let averageRequestDuration = requestDurations.isEmpty ? nil : requestDurations.reduce(0, +) / Double(requestDurations.count)
        
        return Statistics(
            totalEntries: entries.count,
            entriesByLevel: entriesByLevel,
            entriesByCategory: entriesByCategory,
            timeRange: timeRange,
            errorRate: errorRate,
            averageRequestDuration: averageRequestDuration
        )
    }
    
    public static func findAnomalies(entries: [NetworkLogger.LogEntry], threshold: TimeInterval = 5.0) -> [NetworkLogger.LogEntry] {
        return entries.filter { entry in
            if let duration = entry.metadata["duration"] as? TimeInterval {
                return duration > threshold
            }
            return entry.level >= .error
        }
    }
    
    public static func generateReport(statistics: Statistics) -> String {
        var report = "=== Network Log Analysis Report ===\n\n"
        
        report += "Total Entries: \(statistics.totalEntries)\n"
        
        if let timeRange = statistics.timeRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            report += "Time Range: \(formatter.string(from: timeRange.start)) - \(formatter.string(from: timeRange.end))\n"
        }
        
        report += "Error Rate: \(String(format: "%.2f", statistics.errorRate * 100))%\n\n"
        
        report += "Entries by Level:\n"
        for level in NetworkLogger.Level.allCases {
            let count = statistics.entriesByLevel[level] ?? 0
            report += "  \(level.name): \(count)\n"
        }
        
        report += "\nEntries by Category:\n"
        for category in NetworkLogger.Category.allCases {
            let count = statistics.entriesByCategory[category] ?? 0
            if count > 0 {
                report += "  \(category.rawValue): \(count)\n"
            }
        }
        
        if let avgDuration = statistics.averageRequestDuration {
            report += "\nAverage Request Duration: \(String(format: "%.3f", avgDuration))s\n"
        }
        
        return report
    }
}