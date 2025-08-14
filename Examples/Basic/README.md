# 🟢 Basic Examples

Welcome to SwiftNetworkPro Basic Examples! This level covers fundamental networking concepts and basic usage patterns.

## 📋 What You'll Learn

- ✅ Setting up SwiftNetworkPro in your project
- ✅ Making simple HTTP requests (GET, POST, PUT, DELETE)
- ✅ Basic error handling and response processing
- ✅ Working with Codable models
- ✅ Essential configuration options

## 📁 Example Projects

### 1. QuickStart App
**File**: `QuickStart/`
**Platform**: iOS (SwiftUI)
**Description**: Your first SwiftNetworkPro app with minimal setup

```swift
// Just 3 lines to make your first request!
let client = NetworkClient.shared
let users = try await client.get("/users", as: [User].self)
print("Fetched \(users.count) users")
```

### 2. CRUD Operations
**File**: `CRUDExample/`
**Platform**: iOS (UIKit)
**Description**: Complete Create, Read, Update, Delete operations

**Features**:
- User management interface
- Form validation
- Loading states
- Success/error feedback

### 3. Response Handling
**File**: `ResponseHandling/`
**Platform**: iOS (SwiftUI)
**Description**: Different ways to handle API responses

**Covers**:
- Success responses
- Error handling patterns
- Status code interpretation
- Response validation

### 4. Model Mapping
**File**: `ModelMapping/`
**Platform**: macOS
**Description**: Working with complex JSON structures

**Topics**:
- Codable best practices
- Custom date formatting
- Nested model structures
- Optional field handling

### 5. Basic Configuration
**File**: `Configuration/`
**Platform**: iOS (SwiftUI)
**Description**: Essential NetworkClient configuration

**Settings**:
- Base URL configuration
- Timeout values
- Default headers
- Basic security settings

## 🏃‍♂️ Quick Start Guide

### Step 1: Choose an Example
Browse the directories above and pick an example that matches your learning goal.

### Step 2: Open in Xcode
```bash
cd Examples/Basic/QuickStart
open QuickStart.xcodeproj
```

### Step 3: Run the Example
1. Select your target device/simulator
2. Press `Cmd+R` to build and run
3. Explore the code and modify it!

## 📝 Code Walkthrough

### Simple GET Request
```swift
import SwiftNetworkPro

struct ContentView: View {
    @State private var users: [User] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            List(users) { user in
                VStack(alignment: .leading) {
                    Text(user.name).font(.headline)
                    Text(user.email).font(.subheadline)
                }
            }
            .navigationTitle("Users")
            .task {
                await loadUsers()
            }
        }
    }
    
    private func loadUsers() async {
        isLoading = true
        
        do {
            // SwiftNetworkPro magic - one line for complete request!
            users = try await NetworkClient.shared.get("/users", as: [User].self)
        } catch {
            print("Error loading users: \(error)")
        }
        
        isLoading = false
    }
}

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
}
```

### POST Request with Body
```swift
struct CreateUserView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var isLoading = false
    
    private func createUser() async {
        isLoading = true
        
        let newUser = CreateUserRequest(name: name, email: email)
        
        do {
            let createdUser = try await NetworkClient.shared.post(
                "/users", 
                body: newUser, 
                as: User.self
            )
            print("Created user: \(createdUser.name)")
        } catch {
            print("Error creating user: \(error)")
        }
        
        isLoading = false
    }
}

struct CreateUserRequest: Codable {
    let name: String
    let email: String
}
```

## 🛠️ Common Patterns

### Error Handling Best Practices
```swift
enum UserError: Error {
    case networkUnavailable
    case invalidData
    case serverError(Int)
}

func loadUsersWithErrorHandling() async -> Result<[User], UserError> {
    do {
        let users = try await NetworkClient.shared.get("/users", as: [User].self)
        return .success(users)
    } catch let networkError as NetworkError {
        switch networkError {
        case .noConnection:
            return .failure(.networkUnavailable)
        case .invalidResponse:
            return .failure(.invalidData)
        case .httpError(let statusCode):
            return .failure(.serverError(statusCode))
        default:
            return .failure(.invalidData)
        }
    } catch {
        return .failure(.invalidData)
    }
}
```

### Loading States in SwiftUI
```swift
struct UserListView: View {
    @State private var users: [User] = []
    @State private var loadingState: LoadingState = .idle
    
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(String)
    }
    
    var body: some View {
        switch loadingState {
        case .idle:
            Text("Tap to load users")
                .onTapGesture { Task { await loadUsers() } }
        case .loading:
            ProgressView("Loading users...")
        case .loaded:
            List(users) { user in
                UserRowView(user: user)
            }
        case .error(let message):
            VStack {
                Image(systemName: "exclamationmark.triangle")
                Text("Error: \(message)")
                Button("Retry") { Task { await loadUsers() } }
            }
        }
    }
}
```

## 🎯 Practice Exercises

Try these exercises to reinforce your learning:

### Exercise 1: User Profile App
Create an app that:
- Fetches user profiles from an API
- Displays user information in a list
- Shows loading and error states
- Implements pull-to-refresh

### Exercise 2: Todo List Manager
Build a todo app that:
- Loads todos from an API
- Creates new todos
- Updates todo completion status
- Deletes todos

### Exercise 3: Weather App
Develop a weather app that:
- Fetches weather data for a city
- Displays current weather conditions
- Shows a 5-day forecast
- Handles location-based requests

## 🔗 Useful Resources

- **SwiftNetworkPro Documentation**: [Advanced Usage](../../README.md#advanced-usage)
- **Apple Async/Await Guide**: [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- **HTTP Status Codes**: [MDN Reference](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status)
- **JSON and Codable**: [Swift Guide](https://developer.apple.com/documentation/foundation/archives_and_serialization/encoding_and_decoding_custom_types)

## ➡️ Next Steps

Once you're comfortable with basic concepts, progress to:
- **[Intermediate Examples](../Intermediate/)** - Real-world app patterns
- **[Advanced Examples](../Advanced/)** - Enterprise architectures

---

**🚀 Ready to build amazing networked apps? Start with QuickStart and work your way up!**