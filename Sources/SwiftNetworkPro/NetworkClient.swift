import Foundation

/// Basic networking client for HTTP requests
public class NetworkClient {
    
    private let session: URLSession
    
    public init() {
        self.session = URLSession.shared
    }
    
    /// Perform a GET request
    public func get(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        let request = URLRequest(url: url)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.noData))
                return
            }
            
            completion(.success(data))
        }.resume()
    }
}

public enum NetworkError: Error {
    case noData
    case invalidURL
}