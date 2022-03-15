import Foundation
import os.log
import Combine

/// Upload manager for handling file uploads
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor UploadManager: NSObject {
    
    // MARK: - Types
    
    /// Upload task
    public class UploadTask: ObservableObject {
        public let id: String
        public let url: URL
        public let fileURL: URL?
        public let data: Data?
        @Published public private(set) var state: State = .waiting
        @Published public private(set) var progress: Progress = Progress(totalUnitCount: 0)
        @Published public private(set) var bytesSent: Int64 = 0
        @Published public private(set) var totalBytes: Int64 = 0
        @Published public private(set) var speed: Double = 0
        @Published public private(set) var timeRemaining: TimeInterval?
        @Published public private(set) var response: URLResponse?
        @Published public private(set) var responseData: Data?
        @Published public private(set) var error: Error?
        
        internal var sessionTask: URLSessionUploadTask?
        internal var startTime: Date?
        internal var lastUpdateTime: Date?
        internal var lastBytesSent: Int64 = 0
        internal var retryCount: Int = 0
        
        public enum State {
            case waiting
            case uploading
            case paused
            case completed
            case failed
            case cancelled
            
            public var isActive: Bool {
                switch self {
                case .uploading, .waiting:
                    return true
                default:
                    return false
                }
            }
        }
        
        public init(
            id: String = UUID().uuidString,
            url: URL,
            fileURL: URL? = nil,
            data: Data? = nil
        ) {
            self.id = id
            self.url = url
            self.fileURL = fileURL
            self.data = data
            
            if let fileURL = fileURL {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        self.totalBytes = fileSize
                        self.progress.totalUnitCount = fileSize
                    }
                } catch {
                    // Handle error
                }
            } else if let data = data {
                self.totalBytes = Int64(data.count)
                self.progress.totalUnitCount = Int64(data.count)
            }
        }
        
        public var progressPercentage: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesSent) / Double(totalBytes)
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
    
    /// Upload configuration
    public struct Configuration {
        public let maxConcurrentUploads: Int
        public let allowsCellularAccess: Bool
        public let chunkSize: Int
        public let timeout: TimeInterval
        public let retryCount: Int
        public let resumeOnFailure: Bool
        public let useBackgroundSession: Bool
        public let compressionEnabled: Bool
        
        public init(
            maxConcurrentUploads: Int = 3,
            allowsCellularAccess: Bool = true,
            chunkSize: Int = 1024 * 1024, // 1MB chunks
            timeout: TimeInterval = 300,
            retryCount: Int = 3,
            resumeOnFailure: Bool = true,
            useBackgroundSession: Bool = false,
            compressionEnabled: Bool = false
        ) {
            self.maxConcurrentUploads = maxConcurrentUploads
            self.allowsCellularAccess = allowsCellularAccess
            self.chunkSize = chunkSize
            self.timeout = timeout
            self.retryCount = retryCount
            self.resumeOnFailure = resumeOnFailure
            self.useBackgroundSession = useBackgroundSession
            self.compressionEnabled = compressionEnabled
        }
        
        public static let `default` = Configuration()
        
        public static let background = Configuration(
            useBackgroundSession: true,
            timeout: 600
        )
        
        public static let largeFile = Configuration(
            chunkSize: 5 * 1024 * 1024, // 5MB chunks
            timeout: 1800,
            useBackgroundSession: true
        )
    }
    
    /// Upload priority
    public enum Priority: Int {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3
    }
    
    /// Upload method
    public enum UploadMethod {
        case put
        case post
        case patch
        case multipart(boundary: String? = nil)
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private var session: URLSession!
    private var tasks: [String: UploadTask] = [:]
    private var taskQueue: [(task: UploadTask, priority: Priority)] = []
    private var activeUploads: Set<String> = []
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "UploadManager")
    
    private var progressHandler: ((String, Double) -> Void)?
    private var completionHandler: ((String, Result<(URLResponse, Data?), Error>) -> Void)?
    private var speedUpdateTimer: Timer?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        let config: URLSessionConfiguration
        
        if configuration.useBackgroundSession {
            config = URLSessionConfiguration.background(withIdentifier: "com.swiftnetworkpro.upload")
        } else {
            config = URLSessionConfiguration.default
        }
        
        config.allowsCellularAccess = configuration.allowsCellularAccess
        config.timeoutIntervalForRequest = configuration.timeout
        config.httpMaximumConnectionsPerHost = configuration.maxConcurrentUploads
        
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
    
    /// Upload file
    @discardableResult
    public func uploadFile(
        _ fileURL: URL,
        to url: URL,
        method: UploadMethod = .post,
        headers: [String: String]? = nil,
        priority: Priority = .normal
    ) -> UploadTask {
        let task = UploadTask(url: url, fileURL: fileURL)
        
        tasks[task.id] = task
        taskQueue.append((task, priority))
        taskQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        logger.debug("Added file upload: \(fileURL.lastPathComponent)")
        
        processQueue()
        
        return task
    }
    
    /// Upload data
    @discardableResult
    public func uploadData(
        _ data: Data,
        to url: URL,
        method: UploadMethod = .post,
        headers: [String: String]? = nil,
        priority: Priority = .normal
    ) -> UploadTask {
        let task = UploadTask(url: url, data: data)
        
        tasks[task.id] = task
        taskQueue.append((task, priority))
        taskQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        logger.debug("Added data upload: \(data.count) bytes")
        
        processQueue()
        
        return task
    }
    
    /// Upload multipart form data
    @discardableResult
    public func uploadMultipart(
        _ multipartData: MultipartFormData,
        to url: URL,
        headers: [String: String]? = nil,
        priority: Priority = .normal
    ) -> UploadTask? {
        do {
            let data = try multipartData.encode()
            var uploadHeaders = headers ?? [:]
            uploadHeaders["Content-Type"] = multipartData.contentType
            
            return uploadData(
                data,
                to: url,
                method: .multipart(),
                headers: uploadHeaders,
                priority: priority
            )
        } catch {
            logger.error("Failed to encode multipart data: \(error)")
            return nil
        }
    }
    
    /// Upload JSON
    @discardableResult
    public func uploadJSON<T: Encodable>(
        _ object: T,
        to url: URL,
        method: UploadMethod = .post,
        headers: [String: String]? = nil,
        priority: Priority = .normal,
        encoder: JSONEncoder = JSONEncoder()
    ) -> UploadTask? {
        do {
            let data = try encoder.encode(object)
            var uploadHeaders = headers ?? [:]
            uploadHeaders["Content-Type"] = "application/json"
            
            return uploadData(
                data,
                to: url,
                method: method,
                headers: uploadHeaders,
                priority: priority
            )
        } catch {
            logger.error("Failed to encode JSON: \(error)")
            return nil
        }
    }
    
    /// Start upload
    public func start(_ taskId: String) {
        guard let task = tasks[taskId] else { return }
        
        switch task.state {
        case .paused:
            resume(taskId)
        case .waiting, .failed, .cancelled:
            startUpload(task)
        default:
            break
        }
    }
    
    /// Pause upload
    public func pause(_ taskId: String) {
        guard let task = tasks[taskId],
              task.state == .uploading else { return }
        
        task.sessionTask?.suspend()
        task.state = .paused
        
        activeUploads.remove(taskId)
        logger.debug("Paused upload: \(task.id)")
        
        processQueue()
    }
    
    /// Resume upload
    public func resume(_ taskId: String) {
        guard let task = tasks[taskId],
              task.state == .paused else { return }
        
        task.sessionTask?.resume()
        task.state = .uploading
        
        activeUploads.insert(taskId)
        logger.debug("Resumed upload: \(task.id)")
    }
    
    /// Cancel upload
    public func cancel(_ taskId: String) {
        guard let task = tasks[taskId] else { return }
        
        task.sessionTask?.cancel()
        task.state = .cancelled
        
        activeUploads.remove(taskId)
        tasks.removeValue(forKey: taskId)
        
        logger.debug("Cancelled upload: \(task.id)")
        processQueue()
    }
    
    /// Cancel all uploads
    public func cancelAll() {
        for taskId in tasks.keys {
            cancel(taskId)
        }
    }
    
    /// Retry failed upload
    public func retry(_ taskId: String) {
        guard let task = tasks[taskId],
              task.state == .failed else { return }
        
        task.retryCount += 1
        task.state = .waiting
        task.error = nil
        
        taskQueue.append((task, .normal))
        processQueue()
        
        logger.debug("Retrying upload: \(task.id) (attempt \(task.retryCount))")
    }
    
    /// Get upload task
    public func getTask(_ taskId: String) -> UploadTask? {
        return tasks[taskId]
    }
    
    /// Get all tasks
    public func getAllTasks() -> [UploadTask] {
        return Array(tasks.values)
    }
    
    /// Get active uploads
    public func getActiveUploads() -> [UploadTask] {
        return tasks.values.filter { $0.state.isActive }
    }
    
    /// Set progress handler
    public func onProgress(_ handler: @escaping (String, Double) -> Void) {
        self.progressHandler = handler
    }
    
    /// Set completion handler
    public func onCompletion(_ handler: @escaping (String, Result<(URLResponse, Data?), Error>) -> Void) {
        self.completionHandler = handler
    }
    
    /// Clear completed uploads
    public func clearCompleted() {
        let completedIds = tasks.values
            .filter { $0.state == .completed || $0.state == .cancelled }
            .map { $0.id }
        
        for id in completedIds {
            tasks.removeValue(forKey: id)
        }
        
        logger.debug("Cleared \(completedIds.count) completed uploads")
    }
    
    // MARK: - Private Methods
    
    private func processQueue() {
        guard activeUploads.count < configuration.maxConcurrentUploads else { return }
        
        // Find next waiting task
        for (index, item) in taskQueue.enumerated() {
            if item.task.state == .waiting {
                taskQueue.remove(at: index)
                startUpload(item.task)
                break
            }
        }
    }
    
    private func startUpload(_ task: UploadTask) {
        guard activeUploads.count < configuration.maxConcurrentUploads else {
            taskQueue.append((task, .normal))
            return
        }
        
        var request = URLRequest(url: task.url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        
        task.state = .uploading
        task.startTime = Date()
        
        if let fileURL = task.fileURL {
            task.sessionTask = session.uploadTask(with: request, fromFile: fileURL)
        } else if let data = task.data {
            task.sessionTask = session.uploadTask(with: request, from: data)
        } else {
            task.state = .failed
            task.error = NetworkError.invalidRequest("No data or file to upload")
            return
        }
        
        task.sessionTask?.resume()
        activeUploads.insert(task.id)
        
        logger.debug("Started upload: \(task.id)")
    }
    
    private func updateSpeeds() {
        let now = Date()
        
        for task in tasks.values where task.state == .uploading {
            if let lastUpdate = task.lastUpdateTime {
                let timeDelta = now.timeIntervalSince(lastUpdate)
                let bytesDelta = task.bytesSent - task.lastBytesSent
                
                if timeDelta > 0 {
                    task.speed = Double(bytesDelta) / timeDelta
                    
                    // Calculate time remaining
                    if task.speed > 0 && task.totalBytes > 0 {
                        let bytesRemaining = task.totalBytes - task.bytesSent
                        task.timeRemaining = TimeInterval(bytesRemaining) / task.speed
                    }
                }
            }
            
            task.lastUpdateTime = now
            task.lastBytesSent = task.bytesSent
        }
    }
    
    private func findTask(for sessionTask: URLSessionTask) -> UploadTask? {
        return tasks.values.first { $0.sessionTask == sessionTask }
    }
}

