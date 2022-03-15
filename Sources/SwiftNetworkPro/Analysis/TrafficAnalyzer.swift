import Foundation
import Network
import os.log
import Combine

/// Network traffic analysis and monitoring
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor TrafficAnalyzer {
    
    // MARK: - Types
    
    /// Traffic statistics
    public struct Statistics {
        public let totalRequests: Int
        public let successfulRequests: Int
        public let failedRequests: Int
        public let totalBytes: Int64
        public let averageResponseTime: TimeInterval
        public let minResponseTime: TimeInterval
        public let maxResponseTime: TimeInterval
        public let p50ResponseTime: TimeInterval
        public let p95ResponseTime: TimeInterval
        public let p99ResponseTime: TimeInterval
        public let requestsPerSecond: Double
        public let bytesPerSecond: Double
        public let errorRate: Double
        public let topDomains: [String: Int]
        public let topStatusCodes: [Int: Int]
        public let topUserAgents: [String: Int]
        public let peakHour: Int?
        public let timeRange: DateInterval
        
        public var successRate: Double {
            guard totalRequests > 0 else { return 0 }
            return Double(successfulRequests) / Double(totalRequests)
        }
        
        public var formattedTotalBytes: String {
            return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .binary)
        }
        
        public var formattedBytesPerSecond: String {
            return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
        }
    }
    
    /// Request record for analysis
    public struct RequestRecord {
        public let id: String
        public let url: URL
        public let method: String
        public let timestamp: Date
        public let responseTime: TimeInterval
        public let statusCode: Int?
        public let requestSize: Int64
        public let responseSize: Int64
        public let userAgent: String?
        public let error: Error?
        public let headers: [String: String]
        
        public var domain: String {
            return url.host ?? "unknown"
        }
        
        public var isSuccessful: Bool {
            if let statusCode = statusCode {
                return (200...299).contains(statusCode)
            }
            return error == nil
        }
        
        public var hourOfDay: Int {
            return Calendar.current.component(.hour, from: timestamp)
        }
    }
    
    /// Traffic pattern detection
    public struct Pattern {
        public enum PatternType {
            case spike
            case drop
            case anomaly
            case trend
        }
        
        public let type: PatternType
        public let description: String
        public let severity: Severity
        public let timeRange: DateInterval
        public let value: Double
        public let threshold: Double
        
        public enum Severity {
            case low
            case medium
            case high
            case critical
        }
    }
    
    /// Real-time metrics
    public struct RealTimeMetrics {
        public let requestsPerSecond: Double
        public let averageResponseTime: TimeInterval
        public let errorRate: Double
        public let activeConnections: Int
        public let bandwidth: Double
        public let timestamp: Date
    }
    
    /// Performance threshold
    public struct PerformanceThreshold {
        public let responseTimeWarning: TimeInterval
        public let responseTimeCritical: TimeInterval
        public let errorRateWarning: Double
        public let errorRateCritical: Double
        public let requestRateHigh: Double
        public let requestRateCritical: Double
        
        public static let `default` = PerformanceThreshold(
            responseTimeWarning: 1.0,
            responseTimeCritical: 5.0,
            errorRateWarning: 0.05,
            errorRateCritical: 0.15,
            requestRateHigh: 100.0,
            requestRateCritical: 500.0
        )
    }
    
    // MARK: - Properties
    
    private var records: [RequestRecord] = []
    private var maxRecords: Int = 10000
    private var isRecording = false
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "TrafficAnalyzer")
    
    // Real-time monitoring
    private var metricsTimer: Timer?
    private var currentMetrics = RealTimeMetrics(
        requestsPerSecond: 0,
        averageResponseTime: 0,
        errorRate: 0,
        activeConnections: 0,
        bandwidth: 0,
        timestamp: Date()
    )
    
    // Thresholds and alerting
    private var thresholds = PerformanceThreshold.default
    private var alertHandler: ((Pattern) -> Void)?
    
    // Publishers for real-time updates
    private let metricsSubject = PassthroughSubject<RealTimeMetrics, Never>()
    private let patternSubject = PassthroughSubject<Pattern, Never>()
    
    public var metricsPublisher: AnyPublisher<RealTimeMetrics, Never> {
        metricsSubject.eraseToAnyPublisher()
    }
    
    public var patternPublisher: AnyPublisher<Pattern, Never> {
        patternSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Public Methods
    
    /// Start recording traffic
    public func startRecording(maxRecords: Int = 10000) {
        self.maxRecords = maxRecords
        self.isRecording = true
        
        // Start real-time monitoring
        startRealTimeMonitoring()
        
        logger.info("Traffic recording started (max records: \(maxRecords))")
    }
    
    /// Stop recording traffic
    public func stopRecording() {
        self.isRecording = false
        stopRealTimeMonitoring()
        
        logger.info("Traffic recording stopped")
    }
    
    /// Record a network request
    public func recordRequest(_ record: RequestRecord) {
        guard isRecording else { return }
        
        records.append(record)
        
        // Maintain maximum records limit
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        
        // Check for patterns and anomalies
        checkForPatterns()
        
        logger.debug("Recorded request: \(record.method) \(record.url)")
    }
    
    /// Get traffic statistics
    public func getStatistics(timeRange: DateInterval? = nil) -> Statistics {
        let filteredRecords = filterRecords(timeRange: timeRange)
        return calculateStatistics(from: filteredRecords)
    }
    
    /// Get records within time range
    public func getRecords(timeRange: DateInterval? = nil, limit: Int? = nil) -> [RequestRecord] {
        var filtered = filterRecords(timeRange: timeRange)
        
        if let limit = limit {
            filtered = Array(filtered.prefix(limit))
        }
        
        return filtered
    }
    
    /// Clear all records
    public func clearRecords() {
        records.removeAll()
        logger.info("All traffic records cleared")
    }
    
    /// Set performance thresholds
    public func setThresholds(_ thresholds: PerformanceThreshold) {
        self.thresholds = thresholds
        logger.info("Performance thresholds updated")
    }
    
    /// Set alert handler
    public func onAlert(_ handler: @escaping (Pattern) -> Void) {
        self.alertHandler = handler
    }
    
    /// Get current real-time metrics
    public func getCurrentMetrics() -> RealTimeMetrics {
        return currentMetrics
    }
    
    /// Analyze performance trends
    public func analyzePerformanceTrends(timeWindow: TimeInterval = 3600) -> [Pattern] {
        let now = Date()
        let windowStart = now.addingTimeInterval(-timeWindow)
        let timeRange = DateInterval(start: windowStart, end: now)
        
        let filteredRecords = filterRecords(timeRange: timeRange)
        return detectPatterns(in: filteredRecords)
    }
    
    /// Generate comprehensive report
    public func generateReport(timeRange: DateInterval? = nil) -> String {
        let stats = getStatistics(timeRange: timeRange)
        let patterns = analyzePerformanceTrends()
        
        return formatReport(statistics: stats, patterns: patterns)
    }
    
    /// Export data for analysis
    public func exportData(format: ExportFormat = .json) throws -> Data {
        switch format {
        case .json:
            return try JSONEncoder().encode(records)
        case .csv:
            return generateCSV()
        }
    }
    
    public enum ExportFormat {
        case json
        case csv
    }
    
    // MARK: - Private Methods
    
    private func filterRecords(timeRange: DateInterval?) -> [RequestRecord] {
        guard let timeRange = timeRange else { return records }
        
        return records.filter { record in
            timeRange.contains(record.timestamp)
        }
    }
    
    private func calculateStatistics(from records: [RequestRecord]) -> Statistics {
        guard !records.isEmpty else {
            return Statistics(
                totalRequests: 0, successfulRequests: 0, failedRequests: 0,
                totalBytes: 0, averageResponseTime: 0, minResponseTime: 0,
                maxResponseTime: 0, p50ResponseTime: 0, p95ResponseTime: 0,
                p99ResponseTime: 0, requestsPerSecond: 0, bytesPerSecond: 0,
                errorRate: 0, topDomains: [:], topStatusCodes: [:],
                topUserAgents: [:], peakHour: nil,
                timeRange: DateInterval(start: Date(), duration: 0)
            )
        }
        
        let totalRequests = records.count
        let successfulRequests = records.filter { $0.isSuccessful }.count
        let failedRequests = totalRequests - successfulRequests
        
        let totalBytes = records.reduce(0) { $0 + $1.requestSize + $1.responseSize }
        
        let responseTimes = records.map { $0.responseTime }
        let sortedResponseTimes = responseTimes.sorted()
        
        let averageResponseTime = responseTimes.isEmpty ? 0 : responseTimes.reduce(0, +) / Double(responseTimes.count)
        let minResponseTime = sortedResponseTimes.first ?? 0
        let maxResponseTime = sortedResponseTimes.last ?? 0
        
        let p50Index = Int(Double(sortedResponseTimes.count) * 0.5)
        let p95Index = Int(Double(sortedResponseTimes.count) * 0.95)
        let p99Index = Int(Double(sortedResponseTimes.count) * 0.99)
        
        let p50ResponseTime = sortedResponseTimes.isEmpty ? 0 : sortedResponseTimes[min(p50Index, sortedResponseTimes.count - 1)]
        let p95ResponseTime = sortedResponseTimes.isEmpty ? 0 : sortedResponseTimes[min(p95Index, sortedResponseTimes.count - 1)]
        let p99ResponseTime = sortedResponseTimes.isEmpty ? 0 : sortedResponseTimes[min(p99Index, sortedResponseTimes.count - 1)]
        
        // Calculate time-based metrics
        let timestamps = records.map { $0.timestamp }
        let timeRange = DateInterval(start: timestamps.min() ?? Date(), end: timestamps.max() ?? Date())
        let duration = timeRange.duration
        
        let requestsPerSecond = duration > 0 ? Double(totalRequests) / duration : 0
        let bytesPerSecond = duration > 0 ? Double(totalBytes) / duration : 0
        let errorRate = Double(failedRequests) / Double(totalRequests)
        
        // Top domains
        var domainCounts: [String: Int] = [:]
        for record in records {
            domainCounts[record.domain, default: 0] += 1
        }
        let topDomains = Dictionary(domainCounts.sorted(by: { $0.value > $1.value }).prefix(10), uniquingKeysWith: { first, _ in first })
        
        // Top status codes
        var statusCodeCounts: [Int: Int] = [:]
        for record in records {
            if let statusCode = record.statusCode {
                statusCodeCounts[statusCode, default: 0] += 1
            }
        }
        let topStatusCodes = Dictionary(statusCodeCounts.sorted(by: { $0.value > $1.value }).prefix(10), uniquingKeysWith: { first, _ in first })
        
        // Top user agents
        var userAgentCounts: [String: Int] = [:]
        for record in records {
            if let userAgent = record.userAgent {
                userAgentCounts[userAgent, default: 0] += 1
            }
        }
        let topUserAgents = Dictionary(userAgentCounts.sorted(by: { $0.value > $1.value }).prefix(10), uniquingKeysWith: { first, _ in first })
        
        // Peak hour
        var hourCounts: [Int: Int] = [:]
        for record in records {
            hourCounts[record.hourOfDay, default: 0] += 1
        }
        let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key
        
        return Statistics(
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            failedRequests: failedRequests,
            totalBytes: totalBytes,
            averageResponseTime: averageResponseTime,
            minResponseTime: minResponseTime,
            maxResponseTime: maxResponseTime,
            p50ResponseTime: p50ResponseTime,
            p95ResponseTime: p95ResponseTime,
            p99ResponseTime: p99ResponseTime,
            requestsPerSecond: requestsPerSecond,
            bytesPerSecond: bytesPerSecond,
            errorRate: errorRate,
            topDomains: topDomains,
            topStatusCodes: topStatusCodes,
            topUserAgents: topUserAgents,
            peakHour: peakHour,
            timeRange: timeRange
        )
    }
    
    private func startRealTimeMonitoring() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task {
                await self?.updateRealTimeMetrics()
            }
        }
    }
    
    private func stopRealTimeMonitoring() {
        metricsTimer?.invalidate()
        metricsTimer = nil
    }
    
    private func updateRealTimeMetrics() {
        let now = Date()
        let recentTimeWindow: TimeInterval = 60 // Last 60 seconds
        let recentRecords = records.filter { 
            now.timeIntervalSince($0.timestamp) <= recentTimeWindow 
        }
        
        let requestsPerSecond = Double(recentRecords.count) / recentTimeWindow
        let averageResponseTime = recentRecords.isEmpty ? 0 : 
            recentRecords.map { $0.responseTime }.reduce(0, +) / Double(recentRecords.count)
        let errorRate = recentRecords.isEmpty ? 0 : 
            Double(recentRecords.filter { !$0.isSuccessful }.count) / Double(recentRecords.count)
        let bandwidth = recentRecords.isEmpty ? 0 : 
            Double(recentRecords.reduce(0) { $0 + $1.requestSize + $1.responseSize }) / recentTimeWindow
        
        currentMetrics = RealTimeMetrics(
            requestsPerSecond: requestsPerSecond,
            averageResponseTime: averageResponseTime,
            errorRate: errorRate,
            activeConnections: 0, // Would need connection tracking
            bandwidth: bandwidth,
            timestamp: now
        )
        
        metricsSubject.send(currentMetrics)
    }
    
    private func checkForPatterns() {
        // Simple pattern detection - in production, use more sophisticated algorithms
        guard records.count >= 10 else { return }
        
        let recentRecords = Array(records.suffix(10))
        let recentResponseTimes = recentRecords.map { $0.responseTime }
        let averageResponseTime = recentResponseTimes.reduce(0, +) / Double(recentResponseTimes.count)
        
        // Check for response time spike
        if averageResponseTime > thresholds.responseTimeCritical {
            let pattern = Pattern(
                type: .spike,
                description: "Response time spike detected",
                severity: .critical,
                timeRange: DateInterval(start: recentRecords.first!.timestamp, end: recentRecords.last!.timestamp),
                value: averageResponseTime,
                threshold: thresholds.responseTimeCritical
            )
            
            patternSubject.send(pattern)
            alertHandler?(pattern)
        }
        
        // Check for error rate spike
        let errorCount = recentRecords.filter { !$0.isSuccessful }.count
        let errorRate = Double(errorCount) / Double(recentRecords.count)
        
        if errorRate > thresholds.errorRateCritical {
            let pattern = Pattern(
                type: .anomaly,
                description: "Error rate spike detected",
                severity: .critical,
                timeRange: DateInterval(start: recentRecords.first!.timestamp, end: recentRecords.last!.timestamp),
                value: errorRate,
                threshold: thresholds.errorRateCritical
            )
            
            patternSubject.send(pattern)
            alertHandler?(pattern)
        }
    }
    
    private func detectPatterns(in records: [RequestRecord]) -> [Pattern] {
        var patterns: [Pattern] = []
        
        // Detect response time trends
        if records.count >= 10 {
            let bucketSize = max(1, records.count / 10)
            var bucketAverages: [TimeInterval] = []
            
            for i in stride(from: 0, to: records.count, by: bucketSize) {
                let bucket = Array(records[i..<min(i + bucketSize, records.count)])
                let average = bucket.map { $0.responseTime }.reduce(0, +) / Double(bucket.count)
                bucketAverages.append(average)
            }
            
            // Simple trend detection
            if bucketAverages.count >= 3 {
                let first = bucketAverages.prefix(3).reduce(0, +) / 3
                let last = bucketAverages.suffix(3).reduce(0, +) / 3
                
                if last > first * 1.5 {
                    patterns.append(Pattern(
                        type: .trend,
                        description: "Response time increasing trend",
                        severity: .medium,
                        timeRange: DateInterval(start: records.first!.timestamp, end: records.last!.timestamp),
                        value: last,
                        threshold: first
                    ))
                }
            }
        }
        
        return patterns
    }
    
    private func formatReport(statistics: Statistics, patterns: [Pattern]) -> String {
        var report = """
        === Network Traffic Analysis Report ===
        
        Time Range: \(formatDateInterval(statistics.timeRange))
        
        OVERVIEW
        --------
        Total Requests: \(statistics.totalRequests)
        Successful: \(statistics.successfulRequests) (\(String(format: "%.1f", statistics.successRate * 100))%)
        Failed: \(statistics.failedRequests) (\(String(format: "%.1f", statistics.errorRate * 100))%)
        Total Data: \(statistics.formattedTotalBytes)
        
        PERFORMANCE
        -----------
        Average Response Time: \(String(format: "%.3f", statistics.averageResponseTime))s
        Min Response Time: \(String(format: "%.3f", statistics.minResponseTime))s
        Max Response Time: \(String(format: "%.3f", statistics.maxResponseTime))s
        50th Percentile: \(String(format: "%.3f", statistics.p50ResponseTime))s
        95th Percentile: \(String(format: "%.3f", statistics.p95ResponseTime))s
        99th Percentile: \(String(format: "%.3f", statistics.p99ResponseTime))s
        
        THROUGHPUT
        ----------
        Requests per Second: \(String(format: "%.1f", statistics.requestsPerSecond))
        Bandwidth: \(statistics.formattedBytesPerSecond)
        
        """
        
        if !statistics.topDomains.isEmpty {
            report += "\nTOP DOMAINS\n-----------\n"
            for (domain, count) in statistics.topDomains.sorted(by: { $0.value > $1.value }).prefix(5) {
                report += "\(domain): \(count) requests\n"
            }
        }
        
        if !statistics.topStatusCodes.isEmpty {
            report += "\nTOP STATUS CODES\n----------------\n"
            for (code, count) in statistics.topStatusCodes.sorted(by: { $0.value > $1.value }).prefix(5) {
                report += "\(code): \(count) responses\n"
            }
        }
        
        if let peakHour = statistics.peakHour {
            report += "\nPeak Hour: \(peakHour):00\n"
        }
        
        if !patterns.isEmpty {
            report += "\nPATTERNS & ANOMALIES\n-------------------\n"
            for pattern in patterns {
                report += "\(pattern.severity.description): \(pattern.description)\n"
            }
        }
        
        return report
    }
    
    private func formatDateInterval(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return "\(formatter.string(from: interval.start)) - \(formatter.string(from: interval.end))"
    }
    
    private func generateCSV() -> Data {
        var csv = "Timestamp,Method,URL,Response Time,Status Code,Request Size,Response Size,Success\n"
        
        for record in records {
            let timestamp = ISO8601DateFormatter().string(from: record.timestamp)
            let url = record.url.absoluteString
            let responseTime = String(format: "%.3f", record.responseTime)
            let statusCode = record.statusCode?.description ?? ""
            let success = record.isSuccessful ? "true" : "false"
            
            csv += "\(timestamp),\(record.method),\(url),\(responseTime),\(statusCode),\(record.requestSize),\(record.responseSize),\(success)\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
}

// MARK: - Extensions

extension TrafficAnalyzer.Pattern.Severity {
    var description: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        case .critical: return "CRITICAL"
        }
    }
}

// MARK: - Codable Support

extension TrafficAnalyzer.RequestRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id, url, method, timestamp, responseTime, statusCode
        case requestSize, responseSize, userAgent, headers
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        method = try container.decode(String.self, forKey: .method)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        responseTime = try container.decode(TimeInterval.self, forKey: .responseTime)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        requestSize = try container.decode(Int64.self, forKey: .requestSize)
        responseSize = try container.decode(Int64.self, forKey: .responseSize)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        headers = try container.decode([String: String].self, forKey: .headers)
        error = nil // Errors are not serialized
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(method, forKey: .method)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(responseTime, forKey: .responseTime)
        try container.encodeIfPresent(statusCode, forKey: .statusCode)
        try container.encode(requestSize, forKey: .requestSize)
        try container.encode(responseSize, forKey: .responseSize)
        try container.encodeIfPresent(userAgent, forKey: .userAgent)
        try container.encode(headers, forKey: .headers)
    }
}