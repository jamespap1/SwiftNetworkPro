import Foundation
import CryptoKit
import os.log

/// Advanced cache manager for network responses
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public actor CacheManager {
    
    // MARK: - Properties
    
    /// Cache storage type
    public enum StorageType {
        case memory
        case disk
        case hybrid
    }
    
    /// Cache eviction policy
    public enum EvictionPolicy {
        case lru // Least Recently Used
        case lfu // Least Frequently Used
        case fifo // First In First Out
        case ttl // Time To Live
        case size // Size-based
    }
    
    /// Cache configuration
    public struct Configuration {
        public let storageType: StorageType
        public let evictionPolicy: EvictionPolicy
        public let maxMemorySize: Int // In bytes
        public let maxDiskSize: Int // In bytes
        public let defaultTTL: TimeInterval
        public let cleanupInterval: TimeInterval
        public let compressionEnabled: Bool
        public let encryptionEnabled: Bool
        
        public init(
            storageType: StorageType = .hybrid,
            evictionPolicy: EvictionPolicy = .lru,
            maxMemorySize: Int = 50 * 1024 * 1024, // 50 MB
            maxDiskSize: Int = 200 * 1024 * 1024, // 200 MB
            defaultTTL: TimeInterval = 3600, // 1 hour
            cleanupInterval: TimeInterval = 300, // 5 minutes
            compressionEnabled: Bool = true,
            encryptionEnabled: Bool = false
        ) {
            self.storageType = storageType
            self.evictionPolicy = evictionPolicy
            self.maxMemorySize = maxMemorySize
            self.maxDiskSize = maxDiskSize
            self.defaultTTL = defaultTTL
            self.cleanupInterval = cleanupInterval
            self.compressionEnabled = compressionEnabled
            self.encryptionEnabled = encryptionEnabled
        }
        
        public static let `default` = Configuration()
        
        public static let performance = Configuration(
            storageType: .memory,
            evictionPolicy: .lru,
            maxMemorySize: 100 * 1024 * 1024,
            compressionEnabled: false
        )
        
        public static let persistent = Configuration(
            storageType: .disk,
            evictionPolicy: .ttl,
            maxDiskSize: 500 * 1024 * 1024,
            encryptionEnabled: true
        )
    }
    
    /// Cache entry
    private struct CacheEntry {
        let key: String
        let data: Data
        let metadata: Metadata
        let createdAt: Date
        var lastAccessedAt: Date
        var accessCount: Int
        
        struct Metadata {
            let url: String?
            let headers: [String: String]?
            let statusCode: Int?
            let ttl: TimeInterval
            let compressed: Bool
            let encrypted: Bool
            let size: Int
        }
        
        var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > metadata.ttl
        }
        
        var age: TimeInterval {
            Date().timeIntervalSince(createdAt)
        }
    }
    
    /// Cache statistics
    public struct Statistics {
        public let totalEntries: Int
        public let memoryUsage: Int
        public let diskUsage: Int
        public let hitCount: Int
        public let missCount: Int
        public let evictionCount: Int
        public let averageAccessTime: TimeInterval
        
        public var hitRate: Double {
            let total = hitCount + missCount
            return total > 0 ? Double(hitCount) / Double(total) : 0
        }
    }
    
    // Private properties
    private let configuration: Configuration
    private var memoryCache: [String: CacheEntry] = [:]
    private var diskCacheURL: URL?
    private var statistics = Statistics(
        totalEntries: 0,
        memoryUsage: 0,
        diskUsage: 0,
        hitCount: 0,
        missCount: 0,
        evictionCount: 0,
        averageAccessTime: 0
    )
    
    private var hitCount = 0
    private var missCount = 0
    private var evictionCount = 0
    private var totalAccessTime: TimeInterval = 0
    private var accessCount = 0
    
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Cache")
    private var cleanupTask: Task<Void, Never>?
    
    private let encryptionKey: SymmetricKey?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        
        // Setup encryption key if needed
        if configuration.encryptionEnabled {
            self.encryptionKey = SymmetricKey(size: .bits256)
        } else {
            self.encryptionKey = nil
        }
        
        // Setup disk cache directory
        if configuration.storageType == .disk || configuration.storageType == .hybrid {
            setupDiskCache()
        }
        
        // Start cleanup task
        startCleanupTask()
    }
    
    deinit {
        cleanupTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Store data in cache
    public func store(
        _ data: Data,
        for key: String,
        ttl: TimeInterval? = nil,
        metadata: [String: Any]? = nil
    ) async throws {
        let startTime = Date()
        
        // Process data
        var processedData = data
        var compressed = false
        var encrypted = false
        
        // Compress if enabled and data is large enough
        if configuration.compressionEnabled && data.count > 1024 {
            if let compressedData = compress(data) {
                processedData = compressedData
                compressed = true
            }
        }
        
        // Encrypt if enabled
        if configuration.encryptionEnabled, let key = encryptionKey {
            processedData = try encrypt(processedData, with: key)
            encrypted = true
        }
        
        // Create cache entry
        let entry = CacheEntry(
            key: key,
            data: processedData,
            metadata: CacheEntry.Metadata(
                url: metadata?["url"] as? String,
                headers: metadata?["headers"] as? [String: String],
                statusCode: metadata?["statusCode"] as? Int,
                ttl: ttl ?? configuration.defaultTTL,
                compressed: compressed,
                encrypted: encrypted,
                size: processedData.count
            ),
            createdAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 0
        )
        
        // Store based on storage type
        switch configuration.storageType {
        case .memory:
            await storeInMemory(entry)
        case .disk:
            try await storeOnDisk(entry)
        case .hybrid:
            await storeInMemory(entry)
            try await storeOnDisk(entry)
        }
        
        // Update statistics
        let accessTime = Date().timeIntervalSince(startTime)
        updateAccessStatistics(accessTime)
        
        logger.debug("Cached data for key: \(key) (size: \(processedData.count) bytes, compressed: \(compressed), encrypted: \(encrypted))")
    }
    
    /// Retrieve data from cache
    public func retrieve(for key: String) async throws -> Data? {
        let startTime = Date()
        
        // Check memory cache first
        if let entry = memoryCache[key] {
            if !entry.isExpired {
                // Update access info
                memoryCache[key]?.lastAccessedAt = Date()
                memoryCache[key]?.accessCount += 1
                
                hitCount += 1
                
                // Decrypt and decompress if needed
                let data = try processRetrievedData(entry)
                
                // Update statistics
                let accessTime = Date().timeIntervalSince(startTime)
                updateAccessStatistics(accessTime)
                
                logger.debug("Cache hit for key: \(key) (memory)")
                return data
            } else {
                // Remove expired entry
                memoryCache.removeValue(forKey: key)
                evictionCount += 1
            }
        }
        
        // Check disk cache if applicable
        if configuration.storageType == .disk || configuration.storageType == .hybrid {
            if let entry = try await retrieveFromDisk(key) {
                if !entry.isExpired {
                    hitCount += 1
                    
                    // Promote to memory cache if hybrid
                    if configuration.storageType == .hybrid {
                        await storeInMemory(entry)
                    }
                    
                    // Decrypt and decompress if needed
                    let data = try processRetrievedData(entry)
                    
                    // Update statistics
                    let accessTime = Date().timeIntervalSince(startTime)
                    updateAccessStatistics(accessTime)
                    
                    logger.debug("Cache hit for key: \(key) (disk)")
                    return data
                } else {
                    // Remove expired entry
                    try await removeFromDisk(key)
                    evictionCount += 1
                }
            }
        }
        
        missCount += 1
        
        // Update statistics
        let accessTime = Date().timeIntervalSince(startTime)
        updateAccessStatistics(accessTime)
        
        logger.debug("Cache miss for key: \(key)")
        return nil
    }
    
    /// Remove data from cache
    public func remove(for key: String) async throws {
        memoryCache.removeValue(forKey: key)
        
        if configuration.storageType == .disk || configuration.storageType == .hybrid {
            try await removeFromDisk(key)
        }
        
        logger.debug("Removed cache entry for key: \(key)")
    }
    
    /// Clear all cache
    public func clearAll() async throws {
        memoryCache.removeAll()
        
        if configuration.storageType == .disk || configuration.storageType == .hybrid {
            try await clearDiskCache()
        }
        
        // Reset statistics
        hitCount = 0
        missCount = 0
        evictionCount = 0
        totalAccessTime = 0
        accessCount = 0
        
        logger.info("Cleared all cache")
    }
    
    /// Get cache statistics
    public func getStatistics() -> Statistics {
        let memoryUsage = memoryCache.values.reduce(0) { $0 + $1.data.count }
        let diskUsage = calculateDiskUsage()
        
        return Statistics(
            totalEntries: memoryCache.count,
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            hitCount: hitCount,
            missCount: missCount,
            evictionCount: evictionCount,
            averageAccessTime: accessCount > 0 ? totalAccessTime / Double(accessCount) : 0
        )
    }
    
    /// Check if key exists in cache
    public func contains(_ key: String) async -> Bool {
        if memoryCache[key] != nil {
            return true
        }
        
        if configuration.storageType == .disk || configuration.storageType == .hybrid {
            return await diskCacheExists(key)
        }
        
        return false
    }
    
    /// Get all cache keys
    public func getAllKeys() -> [String] {
        return Array(memoryCache.keys)
    }
    
    /// Preload cache entries
    public func preload(keys: [String]) async {
        guard configuration.storageType == .disk || configuration.storageType == .hybrid else {
            return
        }
        
        for key in keys {
            if let entry = try? await retrieveFromDisk(key), !entry.isExpired {
                await storeInMemory(entry)
            }
        }
        
        logger.info("Preloaded \(keys.count) cache entries")
    }
    
    // MARK: - Private Methods
    
    private func setupDiskCache() {
        let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SwiftNetworkPro")
        
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        
        diskCacheURL = cacheDirectory
    }
    
    private func startCleanupTask() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(configuration.cleanupInterval * 1_000_000_000))
                await performCleanup()
            }
        }
    }
    
    private func performCleanup() async {
        let startTime = Date()
        var removedCount = 0
        
        // Remove expired entries from memory
        let expiredKeys = memoryCache.compactMap { entry in
            entry.value.isExpired ? entry.key : nil
        }
        
        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
            removedCount += 1
        }
        
        // Apply eviction policy if needed
        await applyEvictionPolicy()
        
        // Clean disk cache
        if configuration.storageType == .disk || configuration.storageType == .hybrid {
            removedCount += await cleanDiskCache()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        logger.info("Cleanup completed: removed \(removedCount) entries in \(duration)s")
    }
    
    private func applyEvictionPolicy() async {
        let memoryUsage = memoryCache.values.reduce(0) { $0 + $1.data.count }
        
        guard memoryUsage > configuration.maxMemorySize else {
            return
        }
        
        let targetSize = Int(Double(configuration.maxMemorySize) * 0.75) // Reduce to 75%
        var currentSize = memoryUsage
        
        switch configuration.evictionPolicy {
        case .lru:
            // Sort by last accessed time
            let sorted = memoryCache.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            for (key, entry) in sorted {
                if currentSize <= targetSize { break }
                memoryCache.removeValue(forKey: key)
                currentSize -= entry.data.count
                evictionCount += 1
            }
            
        case .lfu:
            // Sort by access count
            let sorted = memoryCache.sorted { $0.value.accessCount < $1.value.accessCount }
            for (key, entry) in sorted {
                if currentSize <= targetSize { break }
                memoryCache.removeValue(forKey: key)
                currentSize -= entry.data.count
                evictionCount += 1
            }
            
        case .fifo:
            // Sort by creation time
            let sorted = memoryCache.sorted { $0.value.createdAt < $1.value.createdAt }
            for (key, entry) in sorted {
                if currentSize <= targetSize { break }
                memoryCache.removeValue(forKey: key)
                currentSize -= entry.data.count
                evictionCount += 1
            }
            
        case .ttl:
            // Sort by remaining TTL
            let sorted = memoryCache.sorted { $0.value.age > $1.value.age }
            for (key, entry) in sorted {
                if currentSize <= targetSize { break }
                memoryCache.removeValue(forKey: key)
                currentSize -= entry.data.count
                evictionCount += 1
            }
            
        case .size:
            // Sort by size (largest first)
            let sorted = memoryCache.sorted { $0.value.data.count > $1.value.data.count }
            for (key, entry) in sorted {
                if currentSize <= targetSize { break }
                memoryCache.removeValue(forKey: key)
                currentSize -= entry.data.count
                evictionCount += 1
            }
        }
    }
    
    private func storeInMemory(_ entry: CacheEntry) async {
        memoryCache[entry.key] = entry
        await applyEvictionPolicy()
    }
    
    private func storeOnDisk(_ entry: CacheEntry) async throws {
        guard let diskCacheURL = diskCacheURL else { return }
        
        let fileURL = diskCacheURL.appendingPathComponent(entry.key.toFileName())
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(DiskCacheEntry(from: entry))
        
        try data.write(to: fileURL)
    }
    
    private func retrieveFromDisk(_ key: String) async throws -> CacheEntry? {
        guard let diskCacheURL = diskCacheURL else { return nil }
        
        let fileURL = diskCacheURL.appendingPathComponent(key.toFileName())
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let diskEntry = try decoder.decode(DiskCacheEntry.self, from: data)
        
        return diskEntry.toCacheEntry()
    }
    
    private func removeFromDisk(_ key: String) async throws {
        guard let diskCacheURL = diskCacheURL else { return }
        
        let fileURL = diskCacheURL.appendingPathComponent(key.toFileName())
        try FileManager.default.removeItem(at: fileURL)
    }
    
    private func clearDiskCache() async throws {
        guard let diskCacheURL = diskCacheURL else { return }
        
        let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    private func cleanDiskCache() async -> Int {
        guard let diskCacheURL = diskCacheURL else { return 0 }
        
        var removedCount = 0
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.creationDateKey])
            
            for file in files {
                let attributes = try file.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = attributes.creationDate {
                    let age = Date().timeIntervalSince(creationDate)
                    if age > configuration.defaultTTL {
                        try FileManager.default.removeItem(at: file)
                        removedCount += 1
                    }
                }
            }
        } catch {
            logger.error("Error cleaning disk cache: \(error)")
        }
        
        return removedCount
    }
    
    private func diskCacheExists(_ key: String) async -> Bool {
        guard let diskCacheURL = diskCacheURL else { return false }
        
        let fileURL = diskCacheURL.appendingPathComponent(key.toFileName())
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    private func calculateDiskUsage() -> Int {
        guard let diskCacheURL = diskCacheURL else { return 0 }
        
        var totalSize = 0
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey])
            
            for file in files {
                let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += attributes.fileSize ?? 0
            }
        } catch {
            logger.error("Error calculating disk usage: \(error)")
        }
        
        return totalSize
    }
    
    private func processRetrievedData(_ entry: CacheEntry) throws -> Data {
        var data = entry.data
        
        // Decrypt if needed
        if entry.metadata.encrypted, let key = encryptionKey {
            data = try decrypt(data, with: key)
        }
        
        // Decompress if needed
        if entry.metadata.compressed {
            if let decompressed = decompress(data) {
                data = decompressed
            }
        }
        
        return data
    }
    
    private func updateAccessStatistics(_ accessTime: TimeInterval) {
        totalAccessTime += accessTime
        accessCount += 1
    }
    
    // MARK: - Compression
    
    private func compress(_ data: Data) -> Data? {
        return data.compressed()
    }
    
    private func decompress(_ data: Data) -> Data? {
        return data.decompressed()
    }
    
    // MARK: - Encryption
    
    private func encrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined ?? data
    }
    
    private func decrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

