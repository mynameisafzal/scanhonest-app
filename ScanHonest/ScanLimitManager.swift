import SwiftUI
import Combine

// MARK: - UserDefaults keys (file-scope)
//
// PERMANENT FIX for "Main actor-isolated static property can not be referenced
// from a nonisolated context":
//
// In Swift 6, ALL members of a @MainActor class — including `static let` —
// inherit @MainActor isolation. There is no way to opt a static property out
// of actor isolation while it lives inside a @MainActor class declaration.
//
// The only guaranteed-permanent solution is to move the keys to FILE SCOPE.
// File-scope constants have no actor isolation by definition. They are safe
// to access from @MainActor, nonisolated, Task.detached, or any other context.
// This will never produce an actor-isolation error regardless of Swift version.

private let scanLimitScansKey   = "scansUsedThisMonth"
private let scanLimitResetKey   = "scanCountResetDate"
private let scanLimitInstallKey = "appFirstInstallDate"

// MARK: - ScanLimitManager

@MainActor
class ScanLimitManager: ObservableObject {

    static let freeMonthlyLimit = 5

    @Published private(set) var scansUsedThisMonth: Int = 0

    // MARK: - Derived state

    var scansRemaining: Int { max(0, ScanLimitManager.freeMonthlyLimit - scansUsedThisMonth) }
    var hasReachedLimit: Bool { scansUsedThisMonth >= ScanLimitManager.freeMonthlyLimit }
    var progressFraction: Double {
        min(1.0, Double(scansUsedThisMonth) / Double(ScanLimitManager.freeMonthlyLimit))
    }

    var progressColor: Color {
        let r = progressFraction
        if r >= 1.0 { return Color("Danger") }
        if r >= 0.8 { return Color("Warn")   }
        return Color("AccentGreen")
    }

    var nextResetFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: nextResetDate)
    }

    var nextResetDate: Date {
        let install = ScanLimitManager.readInstallDate()
        let now     = Date()
        let elapsed = now.timeIntervalSince(install)
        let period: TimeInterval = 30 * 24 * 3600
        let cyclesPassed = floor(elapsed / period)
        let cycleStart   = install.addingTimeInterval(cyclesPassed * period)
        return cycleStart.addingTimeInterval(period)
    }

    func counterState(isPro: Bool) -> ScanCounterState {
        isPro ? .pro : .free(used: scansUsedThisMonth, limit: ScanLimitManager.freeMonthlyLimit)
    }

    // MARK: - Init

    init() {
        ScanLimitManager.checkAndResetIfNeeded()
        scansUsedThisMonth = UserDefaults.standard.integer(forKey: scanLimitScansKey)
    }

    // MARK: - Mutations

    func recordScan() {
        ScanLimitManager.checkAndResetIfNeeded()
        scansUsedThisMonth = UserDefaults.standard.integer(forKey: scanLimitScansKey)
        guard !hasReachedLimit else { return }
        scansUsedThisMonth += 1
        UserDefaults.standard.set(scansUsedThisMonth, forKey: scanLimitScansKey)
        if scansUsedThisMonth == ScanLimitManager.freeMonthlyLimit - 1 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    func resetCount() {
        scansUsedThisMonth = 0
        UserDefaults.standard.set(0,        forKey: scanLimitScansKey)
        UserDefaults.standard.set(Date(),   forKey: scanLimitInstallKey)
        UserDefaults.standard.removeObject(forKey: scanLimitResetKey)
    }

    // MARK: - nonisolated static helpers
    //
    // Static methods on a @MainActor class are also @MainActor-isolated in Swift 6.
    // Marking them `nonisolated` overrides that so they can be called from any
    // concurrency context. They are safe because they only touch:
    //   • UserDefaults.standard  — a thread-safe global singleton
    //   • File-scope key constants — no actor isolation, accessible everywhere

    private nonisolated static func readInstallDate() -> Date {
        let ud = UserDefaults.standard
        if let saved = ud.object(forKey: scanLimitInstallKey) as? Date { return saved }
        let now = Date()
        ud.set(now, forKey: scanLimitInstallKey)
        return now
    }

    private nonisolated static func checkAndResetIfNeeded() {
        let ud  = UserDefaults.standard
        let now = Date()
        _ = readInstallDate()

        let lastReset = ud.double(forKey: scanLimitResetKey)
        if lastReset == 0 {
            ud.set(now.timeIntervalSince1970, forKey: scanLimitResetKey)
            return
        }

        let elapsed = now.timeIntervalSince(Date(timeIntervalSince1970: lastReset))
        if elapsed >= 30 * 24 * 3600 {
            ud.set(0,                         forKey: scanLimitScansKey)
            ud.set(now.timeIntervalSince1970, forKey: scanLimitResetKey)
        }
    }
}