// MARK: - URLSessionTaskDelegate

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension UploadManager: URLSessionTaskDelegate {
    
    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        Task {
            await handleProgress(
                sessionTask: task,
                bytesSent: bytesSent,
                totalBytesSent: totalBytesSent,
                totalBytesExpectedToSend: totalBytesExpectedToSend
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
    
    public nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        Task {
            await handleDataReceived(sessionTask: dataTask, data: data)
        }
    }
    
    public nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        Task {
            await handleResponse(sessionTask: dataTask, response: response)
            completionHandler(.allow)
        }
    }
    
    // MARK: - Async Handlers
    
    private func handleProgress(
        sessionTask: URLSessionTask,
        bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let task = findTask(for: sessionTask) else { return }
        
        task.bytesSent = totalBytesSent
        task.totalBytes = totalBytesExpectedToSend
        
        if totalBytesExpectedToSend > 0 {
            task.progress.totalUnitCount = totalBytesExpectedToSend
            task.progress.completedUnitCount = totalBytesSent
            
            let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            progressHandler?(task.id, progress)
        }
    }
    
    private func handleDataReceived(sessionTask: URLSessionDataTask, data: Data) {
        guard let task = findTask(for: sessionTask) else { return }
        
        if task.responseData == nil {
            task.responseData = data
        } else {
            task.responseData?.append(data)
        }
    }
    
    private func handleResponse(sessionTask: URLSessionDataTask, response: URLResponse) {
        guard let task = findTask(for: sessionTask) else { return }
        
        task.response = response
    }
    
    private func handleTaskCompletion(sessionTask: URLSessionTask, error: Error?) {
        guard let task = findTask(for: sessionTask) else { return }
        
        if let error = error {
            let nsError = error as NSError
            
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // Already handled in cancel
                return
            }
            
            task.state = .failed
            task.error = error
            
            activeUploads.remove(task.id)
            completionHandler?(task.id, .failure(error))
            
            logger.error("Upload failed: \(error)")
            
            // Retry if configured
            if configuration.resumeOnFailure && task.retryCount < configuration.retryCount {
                retry(task.id)
            }
            
            processQueue()
            
        } else {
            task.state = .completed
            task.progress.completedUnitCount = task.progress.totalUnitCount
            
            activeUploads.remove(task.id)
            
            if let response = task.response {
                completionHandler?(task.id, .success((response, task.responseData)))
            }
            
            logger.info("Upload completed: \(task.id)")
            
            processQueue()
        }
    }
}

