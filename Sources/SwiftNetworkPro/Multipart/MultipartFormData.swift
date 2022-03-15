import Foundation
import UniformTypeIdentifiers
import os.log

/// Multipart form data builder
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class MultipartFormData {
    
    // MARK: - Types
    
    /// Form data part
    public struct Part {
        public let name: String
        public let fileName: String?
        public let mimeType: String?
        public let data: Data
        public let headers: [String: String]
        
        public init(
            name: String,
            fileName: String? = nil,
            mimeType: String? = nil,
            data: Data,
            headers: [String: String] = [:]
        ) {
            self.name = name
            self.fileName = fileName
            self.mimeType = mimeType
            self.data = data
            self.headers = headers
        }
    }
    
    /// Encoding error
    public enum EncodingError: LocalizedError {
        case invalidURL(String)
        case fileNotFound(String)
        case dataConversionFailed
        case streamCreationFailed
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .dataConversionFailed:
                return "Failed to convert data"
            case .streamCreationFailed:
                return "Failed to create stream"
            }
        }
    }
    
    // MARK: - Properties
    
    private var parts: [Part] = []
    private let boundary: String
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "Multipart")
    
    public var contentType: String {
        return "multipart/form-data; boundary=\(boundary)"
    }
    
    public var count: Int {
        return parts.count
    }
    
    public var isEmpty: Bool {
        return parts.isEmpty
    }
    
    // MARK: - Initialization
    
    public init(boundary: String? = nil) {
        self.boundary = boundary ?? Self.generateBoundary()
    }
    
    // MARK: - Public Methods
    
    /// Append data
    public func append(
        _ data: Data,
        withName name: String,
        fileName: String? = nil,
        mimeType: String? = nil,
        headers: [String: String] = [:]
    ) {
        let part = Part(
            name: name,
            fileName: fileName,
            mimeType: mimeType ?? "application/octet-stream",
            data: data,
            headers: headers
        )
        
        parts.append(part)
        logger.debug("Appended data part: \(name) (\(data.count) bytes)")
    }
    
    /// Append file URL
    public func append(
        _ fileURL: URL,
        withName name: String,
        fileName: String? = nil,
        mimeType: String? = nil,
        headers: [String: String] = [:]
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EncodingError.fileNotFound(fileURL.path)
        }
        
        let data = try Data(contentsOf: fileURL)
        let actualFileName = fileName ?? fileURL.lastPathComponent
        let actualMimeType = mimeType ?? Self.mimeType(for: fileURL)
        
        append(
            data,
            withName: name,
            fileName: actualFileName,
            mimeType: actualMimeType,
            headers: headers
        )
    }
    
    /// Append string
    public func append(
        _ string: String,
        withName name: String,
        encoding: String.Encoding = .utf8,
        headers: [String: String] = [:]
    ) throws {
        guard let data = string.data(using: encoding) else {
            throw EncodingError.dataConversionFailed
        }
        
        append(
            data,
            withName: name,
            mimeType: "text/plain; charset=\(encoding.description)",
            headers: headers
        )
    }
    
    /// Append JSON
    public func appendJSON<T: Encodable>(
        _ object: T,
        withName name: String,
        encoder: JSONEncoder = JSONEncoder(),
        headers: [String: String] = [:]
    ) throws {
        let data = try encoder.encode(object)
        
        append(
            data,
            withName: name,
            mimeType: "application/json",
            headers: headers
        )
    }
    
    /// Append form fields
    public func appendFormFields(_ fields: [String: String]) throws {
        for (name, value) in fields {
            try append(value, withName: name)
        }
    }
    
    /// Encode to data
    public func encode() throws -> Data {
        var body = Data()
        
        for part in parts {
            body.append(encodePart(part))
        }
        
        // Add final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        logger.debug("Encoded multipart data: \(body.count) bytes with \(parts.count) parts")
        return body
    }
    
    /// Create input stream
    public func inputStream() throws -> (stream: InputStream, length: Int) {
        let data = try encode()
        
        guard let stream = InputStream(data: data) else {
            throw EncodingError.streamCreationFailed
        }
        
        return (stream, data.count)
    }
    
    /// Write to file
    public func write(to url: URL) throws {
        let data = try encode()
        try data.write(to: url)
        logger.debug("Wrote multipart data to: \(url.path)")
    }
    
    /// Clear all parts
    public func removeAll() {
        parts.removeAll()
        logger.debug("Removed all parts")
    }
    
    // MARK: - Private Methods
    
    private func encodePart(_ part: Part) -> Data {
        var partData = Data()
        
        // Boundary
        partData.append("--\(boundary)\r\n".data(using: .utf8)!)
        
        // Content-Disposition header
        var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
        if let fileName = part.fileName {
            disposition += "; filename=\"\(fileName)\""
        }
        partData.append("\(disposition)\r\n".data(using: .utf8)!)
        
        // Content-Type header
        if let mimeType = part.mimeType {
            partData.append("Content-Type: \(mimeType)\r\n".data(using: .utf8)!)
        }
        
        // Additional headers
        for (key, value) in part.headers {
            partData.append("\(key): \(value)\r\n".data(using: .utf8)!)
        }
        
        // Empty line before content
        partData.append("\r\n".data(using: .utf8)!)
        
        // Content
        partData.append(part.data)
        
        // Line break after content
        partData.append("\r\n".data(using: .utf8)!)
        
        return partData
    }
    
    private static func generateBoundary() -> String {
        return "Boundary-\(UUID().uuidString)"
    }
    
    private static func mimeType(for url: URL) -> String {
        if #available(iOS 14.0, macOS 11.0, *) {
            if let type = UTType(filenameExtension: url.pathExtension) {
                return type.preferredMIMEType ?? "application/octet-stream"
            }
        }
        
        // Fallback for common types
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "txt": return "text/plain"
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Multipart Parser

