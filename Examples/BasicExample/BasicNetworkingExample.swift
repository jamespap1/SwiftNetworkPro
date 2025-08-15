//
//  BasicNetworkingExample.swift
//  SwiftNetworkPro Examples
//
//  Created by SwiftNetworkPro on 2024.
//  Copyright © 2024 SwiftNetworkPro. All rights reserved.
//

import SwiftUI
import SwiftNetworkPro

/// Basic networking example demonstrating common SwiftNetworkPro usage patterns
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct BasicNetworkingExample: View {
    @StateObject private var viewModel = NetworkingViewModel()
    
    var body: some View {
        NavigationView {
            List {
                Section("Basic Operations") {
                    Button("Fetch Users") {
                        Task {
                            await viewModel.fetchUsers()
                        }
                    }
                    
                    Button("Create User") {
                        Task {
                            await viewModel.createUser()
                        }
                    }
                    
                    Button("Upload File") {
                        Task {
                            await viewModel.uploadFile()
                        }
                    }
                }
                
                Section("Results") {
                    if viewModel.isLoading {
                        ProgressView("Loading...")
                    } else {
                        ForEach(viewModel.users, id: \.id) { user in
                            VStack(alignment: .leading) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("SwiftNetworkPro Demo")
        }
    }
}

// MARK: - ViewModel

@MainActor
final class NetworkingViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkClient: NetworkClient
    
    init() {
        // Initialize SwiftNetworkPro with enterprise configuration
        let config = NetworkConfiguration(
            baseURL: "https://jsonplaceholder.typicode.com",
            timeout: 30,
            retryPolicy: .exponentialBackoff(maxAttempts: 3),
            cachePolicy: .returnCacheDataElseLoad,
            security: .enterprise
        )
        
        self.networkClient = NetworkClient(configuration: config)
        
        // Configure authentication if needed
        Task {
            await networkClient.setAuthentication(.bearer("your-api-token"))
        }
    }
    
    /// Fetch users from API
    func fetchUsers() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Simple GET request with type-safe decoding
            let fetchedUsers = try await networkClient.get("/users", as: [User].self)
            users = fetchedUsers
        } catch {
            errorMessage = "Failed to fetch users: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Create a new user
    func createUser() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let newUserRequest = CreateUserRequest(
                name: "John Doe",
                email: "john.doe@example.com",
                phone: "+1-555-0123"
            )
            
            // POST request with body
            let createdUser = try await networkClient.post(
                "/users",
                body: newUserRequest,
                as: User.self
            )
            
            users.append(createdUser)
        } catch {
            errorMessage = "Failed to create user: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Upload a file
    func uploadFile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Create a temporary file for demonstration
            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("example.txt")
            
            let content = "Hello, SwiftNetworkPro!"
            try content.write(to: tempFileURL, atomically: true, encoding: .utf8)
            
            // Upload file
            let uploadResponse = try await networkClient.upload(
                tempFileURL,
                to: "/upload",
                as: UploadResponse.self
            )
            
            print("Upload successful: \(uploadResponse.message)")
            
            // Clean up
            try? FileManager.default.removeItem(at: tempFileURL)
            
        } catch {
            errorMessage = "Failed to upload file: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Data Models

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let phone: String?
    let website: String?
    
    // Nested types for complex JSON
    struct Address: Codable {
        let street: String
        let city: String
        let zipcode: String
    }
    
    let address: Address?
}

struct CreateUserRequest: Codable {
    let name: String
    let email: String
    let phone: String
}

struct UploadResponse: Codable {
    let success: Bool
    let message: String
    let fileId: String?
}

// MARK: - Advanced Examples

/// Advanced networking features demonstration
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
final class AdvancedNetworkingExample {
    private let client = NetworkClient.shared
    
    /// Demonstrate batch requests
    func performBatchRequests() async throws {
        // Execute multiple requests in parallel
        async let users = client.get("/users", as: [User].self)
        async let posts = client.get("/posts", as: [Post].self)
        async let comments = client.get("/comments", as: [Comment].self)
        
        let (userData, postsData, commentsData) = try await (users, posts, comments)
        
        print("Fetched \(userData.count) users, \(postsData.count) posts, \(commentsData.count) comments")
    }
    
    /// Demonstrate request interceptors
    func setupInterceptors() {
        // Add logging interceptor
        client.addInterceptor(LoggingInterceptor())
        
        // Add authentication interceptor
        client.addInterceptor(AuthenticationInterceptor())
        
        // Add retry interceptor
        client.addInterceptor(RetryInterceptor(maxAttempts: 3))
    }
    
    /// Demonstrate WebSocket usage
    func setupWebSocket() async throws {
        let wsClient = WebSocketClient(url: URL(string: "wss://echo.websocket.org")!)
        
        // Connect to WebSocket
        try await wsClient.connect()
        
        // Listen for messages
        wsClient.onMessage { message in
            print("Received: \(message.text ?? "")")
        }
        
        // Send message
        try await wsClient.send(text: "Hello, WebSocket!")
    }
    
    /// Demonstrate GraphQL usage
    func performGraphQLQuery() async throws {
        let query = """
            query GetUser($id: ID!) {
                user(id: $id) {
                    id
                    name
                    email
                    posts {
                        title
                        content
                    }
                }
            }
        """
        
        let variables = ["id": "123"]
        let result = try await GraphQL.query(
            query,
            variables: variables,
            as: UserResponse.self
        )
        
        print("User: \(result.user.name)")
    }
}

// MARK: - Custom Interceptors

struct LoggingInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async -> URLRequest {
        print("🚀 Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        return request
    }
}

struct AuthenticationInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async -> URLRequest {
        var modifiedRequest = request
        
        // Add authentication header
        if let token = await getAuthToken() {
            modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return modifiedRequest
    }
    
    private func getAuthToken() async -> String? {
        // Implement token retrieval logic
        return "your-auth-token"
    }
}

struct RetryInterceptor: RequestInterceptor {
    let maxAttempts: Int
    
    func intercept(_ request: URLRequest) async -> URLRequest {
        // Add retry metadata
        var modifiedRequest = request
        modifiedRequest.setValue("\(maxAttempts)", forHTTPHeaderField: "X-Max-Retries")
        return modifiedRequest
    }
}

// MARK: - Additional Models

struct Post: Codable, Identifiable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

struct Comment: Codable, Identifiable {
    let id: Int
    let postId: Int
    let name: String
    let email: String
    let body: String
}

struct UserResponse: Codable {
    let user: GraphQLUser
}

struct GraphQLUser: Codable {
    let id: String
    let name: String
    let email: String
    let posts: [GraphQLPost]
}

struct GraphQLPost: Codable {
    let title: String
    let content: String
}

// MARK: - Preview

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct BasicNetworkingExample_Previews: PreviewProvider {
    static var previews: some View {
        BasicNetworkingExample()
    }
}