import SwiftUI
import Combine

@MainActor
class ScanLimitManager: ObservableObject {

    static let freeMonthlyLimit = 5

    @Published private(set) var scansUsedThisMonth: Int = 0

    private let defaults  = UserDefaults.standard
    private let scansKey  = "scansUsedThisMonth"
    private let resetKey  = "scanCountResetDate"
    // FIX: track first-install date so reset cycle is 30 days from install, not calendar month
    private let installKey = "appFirstInstallDate"

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

    /// Dynamic reset date — 30 days from current cycle start, not a fixed calendar date
    var nextResetFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: nextResetDate)
    }

    var nextResetDate: Date {
        // Find the start of the current 30-day cycle from first install
        let install = installDate
        let now     = Date()
        let elapsed = now.timeIntervalSince(install)
        let period: TimeInterval = 30 * 24 * 3600   // 30 days in seconds
        // How many full periods have elapsed since install?
        let cyclesPassed = floor(elapsed / period)
        // Start of the CURRENT period
        let cycleStart = install.addingTimeInterval(cyclesPassed * period)
        // Next reset = start of NEXT period
        return cycleStart.addingTimeInterval(period)
    }

    private var installDate: Date {
        if let saved = defaults.object(forKey: installKey) as? Date { return saved }
        // First launch — record now as install date
        let now = Date()
        defaults.set(now, forKey: installKey)
        return now
    }

    func counterState(isPro: Bool) -> ScanCounterState {
        isPro ? .pro : .free(used: scansUsedThisMonth, limit: ScanLimitManager.freeMonthlyLimit)
    }

    // MARK: - Init

    init() {
        checkAndResetIfNeeded()
        scansUsedThisMonth = defaults.integer(forKey: scansKey)
    }

    // MARK: - Mutations

    func recordScan() {
        checkAndResetIfNeeded()
        guard !hasReachedLimit else { return }
        scansUsedThisMonth += 1
        defaults.set(scansUsedThisMonth, forKey: scansKey)
        if scansUsedThisMonth == ScanLimitManager.freeMonthlyLimit - 1 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    func resetCount() {
        scansUsedThisMonth = 0
        defaults.set(0, forKey: scansKey)
        // Also reset the cycle — next reset will be 30 days from now
        defaults.set(Date(), forKey: installKey)
        defaults.removeObject(forKey: resetKey)
    }

    // MARK: - FIX: 30-day cycle reset (dynamic, tied to install date)

    private func checkAndResetIfNeeded() {
        let now     = Date()
        let _       = installDate   // ensures installDate is written on first launch
        let period: TimeInterval = 30 * 24 * 3600

        // Last reset timestamp
        let lastReset = defaults.double(forKey: resetKey)

        if lastReset == 0 {
            // Never reset — record now as first cycle start
            defaults.set(now.timeIntervalSince1970, forKey: resetKey)
            return
        }

        let lastResetDate = Date(timeIntervalSince1970: lastReset)
        let timeSinceLastReset = now.timeIntervalSince(lastResetDate)

        // If a full 30-day period has passed since last reset → reset
        if timeSinceLastReset >= period {
            defaults.set(0, forKey: scansKey)
            defaults.set(now.timeIntervalSince1970, forKey: resetKey)
            scansUsedThisMonth = 0
        }
    }
}
