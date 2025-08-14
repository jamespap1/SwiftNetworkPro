import SwiftUI
import SwiftNetworkPro

/// Basic example demonstrating SwiftNetworkPro usage in a SwiftUI app
@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
@main
struct BasicExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct ContentView: View {
    @StateObject private var viewModel = NetworkExampleViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack {
                    Text("SwiftNetworkPro")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Basic Example")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Status
                StatusView(status: viewModel.status)
                
                // Action Buttons
                VStack(spacing: 16) {
                    ActionButton(
                        title: "GET Users",
                        systemImage: "person.2.fill",
                        action: { await viewModel.fetchUsers() }
                    )
                    
                    ActionButton(
                        title: "POST New User",
                        systemImage: "person.badge.plus",
                        action: { await viewModel.createUser() }
                    )
                    
                    ActionButton(
                        title: "WebSocket Chat",
                        systemImage: "message.fill",
                        action: { await viewModel.connectWebSocket() }
                    )
                    
                    ActionButton(
                        title: "GraphQL Query",
                        systemImage: "doc.text.magnifyingglass",
                        action: { await viewModel.performGraphQLQuery() }
                    )
                }
                
                // Results
                if !viewModel.results.isEmpty {
                    ResultsView(results: viewModel.results)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct StatusView: View {
    let status: NetworkStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
            
            Text(status.title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(Capsule())
    }
}

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () async -> Void
    
    @State private var isLoading = false
    
    var body: some View {
        Button {
            Task {
                isLoading = true
                await action()
                isLoading = false
            }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: systemImage)
                }
                
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(isLoading)
    }
}

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
struct ResultsView: View {
    let results: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results:")
                .font(.headline)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(results, id: \.self) { result in
                        Text(result)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - View Model

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
@MainActor
class NetworkExampleViewModel: ObservableObject {
    @Published var status: NetworkStatus = .idle
    @Published var results: [String] = []
    
    private let networkClient: NetworkClient
    private var webSocketClient: WebSocketClient?
    private var graphQLClient: GraphQLClient?
    
    init() {
        // Configure network client
        let configuration = NetworkConfiguration(
            baseURL: "https://jsonplaceholder.typicode.com",
            timeout: 30,
            retryPolicy: .exponentialBackoff(maxAttempts: 3),
            enableLogging: true
        )
        
        self.networkClient = NetworkClient(configuration: configuration)
        
        // Add logging interceptor
        networkClient.addInterceptor(LoggingInterceptor())
    }
    
    func fetchUsers() async {
        status = .loading
        results.removeAll()
        
        do {
            let users: [User] = try await networkClient.get("/users", as: [User].self)
            status = .success
            results = users.prefix(5).map { "User: \($0.name) (\($0.email))" }
        } catch {
            status = .error(error.localizedDescription)
            results = ["Error: \(error.localizedDescription)"]
        }
    }
    
    func createUser() async {
        status = .loading
        results.removeAll()
        
        let newUser = CreateUserRequest(
            name: "John Doe",
            username: "johndoe",
            email: "john@example.com"
        )
        
        do {
            let createdUser: User = try await networkClient.post(
                "/users",
                body: newUser,
                as: User.self
            )
            status = .success
            results = ["Created user: \(createdUser.name) (ID: \(createdUser.id))"]
        } catch {
            status = .error(error.localizedDescription)
            results = ["Error: \(error.localizedDescription)"]
        }
    }
    
    func connectWebSocket() async {
        status = .loading
        results.removeAll()
        
        guard let url = URL(string: "wss://echo.websocket.org") else {
            status = .error("Invalid WebSocket URL")
            return
        }
        
        do {
            webSocketClient = WebSocketClient(url: url)
            
            // Set up message handler
            webSocketClient?.onMessage { [weak self] message in
                DispatchQueue.main.async {
                    self?.results.append("Received: \(message.text ?? "Binary data")")
                }
            }
            
            // Connect
            try await webSocketClient?.connect()
            status = .success
            
            // Send test message
            try await webSocketClient?.send(text: "Hello from SwiftNetworkPro!")
            results.append("Sent: Hello from SwiftNetworkPro!")
            
        } catch {
            status = .error(error.localizedDescription)
            results = ["WebSocket Error: \(error.localizedDescription)"]
        }
    }
    
    func performGraphQLQuery() async {
        status = .loading
        results.removeAll()
        
        // Initialize GraphQL client (example endpoint)
        let graphQLConfig = GraphQLConfiguration(
            endpoint: "https://api.github.com/graphql",
            headers: ["Authorization": "Bearer YOUR_TOKEN_HERE"]
        )
        
        graphQLClient = GraphQLClient(configuration: graphQLConfig)
        
        let query = """
        query {
            viewer {
                login
                name
                email
            }
        }
        """
        
        do {
            let response: GraphQLResponse<ViewerData> = try await graphQLClient!.query(
                query,
                as: GraphQLResponse<ViewerData>.self
            )
            
            if let viewer = response.data.viewer {
                status = .success
                results = [
                    "GitHub User: \(viewer.name ?? "Unknown")",
                    "Login: \(viewer.login)",
                    "Email: \(viewer.email ?? "Not provided")"
                ]
            }
            
        } catch {
            status = .error(error.localizedDescription)
            results = ["GraphQL Error: This example requires a valid GitHub token"]
        }
    }
}

// MARK: - Models

struct User: Codable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let phone: String?
    let website: String?
    
    struct Address: Codable {
        let street: String
        let suite: String
        let city: String
        let zipcode: String
    }
    
    struct Company: Codable {
        let name: String
        let catchPhrase: String
        let bs: String
    }
    
    let address: Address?
    let company: Company?
}

struct CreateUserRequest: Codable {
    let name: String
    let username: String
    let email: String
}

struct ViewerData: Codable {
    let viewer: GitHubUser?
    
    struct GitHubUser: Codable {
        let login: String
        let name: String?
        let email: String?
    }
}

struct GraphQLResponse<T: Codable>: Codable {
    let data: T
    let errors: [GraphQLError]?
    
    struct GraphQLError: Codable {
        let message: String
        let locations: [Location]?
        
        struct Location: Codable {
            let line: Int
            let column: Int
        }
    }
}

// MARK: - Supporting Types

enum NetworkStatus {
    case idle
    case loading
    case success
    case error(String)
    
    var title: String {
        switch self {
        case .idle: return "Ready"
        case .loading: return "Loading..."
        case .success: return "Success"
        case .error: return "Error"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .gray
        case .loading: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}

@available(iOS 15.0, macOS 13.0, watchOS 9.0, tvOS 15.0, visionOS 1.0, *)
class LoggingInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        print("🚀 Request: \(request.httpMethod ?? "Unknown") \(request.url?.absoluteString ?? "Unknown URL")")
        return request
    }
}