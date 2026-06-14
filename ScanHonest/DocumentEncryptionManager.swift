import Foundation
import CryptoKit
import Security
import os.log

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case keyGenerationFailed
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:              return "Failed to generate encryption key."
        case .keychainReadFailed(let s):        return "Keychain read failed (OSStatus \(s))."
        case .keychainWriteFailed(let s):       return "Keychain write failed (OSStatus \(s))."
        case .encryptionFailed(let e):          return "Encryption failed: \(e.localizedDescription)"
        case .decryptionFailed(let e):          return "Decryption failed: \(e.localizedDescription)"
        case .invalidCiphertext:                return "Ciphertext is malformed or was tampered with."
        }
    }
}

// MARK: - DocumentEncryptionManager
//
// AES-256-GCM at-rest encryption for all document PDFs.
//
// Design decisions:
//   • The symmetric key lives ONLY in the iOS Keychain with
//     kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — it never appears in
//     UserDefaults, plists, iCloud backups, or log output.
//   • Encryption / decryption are synchronous pure-CPU operations so callers
//     don't need async overhead; StorageManager.savePDF can call encrypt()
//     inline before writing.
//   • Writes are always atomic: encrypt → write to .tmp → FileManager.replaceItem
//     so a crash mid-write never leaves a partial or plaintext file at the final URL.
//   • The .tmp file is written with .completeFileProtectionUntilFirstUserAuthentication
//     so the OS data-protection layer covers the window between tmpWrite and atomicMove.

final class DocumentEncryptionManager: @unchecked Sendable {

    static let shared = DocumentEncryptionManager()

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "Encryption")

    // Keychain identifiers
    private let keychainService = "com.afzal.ScanHonest.encryption"
    private let keychainAccount = "documentEncryptionKeyV1"

    // In-process key cache — avoids redundant Keychain lookups on every encrypt/decrypt.
    // Protected by a dedicated lock so concurrent callers on background queues are safe.
    private let cacheLock = NSLock()
    private var _cachedKey: SymmetricKey?

    private init() {}

    // MARK: - Encrypt / Decrypt

    /// Encrypts `plaintext` with AES-256-GCM.
    /// Returns the sealed box as Data (12-byte nonce ‖ ciphertext ‖ 16-byte tag).
    func encrypt(_ plaintext: Data) throws -> Data {
        let key = try resolvedKey()
        do {
            let box = try AES.GCM.seal(plaintext, using: key)
            guard let combined = box.combined else {
                throw EncryptionError.encryptionFailed(
                    NSError(domain: "ScanHonest.Encryption", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "AES.GCM.SealedBox.combined returned nil"])
                )
            }
            return combined
        } catch let e as EncryptionError { throw e }
          catch { throw EncryptionError.encryptionFailed(error) }
    }

    /// Decrypts data previously produced by `encrypt(_:)`.
    func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try resolvedKey()
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch let e as EncryptionError { throw e }
          catch { throw EncryptionError.decryptionFailed(error) }
    }

    // MARK: - Atomic Encrypted Write / Read

    /// Writes `data` to `url` atomically with full AES-256-GCM encryption:
    ///   1. Encrypt in memory.
    ///   2. Write ciphertext to a sibling `.enc.tmp` file with
    ///      `.completeFileProtectionUntilFirstUserAuthentication`.
    ///   3. Atomically replace the final URL (`FileManager.replaceItem`).
    ///
    /// A crash at any step leaves the original file untouched.
    func writeEncrypted(_ data: Data, to url: URL) throws {
        let encrypted = try encrypt(data)

        let dir    = url.deletingLastPathComponent()
        let tmpURL = dir.appendingPathComponent("\(url.lastPathComponent).enc.tmp")

        try encrypted.write(to: tmpURL,
                            options: [.atomic,
                                      .completeFileProtectionUntilFirstUserAuthentication])

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            // replaceItemAt is atomic on the same volume — no window of partial state
            _ = try fm.replaceItemAt(url, withItemAt: tmpURL, backupItemName: nil, options: [])
        } else {
            // New file: move tmp → final URL (also atomic on the same volume)
            try fm.moveItem(at: tmpURL, to: url)
        }
        logger.debug("Encrypted write → \(url.lastPathComponent)")
    }

    /// Reads and decrypts data from `url` that was written by `writeEncrypted(_:to:)`.
    func readEncrypted(from url: URL) throws -> Data {
        let ciphertext = try Data(contentsOf: url)
        return try decrypt(ciphertext)
    }

    // MARK: - Key Management

    /// Returns the cached key, or fetches from Keychain, or generates a new one.
    private func resolvedKey() throws -> SymmetricKey {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let k = _cachedKey { return k }

        let key: SymmetricKey
        if let existing = try? loadFromKeychain() {
            key = existing
        } else {
            key = SymmetricKey(size: .bits256)
            try saveToKeychain(key)
            logger.info("New AES-256 document encryption key generated and stored in Keychain.")
        }
        _cachedKey = key
        return key
    }

    private func loadFromKeychain() throws -> SymmetricKey {
        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    keychainService,
            kSecAttrAccount:    keychainAccount,
            kSecReturnData:     kCFBooleanTrue as Any,
            kSecMatchLimit:     kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw EncryptionError.keychainReadFailed(status)
        }
        return SymmetricKey(data: data)
    }

    private func saveToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        // Remove any stale entry first
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addAttrs: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    keychainService,
            kSecAttrAccount:    keychainAccount,
            kSecValueData:      keyData,
            // Accessible after first unlock (not open) — background tasks (OCR,
            // upload) can still decrypt while device is locked after first unlock.
            // ThisDeviceOnly prevents the key migrating via iCloud Keychain backup.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addAttrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainWriteFailed(status)
        }
        logger.debug("Encryption key persisted to Keychain.")
    }

    // MARK: - Key Rotation (future use)

    /// Re-encrypts all files under `directory` with a newly generated key.
    /// Old key remains in `_cachedKey` for decryption of existing files until
    /// rotation is complete, then swapped atomically.
    func rotateKey(reEncryptingFilesUnder directory: URL) async throws {
        // Enumerate encrypted files
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        let oldKey = try resolvedKey()
        let newKey = SymmetricKey(size: .bits256)

        for fileURL in files where fileURL.pathExtension.lowercased() == "pdf" {
            guard let ciphertext = try? Data(contentsOf: fileURL) else { continue }

            // Decrypt with old key
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(box, using: oldKey)

            // Re-encrypt with new key
            let newBox = try AES.GCM.seal(plaintext, using: newKey)
            guard let newCiphertext = newBox.combined else { continue }

            let tmpURL = fileURL.deletingLastPathComponent()
                                .appendingPathComponent("\(fileURL.lastPathComponent).rotate.tmp")
            try newCiphertext.write(to: tmpURL,
                                    options: [.atomic,
                                              .completeFileProtectionUntilFirstUserAuthentication])
            _ = try fm.replaceItemAt(fileURL, withItemAt: tmpURL, backupItemName: nil, options: [])
        }

        // Commit new key to Keychain and cache
        try saveToKeychain(newKey)
        updateCachedKey(newKey)
        logger.info("Key rotation complete — \(files.count) files re-encrypted.")
    }

    // nonisolated: only touches the lock-protected _cachedKey — no actor state.
    // Prevents Swift 6 warning about calling a sync NSLock inside async rotateKey.
    nonisolated private func updateCachedKey(_ key: SymmetricKey) {
        cacheLock.withLock {
            _cachedKey = key
        }
    }
}
