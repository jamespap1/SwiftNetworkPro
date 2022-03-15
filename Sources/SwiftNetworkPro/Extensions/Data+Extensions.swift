import Foundation
import CryptoKit
import Compression

/// Data extensions for SwiftNetworkPro
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public extension Data {
    
    // MARK: - Encoding/Decoding
    
    /// Convert to hex string
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Initialize from hex string
    init?(hexString: String) {
        let hexString = hexString.replacingOccurrences(of: " ", with: "")
        let len = hexString.count / 2
        var data = Data(capacity: len)
        
        for i in 0..<len {
            let j = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            guard let num = UInt8(bytes, radix: 16) else { return nil }
            data.append(num)
        }
        
        self = data
    }
    
    /// Base64 URL encoded string
    var base64URLEncodedString: String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Initialize from base64 URL encoded string
    init?(base64URLEncoded: String) {
        var base64 = base64URLEncoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        
        self.init(base64Encoded: base64)
    }
    
    // MARK: - JSON
    
    /// Convert to JSON object
    func jsonObject(options: JSONSerialization.ReadingOptions = []) throws -> Any {
        return try JSONSerialization.jsonObject(with: self, options: options)
    }
    
    /// Convert to JSON dictionary
    func jsonDictionary(options: JSONSerialization.ReadingOptions = []) throws -> [String: Any] {
        guard let dict = try jsonObject(options: options) as? [String: Any] else {
            throw NetworkError.decodingFailed(NSError(domain: "Invalid JSON dictionary", code: 0))
        }
        return dict
    }
    
    /// Convert to JSON array
    func jsonArray(options: JSONSerialization.ReadingOptions = []) throws -> [Any] {
        guard let array = try jsonObject(options: options) as? [Any] else {
            throw NetworkError.decodingFailed(NSError(domain: "Invalid JSON array", code: 0))
        }
        return array
    }
    
    /// Decode JSON to type
    func decode<T: Decodable>(
        _ type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        return try decoder.decode(type, from: self)
    }
    
    /// Pretty print JSON
    var prettyPrintedJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    // MARK: - String Conversion
    
    /// Convert to string
    func string(encoding: String.Encoding = .utf8) -> String? {
        return String(data: self, encoding: encoding)
    }
    
    /// Convert to UTF-8 string
    var utf8String: String? {
        return string(encoding: .utf8)
    }
    
    // MARK: - Compression
    
    /// Compress data
    func compressed(using algorithm: CompressionAlgorithm = .zlib) -> Data? {
        return self.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { buffer.deallocate() }
            
            let compressedSize = compression_encode_buffer(
                buffer, count,
                bytes.bindMemory(to: UInt8.self).baseAddress!, count,
                nil, algorithm.algorithm
            )
            
            guard compressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: compressedSize)
        }
    }
    
    /// Decompress data
    func decompressed(using algorithm: CompressionAlgorithm = .zlib) -> Data? {
        return self.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
            defer { buffer.deallocate() }
            
            let decompressedSize = compression_decode_buffer(
                buffer, count * 4,
                bytes.bindMemory(to: UInt8.self).baseAddress!, count,
                nil, algorithm.algorithm
            )
            
            guard decompressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: decompressedSize)
        }
    }
    
    /// Compression algorithm
    enum CompressionAlgorithm {
        case zlib
        case lzfse
        case lz4
        case lzma
        
        var algorithm: compression_algorithm {
            switch self {
            case .zlib: return COMPRESSION_ZLIB
            case .lzfse: return COMPRESSION_LZFSE
            case .lz4: return COMPRESSION_LZ4
            case .lzma: return COMPRESSION_LZMA
            }
        }
    }
    
    /// Get compression ratio
    var compressionRatio: Double {
        guard let compressed = self.compressed() else { return 1.0 }
        return Double(compressed.count) / Double(count)
    }
    
    // MARK: - Hashing
    
    /// MD5 hash
    var md5: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// SHA1 hash
    var sha1: String {
        let digest = Insecure.SHA1.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// SHA256 hash
    var sha256: String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// SHA384 hash
    var sha384: String {
        let digest = SHA384.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// SHA512 hash
    var sha512: String {
        let digest = SHA512.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // MARK: - Encryption
    
    /// Encrypt with AES
    func aesEncrypted(key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(self, using: key)
        return sealedBox.combined ?? self
    }
    
    /// Decrypt with AES
    func aesDecrypted(key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: self)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Encrypt with ChaCha20
    func chachaEncrypted(key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(self, using: key)
        return sealedBox.combined
    }
    
    /// Decrypt with ChaCha20
    func chachaDecrypted(key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: self)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
    
    // MARK: - Chunking
    
    /// Split data into chunks
    func chunked(size: Int) -> [Data] {
        guard size > 0 else { return [self] }
        
        var chunks: [Data] = []
        var offset = 0
        
        while offset < count {
            let chunkSize = Swift.min(size, count - offset)
            let chunk = self[offset..<offset + chunkSize]
            chunks.append(chunk)
            offset += chunkSize
        }
        
        return chunks
    }
    
    /// Get subdata safely
    func subdata(from start: Int, to end: Int) -> Data? {
        guard start >= 0, end <= count, start < end else { return nil }
        return subdata(in: start..<end)
    }
    
    // MARK: - File Operations
    
    /// Write to file atomically
    func writeAtomic(to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try write(to: tempURL)
        try FileManager.default.replaceItem(at: url, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
    }
    
    /// Append to file
    func append(to url: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: url)
        }
    }
    
    // MARK: - Byte Operations
    
    /// Get bytes as array
    var bytes: [UInt8] {
        return [UInt8](self)
    }
    
    /// Initialize from bytes
    init(bytes: [UInt8]) {
        self = Data(bytes)
    }
    
    /// XOR with another data
    func xor(with key: Data) -> Data {
        var result = Data(capacity: count)
        
        for i in 0..<count {
            let byte = self[i] ^ key[i % key.count]
            result.append(byte)
        }
        
        return result
    }
    
    // MARK: - Formatting
    
    /// Format as human readable size
    var humanReadableSize: String {
        return ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }
    
    /// Format as hex dump
    var hexDump: String {
        var result = ""
        var offset = 0
        
        while offset < count {
            // Offset
            result += String(format: "%08x  ", offset)
            
            // Hex bytes
            for i in 0..<16 {
                if offset + i < count {
                    result += String(format: "%02x ", self[offset + i])
                } else {
                    result += "   "
                }
                
                if i == 7 {
                    result += " "
                }
            }
            
            result += " |"
            
            // ASCII representation
            for i in 0..<16 {
                if offset + i < count {
                    let byte = self[offset + i]
                    if byte >= 0x20 && byte < 0x7F {
                        result += String(Character(UnicodeScalar(byte)))
                    } else {
                        result += "."
                    }
                }
            }
            
            result += "|\n"
            offset += 16
        }
        
        return result
    }
    
    // MARK: - Validation
    
    /// Check if data is valid UTF-8
    var isValidUTF8: Bool {
        return String(data: self, encoding: .utf8) != nil
    }
    
    /// Check if data is valid JSON
    var isValidJSON: Bool {
        return (try? JSONSerialization.jsonObject(with: self)) != nil
    }
    
    /// Check if data is likely binary
    var isLikelyBinary: Bool {
        // Check first 8192 bytes for null bytes
        let sampleSize = Swift.min(8192, count)
        let sample = self[0..<sampleSize]
        return sample.contains(0)
    }
    
    // MARK: - MIME Type Detection
    
    /// Detect MIME type from magic bytes
    var mimeType: String? {
        guard count > 0 else { return nil }
        
        let bytes = self.prefix(12).bytes
        
        // Image formats
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.starts(with: [0x42, 0x4D]) { return "image/bmp" }
        if bytes.starts(with: [0x00, 0x00, 0x01, 0x00]) { return "image/x-icon" }
        
        // Video formats
        if bytes.starts(with: [0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70]) { return "video/mp4" }
        if bytes.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return "video/webm" }
        
        // Audio formats
        if bytes.starts(with: [0x49, 0x44, 0x33]) { return "audio/mpeg" }
        if bytes.starts(with: [0xFF, 0xFB]) { return "audio/mpeg" }
        if bytes.starts(with: [0x4F, 0x67, 0x67, 0x53]) { return "audio/ogg" }
        
        // Document formats
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return "application/zip" }
        if bytes.starts(with: [0x1F, 0x8B, 0x08]) { return "application/gzip" }
        
        // Text formats
        if isValidUTF8 {
            if isValidJSON { return "application/json" }
            if utf8String?.hasPrefix("<?xml") == true { return "application/xml" }
            if utf8String?.hasPrefix("<!DOCTYPE html") == true { return "text/html" }
            return "text/plain"
        }
        
        return "application/octet-stream"
    }
}