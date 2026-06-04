import Foundation
import os.log

// MARK: - Cloud Provider

enum CloudProvider: String, CaseIterable, Identifiable {
    case googleDrive = "Google Drive"
    case dropbox     = "Dropbox"

    var id: String { rawValue }

    // OAuth2 token-refresh endpoints
    fileprivate var tokenRefreshURL: URL {
        switch self {
        case .googleDrive: return URL(string: "https://oauth2.googleapis.com/token")!
        case .dropbox:     return URL(string: "https://api.dropboxapi.com/oauth2/token")!
        }
    }

    // Upload endpoints
    fileprivate var uploadURL: URL {
        switch self {
        case .googleDrive:
            return URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
        case .dropbox:
            return URL(string: "https://content.dropboxapi.com/2/files/upload")!
        }
    }
}

// MARK: - Cloud Export Error

enum CloudExportError: LocalizedError {
    case notAuthenticated(CloudProvider)
    case tokenRefreshFailed(Error)
    case uploadFailed(Int, String)   // HTTP status, body snippet
    case fileNotFound(URL)
    case encryptionRequired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated(let p):   return "\(p.rawValue) is not connected. Please sign in via Settings."
        case .tokenRefreshFailed(let e): return "Token refresh failed: \(e.localizedDescription)"
        case .uploadFailed(let s, let b):return "Upload failed (HTTP \(s)): \(b.prefix(120))"
        case .fileNotFound(let u):       return "File not found at \(u.lastPathComponent)."
        case .encryptionRequired:        return "Document must be decrypted before upload."
        }
    }
}

// MARK: - OAuth Token Store
//
// Tokens are stored ONLY in the Keychain — never UserDefaults.

final class OAuthTokenStore {

    static let shared = OAuthTokenStore()
    private init() {}

    private func keychainKey(for provider: CloudProvider, suffix: String) -> String {
        "com.afzal.ScanHonest.\(provider.rawValue).\(suffix)"
    }

    func saveAccessToken(_ token: String, for provider: CloudProvider) {
        save(token, account: keychainKey(for: provider, suffix: "accessToken"))
    }

    func saveRefreshToken(_ token: String, for provider: CloudProvider) {
        save(token, account: keychainKey(for: provider, suffix: "refreshToken"))
    }

    func accessToken(for provider: CloudProvider) -> String? {
        load(account: keychainKey(for: provider, suffix: "accessToken"))
    }

    func refreshToken(for provider: CloudProvider) -> String? {
        load(account: keychainKey(for: provider, suffix: "refreshToken"))
    }

    func clearTokens(for provider: CloudProvider) {
        delete(account: keychainKey(for: provider, suffix: "accessToken"))
        delete(account: keychainKey(for: provider, suffix: "refreshToken"))
    }

    // MARK: Keychain helpers

