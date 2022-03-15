import Foundation
import os.log
import Network

/// Performance monitoring for network requests
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor PerformanceMonitor {
    
    // MARK: - Types
    
    /// Performance metrics
    public struct Metrics {
        public let requestCount: Int
        public let successCount: Int
        public let failureCount: Int
        public let averageResponseTime: TimeInterval
        public let minResponseTime: TimeInterval
        public let maxResponseTime: TimeInterval
        public let percentile95: TimeInterval
        public let percentile99: TimeInterval
        public let totalBytesReceived: Int64
        public let totalBytesSent: Int64
        public let averageThroughput: Double // bytes per second
        public let errorRate: Double
        public let successRate: Double
        public let timestamp: Date
        
        public var description: String {
            """
            Performance Metrics:
            - Requests: \(requestCount) (Success: \(successCount), Failure: \(failureCount))
            - Success Rate: \(String(format: "%.2f%%", successRate * 100))
            - Error Rate: \(String(format: "%.2f%%", errorRate * 100))
            - Response Time: avg \(String(format: "%.3fs", averageResponseTime)), min \(String(format: "%.3fs", minResponseTime)), max \(String(format: "%.3fs", maxResponseTime))
            - Percentiles: p95 \(String(format: "%.3fs", percentile95)), p99 \(String(format: "%.3fs", percentile99))
            - Data Transfer: sent \(ByteCountFormatter.string(fromByteCount: totalBytesSent, countStyle: .binary)), received \(ByteCountFormatter.string(fromByteCount: totalBytesReceived, countStyle: .binary))
            - Throughput: \(ByteCountFormatter.string(fromByteCount: Int64(averageThroughput), countStyle: .binary))/s
            """
        }
    }
    
    /// Request performance data
    public struct RequestPerformance {
        public let id: String
        public let url: String
        public let method: String
        public let startTime: Date
        public let endTime: Date
        public let duration: TimeInterval
        public let statusCode: Int?
        public let bytesReceived: Int64
        public let bytesSent: Int64
        public let success: Bool
        public let error: Error?
        
        public var throughput: Double {
            guard duration > 0 else { return 0 }
            return Double(bytesReceived) / duration
        }
    }
    
    /// Performance alert
    public struct PerformanceAlert {
        public enum AlertType {
            case highResponseTime(threshold: TimeInterval, actual: TimeInterval)
            case highErrorRate(threshold: Double, actual: Double)
            case lowThroughput(threshold: Double, actual: Double)
            case requestTimeout(url: String, duration: TimeInterval)
            case connectionFailure(url: String, error: Error)
        }
        
        public let type: AlertType
        public let timestamp: Date
        public let severity: Severity
        
        public enum Severity {
            case info
            case warning
            case critical
        }
    }
    
    /// Performance configuration
    public struct Configuration {
        public let enableMonitoring: Bool
        public let sampleRate: Double // 0.0 to 1.0
        public let metricsWindowSize: TimeInterval
        public let alertThresholds: AlertThresholds
        public let persistMetrics: Bool
        public let maxStoredMetrics: Int
        
        public struct AlertThresholds {
            public let maxResponseTime: TimeInterval
            public let maxErrorRate: Double
            public let minThroughput: Double
            public let timeoutDuration: TimeInterval
            
            public init(
                maxResponseTime: TimeInterval = 5.0,
                maxErrorRate: Double = 0.1,
                minThroughput: Double = 1024, // 1KB/s
                timeoutDuration: TimeInterval = 30.0
            ) {
                self.maxResponseTime = maxResponseTime
                self.maxErrorRate = maxErrorRate
                self.minThroughput = minThroughput
                self.timeoutDuration = timeoutDuration
            }
        }
        
        public init(
            enableMonitoring: Bool = true,
            sampleRate: Double = 1.0,
            metricsWindowSize: TimeInterval = 3600, // 1 hour
            alertThresholds: AlertThresholds = AlertThresholds(),
            persistMetrics: Bool = false,
            maxStoredMetrics: Int = 10000
        ) {
            self.enableMonitoring = enableMonitoring
            self.sampleRate = min(max(sampleRate, 0.0), 1.0)
            self.metricsWindowSize = metricsWindowSize
            self.alertThresholds = alertThresholds
            self.persistMetrics = persistMetrics
            self.maxStoredMetrics = maxStoredMetrics
        }
        
        public static let `default` = Configuration()
        
        public static let production = Configuration(
            sampleRate: 0.1,
            metricsWindowSize: 86400, // 24 hours
            persistMetrics: true
        )
        
        public static let debug = Configuration(
            sampleRate: 1.0,
            metricsWindowSize: 300, // 5 minutes
            persistMetrics: false
        )
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private var performances: [RequestPerformance] = []
    private var alerts: [PerformanceAlert] = []
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Performance")
    
    private var alertHandler: ((PerformanceAlert) -> Void)?
    private var metricsHandler: ((Metrics) -> Void)?
    
    private var cleanupTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        
        if configuration.enableMonitoring {
            startCleanupTask()
        }
    }
    
    deinit {
        cleanupTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring a request
    public func startRequest(
        id: String = UUID().uuidString,
        url: String,
        method: String
    ) -> String {
        guard configuration.enableMonitoring else { return id }
        
        // Apply sampling
        guard Double.random(in: 0...1) <= configuration.sampleRate else { return id }
        
        logger.debug("Started monitoring request: \(id)")
        return id
    }
    
    /// Complete monitoring a request
    public func completeRequest(
        id: String,
        url: String,
        method: String,
        startTime: Date,
        statusCode: Int? = nil,
        bytesReceived: Int64 = 0,
        bytesSent: Int64 = 0,
        error: Error? = nil
    ) {
        guard configuration.enableMonitoring else { return }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        let performance = RequestPerformance(
            id: id,
            url: url,
            method: method,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            statusCode: statusCode,
            bytesReceived: bytesReceived,
            bytesSent: bytesSent,
            success: error == nil && statusCode.map { (200...299).contains($0) } ?? false,
            error: error
        )
        
        performances.append(performance)
        
        // Check for alerts
        checkForAlerts(performance)
        
        // Trim old performances if needed
        if performances.count > configuration.maxStoredMetrics {
            performances.removeFirst(performances.count - configuration.maxStoredMetrics)
        }
        
        logger.debug("Completed monitoring request: \(id), duration: \(duration)s")
    }
    
    /// Get current metrics
    public func getMetrics() -> Metrics {
        let cutoff = Date().addingTimeInterval(-configuration.metricsWindowSize)
        let recentPerformances = performances.filter { $0.endTime > cutoff }
        
        guard !recentPerformances.isEmpty else {
            return Metrics(
                requestCount: 0,
                successCount: 0,
                failureCount: 0,
                averageResponseTime: 0,
                minResponseTime: 0,
                maxResponseTime: 0,
                percentile95: 0,
                percentile99: 0,
                totalBytesReceived: 0,
                totalBytesSent: 0,
                averageThroughput: 0,
                errorRate: 0,
                successRate: 0,
                timestamp: Date()
            )
        }
        
        let requestCount = recentPerformances.count
        let successCount = recentPerformances.filter { $0.success }.count
        let failureCount = requestCount - successCount
        
        let responseTimes = recentPerformances.map { $0.duration }.sorted()
        let averageResponseTime = responseTimes.reduce(0, +) / Double(responseTimes.count)
        let minResponseTime = responseTimes.first ?? 0
        let maxResponseTime = responseTimes.last ?? 0
        
        let percentile95Index = Int(Double(responseTimes.count) * 0.95)
        let percentile99Index = Int(Double(responseTimes.count) * 0.99)
        let percentile95 = responseTimes[min(percentile95Index, responseTimes.count - 1)]
        let percentile99 = responseTimes[min(percentile99Index, responseTimes.count - 1)]
        
        let totalBytesReceived = recentPerformances.reduce(0) { $0 + $1.bytesReceived }
        let totalBytesSent = recentPerformances.reduce(0) { $0 + $1.bytesSent }
        
        let totalDuration = recentPerformances.reduce(0.0) { $0 + $1.duration }
        let averageThroughput = totalDuration > 0 ? Double(totalBytesReceived) / totalDuration : 0
        
        let errorRate = Double(failureCount) / Double(requestCount)
        let successRate = Double(successCount) / Double(requestCount)
        
        let metrics = Metrics(
            requestCount: requestCount,
            successCount: successCount,
            failureCount: failureCount,
            averageResponseTime: averageResponseTime,
            minResponseTime: minResponseTime,
            maxResponseTime: maxResponseTime,
            percentile95: percentile95,
            percentile99: percentile99,
            totalBytesReceived: totalBytesReceived,
            totalBytesSent: totalBytesSent,
            averageThroughput: averageThroughput,
            errorRate: errorRate,
            successRate: successRate,
            timestamp: Date()
        )
        
        metricsHandler?(metrics)
        
        return metrics
    }
    
    /// Get recent alerts
    public func getAlerts(since: Date? = nil) -> [PerformanceAlert] {
        if let since = since {
            return alerts.filter { $0.timestamp > since }
        }
        return alerts
    }
    
    /// Clear all metrics
    public func clearMetrics() {
        performances.removeAll()
        alerts.removeAll()
        logger.info("Cleared all performance metrics")
    }
    
    /// Set alert handler
    public func onAlert(_ handler: @escaping (PerformanceAlert) -> Void) {
        self.alertHandler = handler
    }
    
    /// Set metrics handler
    public func onMetrics(_ handler: @escaping (Metrics) -> Void) {
        self.metricsHandler = handler
    }
    
    /// Export metrics
    public func exportMetrics(format: ExportFormat = .json) -> Data? {
        let metrics = getMetrics()
        
        switch format {
        case .json:
            return try? JSONEncoder().encode(metrics)
        case .csv:
            return exportAsCSV()
        case .prometheus:
            return exportAsPrometheus()
        }
    }
    
    public enum ExportFormat {
        case json
        case csv
        case prometheus
    }
    
    // MARK: - Private Methods
    
    private func checkForAlerts(_ performance: RequestPerformance) {
        var alerts: [PerformanceAlert] = []
        
        // Check response time
        if performance.duration > configuration.alertThresholds.maxResponseTime {
            alerts.append(PerformanceAlert(
                type: .highResponseTime(
                    threshold: configuration.alertThresholds.maxResponseTime,
                    actual: performance.duration
                ),
                timestamp: Date(),
                severity: performance.duration > configuration.alertThresholds.maxResponseTime * 2 ? .critical : .warning
            ))
        }
        
        // Check for timeout
        if performance.duration > configuration.alertThresholds.timeoutDuration {
            alerts.append(PerformanceAlert(
                type: .requestTimeout(url: performance.url, duration: performance.duration),
                timestamp: Date(),
                severity: .critical
            ))
        }
        
        // Check for connection failure
        if let error = performance.error {
            alerts.append(PerformanceAlert(
                type: .connectionFailure(url: performance.url, error: error),
                timestamp: Date(),
                severity: .critical
            ))
        }
        
        // Check throughput
        if performance.throughput < configuration.alertThresholds.minThroughput && performance.bytesReceived > 0 {
            alerts.append(PerformanceAlert(
                type: .lowThroughput(
                    threshold: configuration.alertThresholds.minThroughput,
                    actual: performance.throughput
                ),
                timestamp: Date(),
                severity: .warning
            ))
        }
        
        // Check error rate
        let metrics = getMetrics()
        if metrics.errorRate > configuration.alertThresholds.maxErrorRate {
            alerts.append(PerformanceAlert(
                type: .highErrorRate(
                    threshold: configuration.alertThresholds.maxErrorRate,
                    actual: metrics.errorRate
                ),
                timestamp: Date(),
                severity: metrics.errorRate > configuration.alertThresholds.maxErrorRate * 2 ? .critical : .warning
            ))
        }
        
        // Store and notify alerts
        for alert in alerts {
            self.alerts.append(alert)
            alertHandler?(alert)
            
            switch alert.severity {
            case .info:
                logger.info("Performance alert: \(alert.type)")
            case .warning:
                logger.warning("Performance warning: \(alert.type)")
            case .critical:
                logger.error("Performance critical: \(alert.type)")
            }
        }
    }
    
    private func startCleanupTask() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute
                await cleanup()
            }
        }
    }
    
    private func cleanup() {
        // Remove old performances
        let cutoff = Date().addingTimeInterval(-configuration.metricsWindowSize * 2)
        performances.removeAll { $0.endTime < cutoff }
        
        // Remove old alerts
        alerts.removeAll { $0.timestamp < cutoff }
        
        logger.debug("Cleaned up old metrics: \(performances.count) performances, \(alerts.count) alerts remaining")
    }
    
    private func exportAsCSV() -> Data? {
        var csv = "timestamp,url,method,duration,status_code,bytes_received,bytes_sent,success\n"
        
        for performance in performances {
            csv += "\(performance.endTime.timeIntervalSince1970),"
            csv += "\"\(performance.url)\","
            csv += "\(performance.method),"
            csv += "\(performance.duration),"
            csv += "\(performance.statusCode ?? 0),"
            csv += "\(performance.bytesReceived),"
            csv += "\(performance.bytesSent),"
            csv += "\(performance.success)\n"
        }
        
        return csv.data(using: .utf8)
    }
    
    private func exportAsPrometheus() -> Data? {
        let metrics = getMetrics()
        
        var prometheus = """
        # HELP http_requests_total Total number of HTTP requests
        # TYPE http_requests_total counter
        http_requests_total \(metrics.requestCount)
        
        # HELP http_requests_success_total Total number of successful HTTP requests
        # TYPE http_requests_success_total counter
        http_requests_success_total \(metrics.successCount)
        
        # HELP http_requests_failure_total Total number of failed HTTP requests
        # TYPE http_requests_failure_total counter
        http_requests_failure_total \(metrics.failureCount)
        
        # HELP http_request_duration_seconds HTTP request duration in seconds
        # TYPE http_request_duration_seconds summary
        http_request_duration_seconds{quantile="0.5"} \(metrics.averageResponseTime)
        http_request_duration_seconds{quantile="0.95"} \(metrics.percentile95)
        http_request_duration_seconds{quantile="0.99"} \(metrics.percentile99)
        http_request_duration_seconds_sum \(Double(metrics.requestCount) * metrics.averageResponseTime)
        http_request_duration_seconds_count \(metrics.requestCount)
        
        # HELP http_bytes_received_total Total bytes received
        # TYPE http_bytes_received_total counter
        http_bytes_received_total \(metrics.totalBytesReceived)
        
        # HELP http_bytes_sent_total Total bytes sent
        # TYPE http_bytes_sent_total counter
        http_bytes_sent_total \(metrics.totalBytesSent)
        
        # HELP http_error_rate Current error rate
        # TYPE http_error_rate gauge
        http_error_rate \(metrics.errorRate)
        
        # HELP http_success_rate Current success rate
        # TYPE http_success_rate gauge
        http_success_rate \(metrics.successRate)
        """
        
        return prometheus.data(using: .utf8)
    }
}

