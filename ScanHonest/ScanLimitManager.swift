import SwiftUI
import Combine

class ScanLimitManager: ObservableObject {
    static let freeMonthlyLimit = 5

    @Published var scansUsedThisMonth: Int = 0

    private let defaults = UserDefaults.standard
    private let scansKey = "scansUsedThisMonth"
    private let resetKey = "scanCountResetDate"

    var scansRemaining: Int {
        max(0, ScanLimitManager.freeMonthlyLimit - scansUsedThisMonth)
    }

    var hasReachedLimit: Bool {
        scansUsedThisMonth >= ScanLimitManager.freeMonthlyLimit
    }

    var progressFraction: Double {
        min(1.0, Double(scansUsedThisMonth) / Double(ScanLimitManager.freeMonthlyLimit))
    }

    var progressColor: Color {
        switch scansUsedThisMonth {
        case 0...3: return Color("AccentGreen")
        case 4:     return .orange
        default:    return .red
        }
    }

    var nextResetFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: nextMonthDate)
    }

    private var nextMonthDate: Date {
        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }

    init() {
        checkAndResetIfNeeded()
        scansUsedThisMonth = defaults.integer(forKey: scansKey)
    }

    func recordScan() {
        checkAndResetIfNeeded()
        scansUsedThisMonth += 1
        defaults.set(scansUsedThisMonth, forKey: scansKey)
    }

    private func checkAndResetIfNeeded() {
        let now = Date()
        let saved = defaults.double(forKey: resetKey)
        let savedDate = saved == 0 ? now : Date(timeIntervalSince1970: saved)
        if !Calendar.current.isDate(now, equalTo: savedDate, toGranularity: .month) {
            defaults.set(0, forKey: scansKey)
            defaults.set(now.timeIntervalSince1970, forKey: resetKey)
            scansUsedThisMonth = 0
        }
    }
}