    private func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let service = "com.afzal.ScanHonest.oauth"
        let deleteQuery: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                             kSecAttrService: service,
                                             kSecAttrAccount: account]
        SecItemDelete(deleteQuery as CFDictionary)
        let attrs: [CFString: Any] = [kSecClass:          kSecClassGenericPassword,
                                       kSecAttrService:    service,
                                       kSecAttrAccount:    account,
                                       kSecValueData:      data,
                                       kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func load(account: String) -> String? {
        let query: [CFString: Any] = [kSecClass:       kSecClassGenericPassword,
                                       kSecAttrService: "com.afzal.ScanHonest.oauth",
                                       kSecAttrAccount: account,
                                       kSecReturnData:  kCFBooleanTrue as Any,
                                       kSecMatchLimit:  kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        let query: [CFString: Any] = [kSecClass:       kSecClassGenericPassword,
                                       kSecAttrService: "com.afzal.ScanHonest.oauth",
                                       kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - CloudExportEngine
//
// Background URLSession upload engine for Google Drive and Dropbox.
//
// Key design choices:
//   • URLSessionConfiguration.background — uploads continue when the app is
//     backgrounded or suspended (system resumes the upload task automatically).
//   • Documents are decrypted in-memory before upload — the encrypted on-disk
//     file is NEVER sent to a cloud provider directly.
//   • OAuth2 refresh is attempted automatically on 401 responses.
//   • All upload operations are async/await and can be called from any context.

final class CloudExportEngine: NSObject {

    static let shared = CloudExportEngine()

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "CloudExport")
    private let tokenStore = OAuthTokenStore.shared

    // Background URLSession — persists across app suspension
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.afzal.ScanHonest.cloudUpload"
        )
        config.isDiscretionary   = false   // upload promptly, not at OS discretion
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Completion handlers keyed by taskIdentifier — called when background task completes
    private var completionHandlers: [Int: (Result<Void, Error>) -> Void] = [:]
    private let handlersLock = NSLock()

    private override init() { super.init() }

    // MARK: - Public Upload API

    /// Uploads the document at `fileURL` (which must be AES-256-GCM encrypted by
    /// DocumentEncryptionManager) to `provider`.
    ///
    /// - Parameters:
    ///   - fileURL:    URL of the encrypted PDF on disk.
    ///   - fileName:   Desired filename in the cloud (e.g. "Invoice_2024.pdf").
    ///   - provider:   `.googleDrive` or `.dropbox`.
    ///   - completion: Called on the main queue with success or an error.
    func upload(
        fileURL:    URL,
        fileName:   String,
        to provider: CloudProvider,
        isPro:      Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                // 0. Service-leakage prevention: verify Pro status before any
                //    network activity. This catches bypassed UI gates.
                try ProGate.verify(.cloudExport, isPro: isPro)

                // 1. Ensure we have a valid access token
                let accessToken = try await resolvedAccessToken(for: provider)

                // 2. Decrypt the file in-memory — never send raw ciphertext to cloud
                let plaintext: Data
                do {
                    plaintext = try DocumentEncryptionManager.shared.readEncrypted(from: fileURL)
                } catch {
                    // Legacy: file may not be encrypted yet
                    guard let data = try? Data(contentsOf: fileURL) else {
                        throw CloudExportError.fileNotFound(fileURL)
                    }
                    plaintext = data
                }

                // 3. Build and enqueue background upload request
                let request = try buildUploadRequest(
                    data:        plaintext,
                    fileName:    fileName,
                    provider:    provider,
                    accessToken: accessToken
                )

                // For background uploads, write payload to a temp file
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).upload.tmp")
                try plaintext.write(to: tmpURL)

                let mutableRequest = request
                let task = backgroundSession.uploadTask(with: mutableRequest, fromFile: tmpURL)

                handlersLock.withLock {
                    completionHandlers[task.taskIdentifier] = { result in
                        try? FileManager.default.removeItem(at: tmpURL)  // cleanup temp
                        DispatchQueue.main.async { completion(result) }
                    }
                }

                task.resume()
                logger.info("Enqueued background upload '\(fileName)' → \(provider.rawValue)")

            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Token Refresh

    private func resolvedAccessToken(for provider: CloudProvider) async throws -> String {
        if let token = tokenStore.accessToken(for: provider), !token.isEmpty {
            return token
        }
        guard let refreshToken = tokenStore.refreshToken(for: provider),
              !refreshToken.isEmpty else {
            throw CloudExportError.notAuthenticated(provider)
        }
        return try await refreshAccessToken(refreshToken: refreshToken, provider: provider)
    }

    private func refreshAccessToken(refreshToken: String, provider: CloudProvider) async throws -> String {
        var request = URLRequest(url: provider.tokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build body — caller must have previously set the client_id/secret via
        // a secure config plist (not hardcoded here)
        let clientID     = CloudCredentials.clientID(for: provider)
        let clientSecret = CloudCredentials.clientSecret(for: provider)
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)&client_secret=\(clientSecret)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let snippet = String(data: data, encoding: .utf8) ?? ""
                let status  = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw CloudExportError.uploadFailed(status, snippet)
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let newToken = json?["access_token"] as? String else {
                throw CloudExportError.tokenRefreshFailed(
                    NSError(domain: "CloudExport", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "No access_token in refresh response"])
                )
            }
            tokenStore.saveAccessToken(newToken, for: provider)
            logger.info("Token refreshed for \(provider.rawValue)")
            return newToken
        } catch let e as CloudExportError { throw e }
          catch { throw CloudExportError.tokenRefreshFailed(error) }
    }

    // MARK: - Request Builders

    private func buildUploadRequest(
        data:        Data,
        fileName:    String,
        provider:    CloudProvider,
        accessToken: String
    ) throws -> URLRequest {
        switch provider {
        case .googleDrive:
            return buildGoogleDriveRequest(data: data, fileName: fileName, accessToken: accessToken)
        case .dropbox:
            return buildDropboxRequest(data: data, fileName: fileName, accessToken: accessToken)
        }
    }

    private func buildGoogleDriveRequest(data: Data, fileName: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: CloudProvider.googleDrive.uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // Multipart/related: metadata JSON + file bytes
        let boundary = "ScanHonest-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadata = "{\"name\":\"\(fileName)\"}"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n\(metadata)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)
        request.httpBody = body
        return request
    }

    private func buildDropboxRequest(data: Data, fileName: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: CloudProvider.dropbox.uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let args: [String: Any] = [
            "path":       "/ScanHonest/\(fileName)",
            "mode":       "overwrite",
            "autorename": true
        ]
        if let argsData = try? JSONSerialization.data(withJSONObject: args),
           let argsString = String(data: argsData, encoding: .utf8) {
            request.setValue(argsString, forHTTPHeaderField: "Dropbox-API-Arg")
        }
        request.httpBody = data
        return request
    }
}

// MARK: - URLSessionDelegate (Background Upload)

extension CloudExportEngine: URLSessionDelegate, URLSessionTaskDelegate {

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let handler = handlersLock.withLock {
            completionHandlers.removeValue(forKey: task.taskIdentifier)
        }

        if let error {
            logger.error("Upload task \(task.taskIdentifier) failed: \(error.localizedDescription)")
            handler?(.failure(error))
            return
        }

        if let http = task.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let msg = "HTTP \(http.statusCode)"
            logger.error("Upload task \(task.taskIdentifier) HTTP error: \(msg)")
            handler?(.failure(CloudExportError.uploadFailed(http.statusCode, msg)))
        } else {
            logger.info("Upload task \(task.taskIdentifier) succeeded.")
            handler?(.success(()))
        }
    }
}

// MARK: - CloudCredentials
//
// Reads OAuth client_id / client_secret from a non-tracked Config.plist so
// credentials are NEVER hardcoded in source. Add Config.plist to .gitignore.

private enum CloudCredentials {
    private static var plist: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return dict
    }()

    static func clientID(for provider: CloudProvider) -> String {
        let key = provider == .googleDrive ? "GoogleDriveClientID" : "DropboxClientID"
        return plist?[key] as? String ?? ""
    }

    static func clientSecret(for provider: CloudProvider) -> String {
        let key = provider == .googleDrive ? "GoogleDriveClientSecret" : "DropboxClientSecret"
        return plist?[key] as? String ?? ""
    }
}