// MARK: - Chunked Upload Support

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
extension UploadManager {
    
    /// Upload file in chunks
    public func uploadFileInChunks(
        _ fileURL: URL,
        to url: URL,
        chunkSize: Int? = nil,
        headers: [String: String]? = nil,
        priority: Priority = .normal
    ) async throws -> URLResponse {
        let actualChunkSize = chunkSize ?? configuration.chunkSize
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NetworkError.fileNotFound(fileURL.path)
        }
        
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { fileHandle.closeFile() }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        var offset: Int64 = 0
        var chunkNumber = 0
        let totalChunks = Int(ceil(Double(fileSize) / Double(actualChunkSize)))
        
        logger.info("Starting chunked upload: \(fileURL.lastPathComponent) (\(totalChunks) chunks)")
        
        while offset < fileSize {
            fileHandle.seek(toFileOffset: UInt64(offset))
            let chunkData = fileHandle.readData(ofLength: actualChunkSize)
            
            if chunkData.isEmpty {
                break
            }
            
            let chunkEnd = min(offset + Int64(chunkData.count) - 1, fileSize - 1)
            
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.httpBody = chunkData
            request.setValue("bytes \(offset)-\(chunkEnd)/\(fileSize)", forHTTPHeaderField: "Content-Range")
            request.setValue("\(chunkData.count)", forHTTPHeaderField: "Content-Length")
            
            headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.invalidStatusCode(httpResponse.statusCode, data: nil)
                }
            }
            
            offset += Int64(chunkData.count)
            chunkNumber += 1
            
            logger.debug("Uploaded chunk \(chunkNumber)/\(totalChunks)")
        }
        
        logger.info("Completed chunked upload: \(fileURL.lastPathComponent)")
        
        return HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}