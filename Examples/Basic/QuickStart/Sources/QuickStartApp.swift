import SwiftUI
import SwiftNetworkPro

@main
struct QuickStartApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading posts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    ErrorView(message: errorMessage) {
                        Task { await loadPosts() }
                    }
                } else {
                    PostListView(posts: posts)
                }
            }
            .navigationTitle("SwiftNetworkPro")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadPosts()
            }
            .refreshable {
                await loadPosts()
            }
        }
    }
    
    private func loadPosts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // ✨ SwiftNetworkPro Magic - Just one line!
            posts = try await NetworkClient.shared.get(
                "https://jsonplaceholder.typicode.com/posts",
                as: [Post].self
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

struct PostListView: View {
    let posts: [Post]
    
    var body: some View {
        List(posts) { post in
            VStack(alignment: .leading, spacing: 8) {
                Text(post.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(post.body)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                HStack {
                    Image(systemName: "person.circle")
                    Text("User \(post.userId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Post #\(post.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Oops! Something went wrong")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Models

struct Post: Codable, Identifiable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

#Preview {
    ContentView()
}