/// Multipart form data parser
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
public class MultipartParser {
    
    // MARK: - Types
    
    /// Parsed part
    public struct ParsedPart {
        public let name: String
        public let fileName: String?
        public let contentType: String?
        public let headers: [String: String]
        public let data: Data
    }
    
    /// Parsing error
    public enum ParsingError: LocalizedError {
        case invalidData
        case boundaryNotFound
        case malformedPart
        case headerParsingFailed
        
        public var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Invalid multipart data"
            case .boundaryNotFound:
                return "Boundary not found in content type"
            case .malformedPart:
                return "Malformed multipart part"
            case .headerParsingFailed:
                return "Failed to parse headers"
            }
        }
    }
    
    // MARK: - Properties
    
    private let data: Data
    private let boundary: String
    private let logger = Logger(subsystem: "com.swiftnetworkpro", category: "MultipartParser")
    
    // MARK: - Initialization
    
    public init(data: Data, boundary: String) {
        self.data = data
        self.boundary = boundary
    }
    
    public convenience init(data: Data, contentType: String) throws {
        guard let boundary = Self.extractBoundary(from: contentType) else {
            throw ParsingError.boundaryNotFound
        }
        self.init(data: data, boundary: boundary)
    }
    
    // MARK: - Public Methods
    
    /// Parse multipart data
    public func parse() throws -> [ParsedPart] {
        var parts: [ParsedPart] = []
        
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let finalBoundaryData = "--\(boundary)--".data(using: .utf8)!
        let delimiter = "\r\n".data(using: .utf8)!
        let headerDelimiter = "\r\n\r\n".data(using: .utf8)!
        
        var currentIndex = 0
        
        while currentIndex < data.count {
            // Find boundary
            guard let boundaryRange = data.range(of: boundaryData, in: currentIndex..<data.count) else {
                break
            }
            
            // Check if it's the final boundary
            let finalRange = data.range(of: finalBoundaryData, in: currentIndex..<data.count)
            if let finalRange = finalRange, finalRange.lowerBound == boundaryRange.lowerBound {
                break
            }
            
            // Move past boundary and delimiter
            currentIndex = boundaryRange.upperBound
            if data[currentIndex..<min(currentIndex + delimiter.count, data.count)] == delimiter {
                currentIndex += delimiter.count
            }
            
            // Find header/body delimiter
            guard let headerEndRange = data.range(of: headerDelimiter, in: currentIndex..<data.count) else {
                throw ParsingError.malformedPart
            }
            
            // Parse headers
            let headerData = data[currentIndex..<headerEndRange.lowerBound]
            let headers = try parseHeaders(from: headerData)
            
            // Move to body
            currentIndex = headerEndRange.upperBound
            
            // Find next boundary
            let nextBoundaryRange = data.range(of: boundaryData, in: currentIndex..<data.count)
            let bodyEndIndex = nextBoundaryRange?.lowerBound ?? data.count
            
            // Extract body (remove trailing \r\n if present)
            var bodyData = data[currentIndex..<bodyEndIndex]
            if bodyData.hasSuffix(delimiter) {
                bodyData = bodyData[0..<(bodyData.count - delimiter.count)]
            }
            
            // Extract part info
            let name = extractName(from: headers)
            let fileName = extractFileName(from: headers)
            let contentType = headers["Content-Type"]
            
            if let name = name {
                let part = ParsedPart(
                    name: name,
                    fileName: fileName,
                    contentType: contentType,
                    headers: headers,
                    data: Data(bodyData)
                )
                parts.append(part)
            }
            
            currentIndex = bodyEndIndex
        }
        
        logger.debug("Parsed \(parts.count) multipart parts")
        return parts
    }
    
    // MARK: - Private Methods
    
    private func parseHeaders(from data: Data) throws -> [String: String] {
        guard let headerString = String(data: data, encoding: .utf8) else {
            throw ParsingError.headerParsingFailed
        }
        
        var headers: [String: String] = [:]
        let lines = headerString.components(separatedBy: "\r\n")
        
        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return headers
    }
    
    private func extractName(from headers: [String: String]) -> String? {
        guard let disposition = headers["Content-Disposition"] else { return nil }
        
        let pattern = #"name="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: disposition) else { return nil }
        
        return String(disposition[swiftRange])
    }
    
    private func extractFileName(from headers: [String: String]) -> String? {
        guard let disposition = headers["Content-Disposition"] else { return nil }
        
        let pattern = #"filename="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: disposition) else { return nil }
        
        return String(disposition[swiftRange])
    }
    
    private static func extractBoundary(from contentType: String) -> String? {
        let pattern = #"boundary=([^;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: contentType, range: NSRange(contentType.startIndex..., in: contentType)),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: contentType) else { return nil }
        
        var boundary = String(contentType[swiftRange])
        
        // Remove quotes if present
        if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
            boundary = String(boundary.dropFirst().dropLast())
        }
        
        return boundary
    }
}

// MARK: - String.Encoding Extension

private extension String.Encoding {
    var description: String {
        switch self {
        case .utf8: return "utf-8"
        case .utf16: return "utf-16"
        case .utf32: return "utf-32"
        case .ascii: return "us-ascii"
        case .isoLatin1: return "iso-8859-1"
        case .isoLatin2: return "iso-8859-2"
        default: return "utf-8"
        }
    }
}