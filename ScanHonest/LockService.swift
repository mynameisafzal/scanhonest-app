// LockService.swift
// Target: ScanHonest main app ONLY
#if !WIDGET_EXTENSION

import Foundation
import Combine
import LocalAuthentication
import SwiftUI
import os.log

// MARK: - LockService
//
// Biometric (Face ID / Touch ID) app lock with a 30-second grace period.
//
// Behaviour:
//   • When `biometricLockEnabled` is true and the app moves to background:
//       – A 30-second grace timer starts.
//       – If the app returns to foreground within 30 s, no prompt is shown.
//       – If 30 s elapse before the app returns, `isLocked` flips to true.
//   • When `isLocked` is true, the UI is covered by `LockScreenView` which
//     calls `authenticate()` to trigger Face ID / Touch ID.
//   • Authentication failures keep the screen locked; the user can retry.
//   • If biometrics are unavailable, a device-passcode fallback is used
//     automatically (LAPolicy.deviceOwnerAuthentication).
//
// Usage:
//   1. Inject as @StateObject in ScanHonestApp.
//   2. Wrap root content in LockOverlayView.
//   3. Toggle `biometricLockEnabled` from SettingsView.

@MainActor
final class LockService: ObservableObject {

    static let shared = LockService()

    @Published private(set) var isLocked       = false
    @Published private(set) var isAuthenticating = false

    @AppStorage("biometricLockEnabled") var biometricLockEnabled = false

    private let logger = Logger(subsystem: "com.afzal.ScanHonest", category: "LockService")

    // 30-second grace window before locking
    private let gracePeriod: TimeInterval = 30
    private var backgroundedAt: Date?
    private var graceTask: Task<Void, Never>?

    private init() {
        observeLifecycleNotifications()
    }

    // MARK: - Lifecycle Observations

    private func observeLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name:     UIApplication.didEnterBackgroundNotification,
            object:   nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name:     UIApplication.willEnterForegroundNotification,
            object:   nil
        )
    }

    @objc private func appDidEnterBackground() {
        guard biometricLockEnabled else { return }
        backgroundedAt = Date()

        // Start grace period timer
        graceTask?.cancel()
        graceTask = Task { [weak self] in
            guard let self else { return }
            // Wait for grace period
            try? await Task.sleep(for: .seconds(gracePeriod))
            // If task wasn't cancelled (app is still in background), lock
            guard !Task.isCancelled else { return }
            logger.info("Grace period expired — locking app.")
            self.isLocked = true
        }
    }

    @objc private func appWillEnterForeground() {
        guard biometricLockEnabled else { return }

        let elapsed = backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0

        if elapsed < gracePeriod {
            // Back within grace window — cancel the pending lock timer
            graceTask?.cancel()
            graceTask = nil
            logger.debug("Returned within grace window (\(String(format: "%.1f", elapsed))s) — no lock prompt.")
        } else {
            // Grace window already expired (graceTask fired isLocked = true);
            // ensure locked state is set even if the timer fired slightly late.
            if !isLocked { isLocked = true }
        }
        backgroundedAt = nil
    }

    // MARK: - Authenticate

    /// Prompts Face ID / Touch ID (with passcode fallback).
    /// Sets `isLocked = false` on success.
    func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true

        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication: biometrics first, passcode fallback
        let policy = LAPolicy.deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            logger.warning("Biometrics unavailable: \(error?.localizedDescription ?? "unknown") — unlocking without auth.")
            // If device has no passcode / biometrics at all, unlock automatically
            isLocked         = false
            isAuthenticating = false
            return
        }

        context.evaluatePolicy(policy, localizedReason: "Unlock ScanHonest") { [weak self] success, authError in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                    self.logger.info("Authentication succeeded — app unlocked.")
                } else {
                    // Keep locked; user can tap "Unlock" again
                    self.logger.warning("Authentication failed: \(authError?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    // MARK: - Manual Lock / Unlock

    /// Immediately locks the app (e.g. called from a "Lock Now" button).
    ///
    /// No-ops silently if `isPro` is false — the UI should have shown the paywall
    /// before reaching this call, but this prevents accidental service-level leakage.
    func lockNow(isPro: Bool = true) {
        guard biometricLockEnabled, isPro else { return }
        isLocked = true
    }

    /// Bypasses biometric lock — call only from tests or after verified unlock.
    func forceUnlock() {
        isLocked = false
    }
}

// MARK: - LockScreenView

/// Full-screen overlay shown when `LockService.isLocked == true`.
struct LockScreenView: View {
    @ObservedObject var lockService: LockService

    var body: some View {
        ZStack {
            // Blurred background — same material as privacy shield
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: biometricIcon)
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.white)

                VStack(spacing: 6) {
                    Text("ScanHonest is Locked")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Authenticate to access your documents.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Button {
                    lockService.authenticate()
                } label: {
                    HStack(spacing: 8) {
                        if lockService.isAuthenticating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: biometricIcon)
                        }
                        Text(lockService.isAuthenticating ? "Authenticating…" : "Unlock")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 14)
                    .background(.white)
                    .clipShape(Capsule())
                }
                .disabled(lockService.isAuthenticating)
            }
        }
        .onAppear {
            // Auto-prompt on appearance so the user doesn't have to tap manually
            // on the first lock after returning from background
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                lockService.authenticate()
            }
        }
    }

    private var biometricIcon: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "lock.fill"
        }
        return context.biometryType == .faceID ? "faceid" : "touchid"
    }
}

// MARK: - LockOverlayModifier

/// Wraps any view with the biometric lock overlay.
/// Apply once at the root, below `.privacyShielded()`.
struct LockOverlayModifier: ViewModifier {
    @ObservedObject var lockService: LockService

    func body(content: Content) -> some View {
        content
            .overlay {
                if lockService.isLocked {
                    LockScreenView(lockService: lockService)
                        .transition(.opacity)
                        .zIndex(8888)   // below privacy shield (9999), above everything else
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lockService.isLocked)
    }
}

extension View {
    /// Applies the biometric lock overlay driven by `lockService`.
    func biometricLocked(by lockService: LockService) -> some View {
        modifier(LockOverlayModifier(lockService: lockService))
    }
}

#endif