// MARK: - Network Monitor

/// Network reachability monitor
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class NetworkMonitor: ObservableObject {
    
    // MARK: - Properties
    
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var connectionType: ConnectionType = .unknown
    @Published public private(set) var isExpensive: Bool = false
    @Published public private(set) var isConstrained: Bool = false
    
    public enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.swiftnetworkpro.networkmonitor")
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "NetworkMonitor")
    
    private var statusChangeHandler: ((Bool, ConnectionType) -> Void)?
    
    // MARK: - Initialization
    
    public init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring network status
    public func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateStatus(path)
        }
        monitor.start(queue: queue)
        logger.info("Started network monitoring")
    }
    
    /// Stop monitoring network status
    public func stopMonitoring() {
        monitor.cancel()
        logger.info("Stopped network monitoring")
    }
    
    /// Set status change handler
    public func onStatusChange(_ handler: @escaping (Bool, ConnectionType) -> Void) {
        self.statusChangeHandler = handler
    }
    
    /// Check if specific host is reachable
    public func isReachable(host: String) async -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.swiftnetworkpro.reachability")
        
        return await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.resume(returning: path.status == .satisfied)
                monitor.cancel()
            }
            monitor.start(queue: queue)
            
            // Timeout after 5 seconds
            queue.asyncAfter(deadline: .now() + 5) {
                continuation.resume(returning: false)
                monitor.cancel()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateStatus(_ path: NWPath) {
        let wasConnected = isConnected
        let previousType = connectionType
        
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = path.status == .satisfied
            self?.isExpensive = path.isExpensive
            self?.isConstrained = path.isConstrained
            
            if path.usesInterfaceType(.wifi) {
                self?.connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self?.connectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                self?.connectionType = .ethernet
            } else {
                self?.connectionType = .unknown
            }
            
            // Notify if status changed
            if let self = self,
               wasConnected != self.isConnected || previousType != self.connectionType {
                self.statusChangeHandler?(self.isConnected, self.connectionType)
                
                if self.isConnected {
                    self.logger.info("Network connected: \(String(describing: self.connectionType))")
                } else {
                    self.logger.warning("Network disconnected")
                }
            }
        }
    }
}