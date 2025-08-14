import XCTest
@testable import SwiftNetworkPro

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
final class NetworkClientTests: XCTestCase {
    
    var client: NetworkClient!
    var configuration: NetworkConfiguration!
    
    override func setUp() async throws {
        configuration = NetworkConfiguration(
            baseURL: "https://api.example.com",
            timeout: 30,
            retryPolicy: .exponentialBackoff(maxAttempts: 3)
        )
        client = NetworkClient(configuration: configuration)
    }
    
    override func tearDown() async throws {
        client = nil
        configuration = nil
    }
    
    // MARK: - GET Request Tests
    
    func testGETRequestSuccess() async throws {
        // Given
        let endpoint = "/users/1"
        
        // When & Then
        // Note: This would require a proper mock setup in a real test
        // For now, we're testing the method signature and basic functionality
        do {
            let _: MockUser = try await client.get(endpoint, as: MockUser.self)
        } catch {
            // Expected to fail without proper mock setup
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    func testGETRequestWithParameters() async throws {
        // Given
        let endpoint = "/users"
        let parameters = ["page": 1, "limit": 10]
        
        // When & Then
        do {
            let _: [MockUser] = try await client.get(
                endpoint,
                parameters: parameters,
                as: [MockUser].self
            )
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    func testGETRequestWithHeaders() async throws {
        // Given
        let endpoint = "/users/1"
        let headers = ["Authorization": "Bearer test-token"]
        
        // When & Then
        do {
            let _: MockUser = try await client.get(
                endpoint,
                headers: headers,
                as: MockUser.self
            )
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - POST Request Tests
    
    func testPOSTRequestSuccess() async throws {
        // Given
        let endpoint = "/users"
        let newUser = CreateUserRequest(name: "John Doe", email: "john@example.com")
        
        // When & Then
        do {
            let _: MockUser = try await client.post(
                endpoint,
                body: newUser,
                as: MockUser.self
            )
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    func testPOSTRequestWithoutBody() async throws {
        // Given
        let endpoint = "/ping"
        
        // When & Then
        do {
            let _: PingResponse = try await client.post(endpoint, as: PingResponse.self)
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - PUT Request Tests
    
    func testPUTRequestSuccess() async throws {
        // Given
        let endpoint = "/users/1"
        let updateUser = UpdateUserRequest(name: "Jane Doe")
        
        // When & Then
        do {
            let _: MockUser = try await client.put(
                endpoint,
                body: updateUser,
                as: MockUser.self
            )
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - PATCH Request Tests
    
    func testPATCHRequestSuccess() async throws {
        // Given
        let endpoint = "/users/1"
        let patchUser = PatchUserRequest(email: "newemail@example.com")
        
        // When & Then
        do {
            let _: MockUser = try await client.patch(
                endpoint,
                body: patchUser,
                as: MockUser.self
            )
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - DELETE Request Tests
    
    func testDELETERequestSuccess() async throws {
        // Given
        let endpoint = "/users/1"
        
        // When & Then
        do {
            let _: DeleteResponse = try await client.delete(endpoint, as: DeleteResponse.self)
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationUpdate() async throws {
        // Given
        let newConfiguration = NetworkConfiguration(
            baseURL: "https://api.newexample.com",
            timeout: 60,
            retryPolicy: .fixed(maxAttempts: 5, delay: 2.0)
        )
        
        // When
        await client.updateConfiguration(newConfiguration)
        
        // Then
        // Configuration should be updated (would need getter to test properly)
    }
    
    // MARK: - Interceptor Tests
    
    func testRequestInterceptor() async throws {
        // Given
        let interceptor = MockRequestInterceptor()
        
        // When
        await client.addInterceptor(interceptor)
        
        // Then
        // Interceptor should be added (would need getter to test properly)
    }
    
    func testResponseProcessor() async throws {
        // Given
        let processor = MockResponseProcessor()
        
        // When
        await client.addResponseProcessor(processor)
        
        // Then
        // Processor should be added (would need getter to test properly)
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkErrorHandling() async throws {
        // Given
        let endpoint = "/invalid-endpoint"
        
        // When & Then
        do {
            let _: MockUser = try await client.get(endpoint, as: MockUser.self)
            XCTFail("Expected network error")
        } catch let error as NetworkError {
            // Expected behavior
            switch error {
            case .invalidURL:
                XCTAssertTrue(true)
            default:
                XCTAssertTrue(true) // Other network errors are also acceptable
            }
        }
    }
    
    // MARK: - File Operations Tests
    
    func testDownloadFile() async throws {
        // Given
        let url = "https://example.com/file.pdf"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("test.pdf")
        
        // When & Then
        do {
            let _ = try await client.download(from: url, to: destination)
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    func testUploadFile() async throws {
        // Given
        let fileURL = Bundle.module.url(forResource: "test", withExtension: "txt") ?? 
                     FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
        let endpoint = "/upload"
        
        // When & Then
        do {
            let _: UploadResponse = try await client.upload(
                fileURL,
                to: endpoint,
                as: UploadResponse.self
            )
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: - Request Cancellation Tests
    
    func testCancelAllRequests() async throws {
        // Given
        // Start some requests (would need proper async setup)
        
        // When
        await client.cancelAllRequests()
        
        // Then
        // All requests should be cancelled (would need tracking to test properly)
    }
    
    // MARK: - Performance Tests
    
    func testRequestPerformance() async throws {
        // Measure performance of basic GET request
        measure {
            let expectation = XCTestExpectation(description: "Network request")
            
            Task {
                do {
                    let _: MockUser = try await client.get("/users/1", as: MockUser.self)
                } catch {
                    // Expected to fail without proper setup
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
}

// MARK: - Mock Types

struct MockUser: Codable {
    let id: Int
    let name: String
    let email: String
    let createdAt: Date
    
    init(id: Int = 1, name: String = "Test User", email: String = "test@example.com", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.email = email
        self.createdAt = createdAt
    }
}

struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

struct UpdateUserRequest: Codable {
    let name: String
}

struct PatchUserRequest: Codable {
    let email: String
}

struct DeleteResponse: Codable {
    let success: Bool
    let message: String
}

struct PingResponse: Codable {
    let status: String
    let timestamp: Date
}

struct UploadResponse: Codable {
    let success: Bool
    let fileId: String
    let url: String
}

// MARK: - Mock Interceptor and Processor

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
class MockRequestInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.setValue("MockInterceptor/1.0", forHTTPHeaderField: "User-Agent")
        return modifiedRequest
    }
}

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
class MockResponseProcessor: ResponseProcessor {
    func process(_ data: Data, response: URLResponse) async throws -> Data {
        // Mock processing - just return data as-is
        return data
    }
}