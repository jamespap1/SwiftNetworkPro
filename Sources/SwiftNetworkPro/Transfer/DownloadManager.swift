import Foundation
import os.log
import Combine

/// Download manager for handling file downloads
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor DownloadManager: NSObject {
    
    // MARK: - Types
    
    /// Download task
    public class DownloadTask: ObservableObject {
        public let id: String
        public let url: URL
        public let destinationURL: URL
        @Published public private(set) var state: State = .waiting
        @Published public private(set) var progress: Progress = Progress(totalUnitCount: 0)
        @Published public private(set) var bytesReceived: Int64 = 0
        @Published public private(set) var totalBytes: Int64 = 0
        @Published public private(set) var speed: Double = 0 // Bytes per second
        @Published public private(set) var timeRemaining: TimeInterval?
        @Published public private(set) var error: Error?
        
        internal var sessionTask: URLSessionDownloadTask?
        internal var resumeData: Data?
        internal var startTime: Date?
        internal var lastUpdateTime: Date?
        internal var lastBytesReceived: Int64 = 0
        
        public enum State {
            case waiting
            case downloading
            case paused
            case completed
            case failed
            case cancelled
            
            public var isActive: Bool {
                switch self {
                case .downloading, .waiting:
                    return true
                default:
                    return false
                }
            }
        }
        
        public init(id: String = UUID().uuidString, url: URL, destinationURL: URL) {
            self.id = id
            self.url = url
            self.destinationURL = destinationURL
            self.progress.totalUnitCount = 1
        }
        
        public var progressPercentage: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesReceived) / Double(totalBytes)
        }
        
        public var formattedSpeed: String {
            return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
        }
        
        public var formattedTimeRemaining: String? {
            guard let timeRemaining = timeRemaining else { return nil }
            
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 2
            
            return formatter.string(from: timeRemaining)
        }
    }
    
    /// Download configuration
    public struct Configuration {
        public let maxConcurrentDownloads: Int
        public let allowsCellularAccess: Bool
        public let isDiscretionary: Bool
        public let sessionIdentifier: String?
        public let timeout: TimeInterval
        public let retryCount: Int
        public let resumeOnFailure: Bool
        public let cleanupOnCompletion: Bool
        
        public init(
            maxConcurrentDownloads: Int = 3,
            allowsCellularAccess: Bool = true,
            isDiscretionary: Bool = false,
            sessionIdentifier: String? = nil,
            timeout: TimeInterval = 60,
            retryCount: Int = 3,
            resumeOnFailure: Bool = true,
            cleanupOnCompletion: Bool = true
        ) {
            self.maxConcurrentDownloads = maxConcurrentDownloads
            self.allowsCellularAccess = allowsCellularAccess
            self.isDiscretionary = isDiscretionary
            self.sessionIdentifier = sessionIdentifier
            self.timeout = timeout
            self.retryCount = retryCount
            self.resumeOnFailure = resumeOnFailure
            self.cleanupOnCompletion = cleanupOnCompletion
        }
        
        public static let `default` = Configuration()
        
        public static let background = Configuration(
            isDiscretionary: true,
            sessionIdentifier: "com.swiftnetworkpro.background"
        )
    }
    
    /// Download priority
    public enum Priority: Int {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private var session: URLSession!
    private var tasks: [String: DownloadTask] = [:]
    private var taskQueue: [(task: DownloadTask, priority: Priority)] = []
    private var activeDownloads: Set<String> = []
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "DownloadManager")
    
    private var progressHandler: ((String, Double) -> Void)?
    private var completionHandler: ((String, Result<URL, Error>) -> Void)?
    private var speedUpdateTimer: Timer?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        let config: URLSessionConfiguration
        
        if let identifier = configuration.sessionIdentifier {
            config = URLSessionConfiguration.background(withIdentifier: identifier)
        } else {
            config = URLSessionConfiguration.default
        }
        
        config.allowsCellularAccess = configuration.allowsCellularAccess
        config.isDiscretionary = configuration.isDiscretionary
        config.timeoutIntervalForRequest = configuration.timeout
        config.httpMaximumConnectionsPerHost = configuration.maxConcurrentDownloads
        
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Start speed update timer
        speedUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task {
                await self.updateSpeeds()
            }
        }
    }
    
    deinit {
        speedUpdateTimer?.invalidate()
        session.invalidateAndCancel()
    }
    
    // MARK: - Public Methods
    
    /// Add download task
    @discardableResult
    public func addDownload(
        from url: URL,
        to destinationURL: URL? = nil,
        priority: Priority = .normal,
        headers: [String: String]? = nil
    ) -> DownloadTask {
        let destination = destinationURL ?? defaultDestinationURL(for: url)
        let task = DownloadTask(url: url, destinationURL: destination)
        
        tasks[task.id] = task
        taskQueue.append((task, priority))
        taskQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        logger.debug("Added download: \(url.lastPathComponent) with priority: \(priority)")
        
        processQueue()
        
        return task
    }
    
    /// Start download
    public func start(_ taskId: String) {
        guard let task = tasks[taskId] else { return }
        
        switch task.state {
        case .paused:
            resume(taskId)
        case .waiting, .failed, .cancelled:
            startDownload(task)
        default:
            break
        }
    }
    
    /// Pause download
    public func pause(_ taskId: String) {
        guard let task = tasks[taskId],
              task.state == .downloading else { return }
        
        task.sessionTask?.cancel { resumeData in
            Task {
                await self.handlePause(taskId: taskId, resumeData: resumeData)
            }
        }
    }
    
    /// Resume download
    public func resume(_ taskId: String) {
        guard let task = tasks[taskId],
              task.state == .paused,
              let resumeData = task.resumeData else { return }
        
        task.state = .downloading
        task.sessionTask = session.downloadTask(withResumeData: resumeData)
        task.sessionTask?.resume()
        
        activeDownloads.insert(taskId)
        logger.debug("Resumed download: \(task.url.lastPathComponent)")
    }
    
    /// Cancel download
    public func cancel(_ taskId: String) {
        guard let task = tasks[taskId] else { return }
        
        task.sessionTask?.cancel()
        task.state = .cancelled
        
        activeDownloads.remove(taskId)
        
        if configuration.cleanupOnCompletion {
            tasks.removeValue(forKey: taskId)
        }
        
        logger.debug("Cancelled download: \(task.url.lastPathComponent)")
        processQueue()
    }
    
    /// Cancel all downloads
    public func cancelAll() {
        for taskId in tasks.keys {
            cancel(taskId)
        }
    }
    
    /// Get download task
    public func getTask(_ taskId: String) -> DownloadTask? {
        return tasks[taskId]
    }
    
    /// Get all tasks
    public func getAllTasks() -> [DownloadTask] {
        return Array(tasks.values)
    }
    
    /// Get active downloads
    public func getActiveDownloads() -> [DownloadTask] {
        return tasks.values.filter { $0.state.isActive }
    }
    
    /// Set progress handler
    public func onProgress(_ handler: @escaping (String, Double) -> Void) {
        self.progressHandler = handler
    }
    
    /// Set completion handler
    public func onCompletion(_ handler: @escaping (String, Result<URL, Error>) -> Void) {
        self.completionHandler = handler
    }
    
    /// Clear completed downloads
    public func clearCompleted() {
        let completedIds = tasks.values
            .filter { $0.state == .completed || $0.state == .cancelled }
            .map { $0.id }
        
        for id in completedIds {
            tasks.removeValue(forKey: id)
        }
        
        logger.debug("Cleared \(completedIds.count) completed downloads")
    }
    
    // MARK: - Private Methods
    
    private func processQueue() {
        guard activeDownloads.count < configuration.maxConcurrentDownloads else { return }
        
        // Find next waiting task
        for (index, item) in taskQueue.enumerated() {
            if item.task.state == .waiting {
                taskQueue.remove(at: index)
                startDownload(item.task)
                break
            }
        }
    }
    
    private func startDownload(_ task: DownloadTask) {
        guard activeDownloads.count < configuration.maxConcurrentDownloads else {
            // Add back to queue
            taskQueue.append((task, .normal))
            return
        }
        
        var request = URLRequest(url: task.url)
        request.timeoutInterval = configuration.timeout
        
        task.state = .downloading
        task.startTime = Date()
        task.sessionTask = session.downloadTask(with: request)
        task.sessionTask?.resume()
        
        activeDownloads.insert(task.id)
        logger.debug("Started download: \(task.url.lastPathComponent)")
    }
    
    private func handlePause(taskId: String, resumeData: Data?) {
        guard let task = tasks[taskId] else { return }
        
        task.state = .paused
        task.resumeData = resumeData
        
        activeDownloads.remove(taskId)
        logger.debug("Paused download: \(task.url.lastPathComponent)")
        
        processQueue()
    }
    
    private func defaultDestinationURL(for url: URL) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    private func updateSpeeds() {
        let now = Date()
        
        for task in tasks.values where task.state == .downloading {
            if let lastUpdate = task.lastUpdateTime {
                let timeDelta = now.timeIntervalSince(lastUpdate)
                let bytesDelta = task.bytesReceived - task.lastBytesReceived
                
                if timeDelta > 0 {
                    task.speed = Double(bytesDelta) / timeDelta
                    
                    // Calculate time remaining
                    if task.speed > 0 && task.totalBytes > 0 {
                        let bytesRemaining = task.totalBytes - task.bytesReceived
                        task.timeRemaining = TimeInterval(bytesRemaining) / task.speed
                    }
                }
            }
            
            task.lastUpdateTime = now
            task.lastBytesReceived = task.bytesReceived
        }
    }
    
    private func findTask(for sessionTask: URLSessionTask) -> DownloadTask? {
        return tasks.values.first { $0.sessionTask == sessionTask }
    }
}

