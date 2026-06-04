# ScanHonest — Security Audit: Password Protection Module
**Version:** 1.0 | **Date:** 2026-05-20 | **Auditor:** Engineering / Security Review  
**Scope:** `isPasswordProtected` flag, lock/unlock flow, App Switcher privacy, biometric fallback

---

## Executive Summary

The current implementation stores a **Boolean flag** (`isPasswordProtected`) in the SwiftData model. This flag gates the *UI presentation* of the password prompt but does **not** encrypt the underlying PDF file at rest. This is the primary finding of this audit.

**Risk Level:** 🔴 High — a user with filesystem access (jailbroken device, iTunes backup without encryption, or direct file browsing via Finder) can read locked documents without ever entering a password.

---

## 1. Current Architecture

```
ScannedDocument.isPasswordProtected: Bool   ← only a UI gate
ScannedDocument.fileURL: URL?               ← plain .pdf on disk, no encryption
StorageManager.savePDF(_:name:thumbnail:)   ← writes plaintext PDFDocument.dataRepresentation()
```

### What IS implemented
- UI-level password prompt blocks access to DocumentDetailView.
- `isPasswordProtected` persists through SwiftData save/fetch cycles.
- Each document's lock state is independent.

### What is NOT implemented
- **AES-256 encryption of the PDF file at rest** — the file is stored as plaintext.
- **Key derivation from the user's password** (PBKDF2/Argon2).
- **Keychain storage** of the derived encryption key or password hash.
- **App Switcher blur** — `SceneDelegate`/`WindowGroup` does not yet apply a UIVisualEffectView or replace the snapshot when the app resigns active.

---

## 2. Findings & Recommendations

### FINDING-01 · Critical · PDF not encrypted at rest

**Description:**  
`StorageManager.savePDF` writes `PDFDocument.dataRepresentation()` directly to disk. A document marked `isPasswordProtected = true` has the same bytes on disk as an unlocked document.

**Reproduction:**  
1. Lock a document in-app.  
2. Use Finder → iPhone → Files → ScanHonest to browse the Documents/ScanHonest folder.  
3. Open the UUID-named `.pdf` file — content is fully readable without a password.

**Recommendation:**  
Encrypt the PDF data before writing, decrypt on load:

```swift
import CryptoKit

// Key derivation (store salt in Keychain, not in the file)
func deriveKey(from password: String, salt: Data) -> SymmetricKey {
    let passwordData = Data(password.utf8)
    // PBKDF2-SHA256 via CommonCrypto or a third-party wrapper
    // Minimum 100,000 iterations for NIST compliance
    return SymmetricKey(data: PBKDF2.sha256(password: passwordData, salt: salt, rounds: 100_000, keyLength: 32))
}

// Encrypt before writing
func encryptPDF(_ data: Data, key: SymmetricKey) throws -> Data {
    let sealedBox = try AES.GCM.seal(data, using: key)
    return sealedBox.combined!   // nonce (12 B) + ciphertext + tag (16 B)
}

// Decrypt after reading
func decryptPDF(_ encryptedData: Data, key: SymmetricKey) throws -> Data {
    let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
    return try AES.GCM.open(sealedBox, using: key)
}
```

Store the per-document **salt** in the Keychain, keyed by `document.id`. Never store the password or the derived key directly.

---

### FINDING-02 · Critical · No App Switcher blur

**Description:**  
When a locked document is open and the user invokes the App Switcher, iOS captures a screenshot of the current UI. This screenshot is visible in the Switcher without any authentication. The app does not yet apply a blur or placeholder.

**Reproduction:**  
1. Open a "password-protected" document.  
2. Double-click Home or swipe up to App Switcher.  
3. The document content is fully visible in the card.

**Recommendation:**  
In your `@main` SwiftUI `App` or the connected `UIWindowScene`, observe the resign-active notification and overlay a blur:

```swift
// In SceneDelegate or via UIWindowSceneDelegate
func sceneWillResignActive(_ scene: UIScene) {
    guard documentIsLocked else { return }
    let blur = UIBlurEffect(style: .systemMaterialDark)
    let overlay = UIVisualEffectView(effect: blur)
    overlay.frame = window?.bounds ?? .zero
    overlay.tag = 9999
    window?.addSubview(overlay)
}

func sceneDidBecomeActive(_ scene: UIScene) {
    window?.viewWithTag(9999)?.removeFromSuperview()
    // Then present the password/biometric prompt
}
```

Alternatively, in SwiftUI with `@Environment(\.scenePhase)`:

```swift
.onChange(of: scenePhase) { phase in
    switch phase {
    case .inactive, .background:
        if viewModel.currentDocumentIsLocked {
            showPrivacyOverlay = true
        }
    case .active:
        showPrivacyOverlay = false
        if viewModel.currentDocumentIsLocked {
            promptForAuthentication()
        }
    }
}
```

---

### FINDING-03 · High · Password not stored in Keychain

**Description:**  
The current model stores only a Bool flag. Any future password implementation must **not** store the password in UserDefaults, SwiftData, or the app's Documents directory. Passwords must be stored as a cryptographic hash (salted PBKDF2/bcrypt) or the derived key must be stored in the iOS Keychain.

**Recommendation:**  
Use `SecItemAdd` / `SecItemCopyMatching` with `kSecClassGenericPassword`:

```swift
func storePasswordHash(_ hash: Data, for documentID: UUID) throws {
    let query: [CFString: Any] = [
        kSecClass:            kSecClassGenericPassword,
        kSecAttrAccount:      documentID.uuidString,
        kSecAttrService:      "com.afzal.ScanHonest.doclock",
        kSecValueData:        hash,
        kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    SecItemDelete(query as CFDictionary)   // remove any existing entry
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.storeFailed(status)
    }
}
```

Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — this prevents the Keychain item from migrating to iCloud Keychain or a restored backup on another device.

---

### FINDING-04 · Medium · Biometric fallback not implemented

**Description:**  
The `isPasswordProtected` flag has no associated LocalAuthentication flow. The UI shows a lock icon but tapping it does not yet trigger `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.

**Recommendation:**

```swift
import LocalAuthentication

func authenticateWithBiometrics(reason: String) async -> Bool {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        return false   // fall back to PIN
    }
    do {
        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    } catch {
        return false   // authentication failed or cancelled → show PIN sheet
    }
}
```

**Fallback chain:**  
FaceID/TouchID → PIN entry → "Forgot password?" (re-encrypt with new password, requires old password verification)

---

### FINDING-05 · Medium · iCloud Backup of plaintext PDFs

**Description:**  
Documents in `Documents/ScanHonest/` are included in iCloud Backup by default. A plaintext "locked" PDF will be backed up unencrypted, accessible to anyone who restores from that backup.

**Recommendation:**  
Either:  
(a) Encrypt the file (FINDING-01) so the backup copy is also encrypted, OR  
(b) Set `URLResourceValues.isExcludedFromBackup = true` for locked documents and store them in a separate directory.

```swift
// Exclude from backup (use only if encryption is not yet implemented)
var values = URLResourceValues()
values.isExcludedFromBackup = true
try url.setResourceValues(values)
```

Note: Option (b) breaks the Pro iCloud sync feature — prefer encryption (a).

---

### FINDING-06 · Low · No brute-force rate limiting

**Description:**  
The current flag-only implementation has no password entry UI, so brute-force is not currently possible. When PIN entry is implemented, there must be a delay or lockout after N failed attempts.

**Recommendation:**  
- After 3 failed attempts: 30-second delay.  
- After 10 failed attempts: require FaceID or device passcode to unlock.  
- Store attempt count in the Keychain (not UserDefaults — it's wiped by the user).

---

### FINDING-07 · Low · Thumbnail leakage

**Description:**  
`ScannedDocument.thumbnailData` is a plain JPEG blob in the SwiftData store. The Library grid renders thumbnails for all documents, including "locked" ones, before any authentication occurs.

**Recommendation:**  
- Redact the thumbnail in the Library when `isPasswordProtected == true`. Replace with a lock-icon placeholder.
- Do not store `thumbnailData` in the SwiftData model for locked documents — store it in the encrypted file payload instead.

---

## 3. Remediation Priority

| Finding | Severity | Effort | Priority |
|---------|----------|--------|----------|
| 01 — No AES-256 encryption | 🔴 Critical | Large | **P0 — block shipping** |
| 02 — No App Switcher blur | 🔴 Critical | Small | **P0 — block shipping** |
| 03 — Password not in Keychain | 🔴 High | Medium | **P1 — before password UI ships** |
| 04 — Biometric not wired up | 🟠 Medium | Medium | **P1** |
| 05 — iCloud backup of plaintext | 🟠 Medium | Small | **P1** |
| 06 — No brute-force protection | 🟡 Low | Medium | **P2** |
| 07 — Thumbnail leakage | 🟡 Low | Small | **P2** |

---

## 4. Automated Test Coverage Gaps

The following must be added to `PasswordProtectionTests.swift` once the encryption layer exists:

| Test | Why |
|------|-----|
| `testEncryptedFileIsNotReadableWithoutKey` | Verify ciphertext on disk is unreadable as a PDF |
| `testDecryptedContentMatchesOriginal` | SHA-256 round-trip through encrypt/decrypt |
| `testKeychainItemCreatedOnLock` | Verify `SecItemCopyMatching` succeeds after lock |
| `testKeychainItemDeletedOnUnlock` | Verify item removed when user removes password |
| `testBruteForceRateLimitEnforced` | N wrong PINs → delay/lockout |
| `testThumbnailNilForLockedDocument` | Thumbnail must be nil in the SwiftData model |

---

## 5. Compliance Notes

- **GDPR / CCPA:** Encrypted-at-rest satisfies the "appropriate technical measures" requirement for personal data stored on-device.
- **Apple App Store Guidelines §5.1.2:** Apps handling sensitive user data must implement appropriate security measures. A UI-only lock does not satisfy this for a paid document manager.
- **NIST SP 800-132:** Recommends PBKDF2 with ≥100,000 iterations for password-based key derivation.

---

## 6. Verification Checklist (post-fix)

After implementing the recommendations, re-verify each item:

- [ ] FINDING-01: Open Documents/ScanHonest/ in Finder — locked PDFs must appear as encrypted binary blobs (no readable PDF header `%PDF-`)
- [ ] FINDING-02: With locked doc open → App Switcher → document content not visible
- [ ] FINDING-03: `SecItemCopyMatching` returns a hash for locked documents; `UserDefaults` contains no password data
- [ ] FINDING-04: FaceID prompt appears before PIN sheet; fallback works on simulator
- [ ] FINDING-05: `isExcludedFromBackup` = true OR file is encrypted (verify via device backup analysis)
- [ ] FINDING-06: Enter wrong PIN 10 times → lockout screen appears
- [ ] FINDING-07: Library grid shows lock-icon placeholder for locked docs