// MARK: - Helper Types

private struct DiskCacheEntry: Codable {
    let key: String
    let data: Data
    let url: String?
    let headers: [String: String]?
    let statusCode: Int?
    let ttl: TimeInterval
    let compressed: Bool
    let encrypted: Bool
    let size: Int
    let createdAt: Date
    let lastAccessedAt: Date
    let accessCount: Int
    
    init(from entry: CacheManager.CacheEntry) {
        self.key = entry.key
        self.data = entry.data
        self.url = entry.metadata.url
        self.headers = entry.metadata.headers
        self.statusCode = entry.metadata.statusCode
        self.ttl = entry.metadata.ttl
        self.compressed = entry.metadata.compressed
        self.encrypted = entry.metadata.encrypted
        self.size = entry.metadata.size
        self.createdAt = entry.createdAt
        self.lastAccessedAt = entry.lastAccessedAt
        self.accessCount = entry.accessCount
    }
    
    func toCacheEntry() -> CacheManager.CacheEntry {
        return CacheManager.CacheEntry(
            key: key,
            data: data,
            metadata: CacheManager.CacheEntry.Metadata(
                url: url,
                headers: headers,
                statusCode: statusCode,
                ttl: ttl,
                compressed: compressed,
                encrypted: encrypted,
                size: size
            ),
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            accessCount: accessCount
        )
    }
}