// MARK: - URLSessionDownloadDelegate

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension DownloadManager: URLSessionDownloadDelegate {
    
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task {
            await handleDownloadCompletion(sessionTask: downloadTask, location: location)
        }
    }
    
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task {
            await handleProgress(
                sessionTask: downloadTask,
                bytesWritten: bytesWritten,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }
    
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        Task {
            await handleResume(
                sessionTask: downloadTask,
                fileOffset: fileOffset,
                expectedTotalBytes: expectedTotalBytes
            )
        }
    }
    
    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task {
            await handleTaskCompletion(sessionTask: task, error: error)
        }
    }
    
    // MARK: - Async Handlers
    
    private func handleDownloadCompletion(sessionTask: URLSessionDownloadTask, location: URL) {
        guard let task = findTask(for: sessionTask) else { return }
        
        do {
            // Move file to destination
            if FileManager.default.fileExists(atPath: task.destinationURL.path) {
                try FileManager.default.removeItem(at: task.destinationURL)
            }
            
            try FileManager.default.moveItem(at: location, to: task.destinationURL)
            
            task.state = .completed
            task.progress.completedUnitCount = task.progress.totalUnitCount
            
            activeDownloads.remove(task.id)
            completionHandler?(task.id, .success(task.destinationURL))
            
            logger.info("Download completed: \(task.url.lastPathComponent)")
            
            if configuration.cleanupOnCompletion {
                tasks.removeValue(forKey: task.id)
            }
            
            processQueue()
            
        } catch {
            task.state = .failed
            task.error = error
            
            activeDownloads.remove(task.id)
            completionHandler?(task.id, .failure(error))
            
            logger.error("Download failed to move file: \(error)")
            
            processQueue()
        }
    }
    
    private func handleProgress(
        sessionTask: URLSessionDownloadTask,
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let task = findTask(for: sessionTask) else { return }
        
        task.bytesReceived = totalBytesWritten
        task.totalBytes = totalBytesExpectedToWrite
        
        if totalBytesExpectedToWrite > 0 {
            task.progress.totalUnitCount = totalBytesExpectedToWrite
            task.progress.completedUnitCount = totalBytesWritten
            
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler?(task.id, progress)
        }
    }
    
    private func handleResume(
        sessionTask: URLSessionDownloadTask,
        fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let task = findTask(for: sessionTask) else { return }
        
        task.bytesReceived = fileOffset
        task.totalBytes = expectedTotalBytes
        
        logger.debug("Download resumed at offset: \(fileOffset)")
    }
    
    private func handleTaskCompletion(sessionTask: URLSessionTask, error: Error?) {
        guard let task = findTask(for: sessionTask) else { return }
        
        if let error = error {
            let nsError = error as NSError
            
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // Already handled in pause/cancel
                return
            }
            
            task.state = .failed
            task.error = error
            
            activeDownloads.remove(task.id)
            completionHandler?(task.id, .failure(error))
            
            logger.error("Download failed: \(error)")
            
            // Retry if configured
            if configuration.resumeOnFailure && configuration.retryCount > 0 {
                // Add retry logic here
            }
            
            processQueue()
        }
    }
}