// MARK: - Extensions

private extension String {
    func toFileName() -> String {
        // Convert to a safe filename using SHA256 hash
        let inputData = Data(self.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    func compressed() -> Data? {
        return self.compress(algorithm: .zlib)
    }
    
    func decompressed() -> Data? {
        return self.decompress(algorithm: .zlib)
    }
    
    func compress(algorithm: CompressionAlgorithm) -> Data? {
        return self.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { buffer.deallocate() }
            
            let compressedSize = compression_encode_buffer(
                buffer, count,
                bytes.bindMemory(to: UInt8.self).baseAddress!, count,
                nil, algorithm.rawValue
            )
            
            guard compressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: compressedSize)
        }
    }
    
    func decompress(algorithm: CompressionAlgorithm) -> Data? {
        return self.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
            defer { buffer.deallocate() }
            
            let decompressedSize = compression_decode_buffer(
                buffer, count * 4,
                bytes.bindMemory(to: UInt8.self).baseAddress!, count,
                nil, algorithm.rawValue
            )
            
            guard decompressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: decompressedSize)
        }
    }
}

private enum CompressionAlgorithm {
    case zlib
    case lzfse
    case lz4
    case lzma
    
    var rawValue: compression_algorithm {
        switch self {
        case .zlib: return COMPRESSION_ZLIB
        case .lzfse: return COMPRESSION_LZFSE
        case .lz4: return COMPRESSION_LZ4
        case .lzma: return COMPRESSION_LZMA
        }
    }
}