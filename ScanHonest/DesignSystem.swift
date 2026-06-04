import SwiftUI

// MARK: ─────────────────────────────────────────────
// DESIGN TOKENS  — single source of truth
// MARK: ─────────────────────────────────────────────

extension Color {
    static let shPrimary    = Color("PrimaryGreen")
    static let shSecondary  = Color("SecondaryGreen")
    static let shAccent     = Color("AccentGreen")
    static let shAccentSoft = Color("AccentSoft")
    static let shBackground = Color("Background")
    static let shSurface    = Color("Surface")
    static let shHairline   = Color("Hairline")
    static let shText       = Color("TextPrimary")
    static let shMuted      = Color("TextMuted")
    static let shDanger     = Color("Danger")
    static let shWarn       = Color("Warn")
    static let shGold       = Color("Gold")
}

struct SHFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func caption(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct SHSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

struct SHRadius {
    static let xs:     CGFloat = 4
    static let sm:     CGFloat = 8
    static let md:     CGFloat = 12
    static let lg:     CGFloat = 16
    static let xl:     CGFloat = 24
    static let button: CGFloat = 28
}

struct SHShadow: ViewModifier {
    var intensity: ShadowIntensity = .medium
    enum ShadowIntensity { case soft, medium, strong }
    func body(content: Content) -> some View {
        switch intensity {
        case .soft:
            content
                .shadow(color: .black.opacity(0.04), radius: 4,  x: 0, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 8,  x: 0, y: 2)
        case .medium:
            content
                .shadow(color: .black.opacity(0.06), radius: 8,  x: 0, y: 2)
                .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 4)
                .shadow(color: .black.opacity(0.02), radius: 24, x: 0, y: 8)
        case .strong:
            content
                .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 8)
                .shadow(color: .black.opacity(0.03), radius: 48, x: 0, y: 16)
        }
    }
}

extension View {
    func shShadow(_ i: SHShadow.ShadowIntensity = .medium) -> some View { modifier(SHShadow(intensity: i)) }
    func shCard() -> some View {
        self.background(Color.shSurface).cornerRadius(SHRadius.lg).shShadow(.soft)
    }
}

// MARK: - Button Styles

struct SHPrimaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SHFont.body(17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, SHSpacing.md)
            .padding(.horizontal, SHSpacing.lg)
            .background(Color.shPrimary)
            .cornerRadius(SHRadius.button)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SHSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SHFont.body(17, weight: .medium))
            .foregroundColor(Color.shPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SHSpacing.md)
            .padding(.horizontal, SHSpacing.lg)
            .background(Color.clear)
            .overlay(RoundedRectangle(cornerRadius: SHRadius.button).stroke(Color.shPrimary, lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: ─────────────────────────────────────────────
// BADGE SYSTEM
// MARK: ─────────────────────────────────────────────

enum SHBadgeVariant {
    case pro, free, new_, limitNear, limitReached, optional_, ocrPro, upgradeUnlock

    var bg: Color {
        switch self {
        case .pro:           return Color.shGold
        case .free:          return .clear
        case .new_:          return Color.shAccent
        case .limitNear:     return Color.shWarn
        case .limitReached:  return Color.shDanger
        case .optional_:     return Color.shMuted.opacity(0.1)
        case .ocrPro:        return Color.shGold
        case .upgradeUnlock: return Color.shPrimary
        }
    }
    var fg: Color {
        switch self {
        case .free, .optional_: return Color.shMuted
        default:                return .white
        }
    }
    var border: Color? {
        switch self {
        case .free:     return Color.shHairline
        case .optional_: return Color.shMuted.opacity(0.3)
        default:        return nil
        }
    }
}

struct SHBadge: View {
    let label: String
    let variant: SHBadgeVariant
    var size: BadgeSize = .regular

    enum BadgeSize {
        case small, regular, large
        var font: CGFloat   { switch self { case .small: return 9;  case .regular: return 10; case .large: return 11 } }
        var hPad: CGFloat   { switch self { case .small: return 5;  case .regular: return 7;  case .large: return 10 } }
        var vPad: CGFloat   { switch self { case .small: return 2;  case .regular: return 3;  case .large: return 4  } }
    }

    var body: some View {
        Text(label)
            .font(SHFont.mono(size.font, weight: .semibold))
            .textCase(.uppercase)
            .foregroundColor(variant.fg)
            .padding(.horizontal, size.hPad)
            .padding(.vertical,   size.vPad)
            .background(variant.bg)
            .clipShape(Capsule())
            .overlay {
                if let b = variant.border { Capsule().stroke(b, lineWidth: 1) }
            }
            .accessibilityLabel(label)
    }
}

// Convenience wrappers
struct ProBadge: View {
    var size: SHBadge.BadgeSize = .regular
    var body: some View { SHBadge(label: "PRO", variant: .pro, size: size) }
}
struct FreeBadge:            View { var body: some View { SHBadge(label: "FREE",             variant: .free)          } }
struct NewBadge:             View { var body: some View { SHBadge(label: "NEW",              variant: .new_)          } }
struct LimitNearBadge:       View { var body: some View { SHBadge(label: "LIMIT NEAR",       variant: .limitNear)     } }
struct LimitReachedBadge:    View { var body: some View { SHBadge(label: "LIMIT REACHED",    variant: .limitReached)  } }
struct OptionalBadge:        View { var body: some View { SHBadge(label: "OPTIONAL",         variant: .optional_)     } }
struct OcrProBadge:          View { var body: some View { SHBadge(label: "OCR · PRO",        variant: .ocrPro)        } }
struct UpgradeToUnlockBadge: View { var body: some View { SHBadge(label: "UPGRADE TO UNLOCK",variant: .upgradeUnlock) } }

// MARK: ─────────────────────────────────────────────
// SCAN COUNTER STATE + VIEW
// MARK: ─────────────────────────────────────────────

enum ScanCounterState: Equatable {
    case pro
    case free(used: Int, limit: Int)

    var fraction: Double {
        guard case .free(let used, let limit) = self, limit > 0 else { return 0 }
        return min(1.0, Double(used) / Double(limit))
    }
    var barColor: Color {
        guard case .free(let used, let limit) = self else { return Color.shAccent }
        let r = Double(used) / Double(max(limit, 1))
        if r >= 1.0 { return Color.shDanger }
        if r >= 0.8 { return Color.shWarn   }
        return Color.shAccent
    }
    var isAtLimit:   Bool { guard case .free(let u, let l) = self else { return false }; return u >= l }
    var isNearLimit: Bool {
        guard case .free(let u, let l) = self else { return false }
        let r = Double(u) / Double(max(l, 1)); return r >= 0.8 && r < 1.0
    }
}

struct ScanCounterView: View {
    let state: ScanCounterState
    let resetDate: String
    var onUpgradeTap: (() -> Void)? = nil

    var body: some View {
        switch state {
        case .pro:                         proView
        case .free(let used, let limit):   freeView(used: used, limit: limit)
        }
    }

    // Pro: infinity glyph, no progress bar
    private var proView: some View {
        HStack(spacing: SHSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16)).foregroundColor(Color.shAccent)
            Text("Pro · Unlimited scans")
                .font(SHFont.body(14, weight: .medium)).foregroundColor(Color.shText)
            Spacer()
            Image(systemName: "infinity")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.shAccent)
            ProBadge()
        }
        .padding(.horizontal, SHSpacing.md)
        .padding(.vertical, 12)
        .background(Color.shSurface)
        .cornerRadius(SHRadius.md)
        .overlay(RoundedRectangle(cornerRadius: SHRadius.md).stroke(Color.shHairline, lineWidth: 1))
        .accessibilityLabel("Pro plan. Unlimited scans.")
    }

    // Free: counter + color-coded progress + badges
    private func freeView(used: Int, limit: Int) -> some View {
        let cs = ScanCounterState.free(used: used, limit: limit)
        let color     = cs.barColor
        let remaining = max(0, limit - used)
        let isLimit   = used >= limit
        let isNear    = !isLimit && Double(used) / Double(max(limit, 1)) >= 0.8

        return VStack(alignment: .leading, spacing: SHSpacing.xs) {
            HStack(alignment: .center, spacing: SHSpacing.xs) {
                HStack(spacing: 0) {
                    Text("\(used)")
                        .font(SHFont.mono(12, weight: .semibold))
                        .foregroundColor(color)
                    Text(" of \(limit) free scans used")
                        .font(SHFont.mono(12))
                        .foregroundColor(Color.shMuted)
                }
                if isLimit       { LimitReachedBadge() }
                else if isNear   { LimitNearBadge()    }
                Spacer(minLength: 0)
                if let tap = onUpgradeTap {
                    Button(action: tap) {
                        Text("Upgrade →")
                            .font(SHFont.mono(11, weight: .semibold))
                            .foregroundColor(isLimit ? Color.shDanger : Color.shPrimary)
                    }.buttonStyle(.plain)
                }
            }

            HStack(spacing: 0) {
                Text(isLimit ? "No scans left this month" : "\(remaining) remaining")
                    .font(SHFont.caption(11))
                    .foregroundColor(isLimit ? Color.shDanger : Color.shMuted)
                Text(" · resets ")
                    .font(SHFont.caption(11))
                    .foregroundColor(Color.shMuted)
                Text(resetDate)
                    .font(SHFont.mono(11))
                    .foregroundColor(Color.shMuted)
            }

            // Segmented bar — 1 capsule per scan slot, colour-coded per design spec:
            //   segments 1–2 (lower 40 %): green  · segments 3–4 (middle): amber
            //   last segment: red  · unfilled slots: hairline grey
            HStack(spacing: 3) {
                ForEach(0..<limit, id: \.self) { idx in
                    Capsule()
                        .fill(idx < used ? segmentColor(idx: idx, limit: limit)
                                         : Color.shHairline.opacity(0.5))
                        .frame(height: 5)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: used)
                }
            }
            .frame(height: 5)

        }
        .padding(.horizontal, SHSpacing.md)
        .padding(.vertical, 12)
        .background(Color.shSurface)
        .cornerRadius(SHRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: SHRadius.md)
                .stroke(isLimit ? Color.shDanger.opacity(0.3) : Color.shHairline, lineWidth: 1)
        )
        .accessibilityLabel(
            isLimit
                ? "Scan limit reached. \(limit) of \(limit) used. Resets \(resetDate)."
                : "\(used) of \(limit) scans used. \(remaining) remaining. Resets \(resetDate)."
        )
    }

    /// Colour for a filled segment at `idx` out of `limit` slots.
    /// Matches design spec (ScanHonest-Components.html #scan-counter):
    ///   lower 40 % of slots → green · upper slots before last → amber · last slot → red
    private func segmentColor(idx: Int, limit: Int) -> Color {
        if idx == limit - 1 { return Color.shDanger }                          // last: red
        if Double(idx + 1) / Double(limit) > 0.4 { return Color.shWarn }      // upper: amber
        return Color.shAccent                                                   // lower: green
    }
}

// MARK: - Pro Lock Overlay

struct ProLockOverlay: View {
    var featureName: String = "This feature"
    var onUpgrade: () -> Void
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).cornerRadius(SHRadius.md)
            VStack(spacing: SHSpacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color.shPrimary)
                Text("\(featureName) requires Pro")
                    .font(SHFont.body(13, weight: .medium))
                    .foregroundColor(Color.shText)
                    .multilineTextAlignment(.center)
                Button("Upgrade", action: onUpgrade)
                    .font(SHFont.body(13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, SHSpacing.md).padding(.vertical, 7)
                    .background(Color.shPrimary).cornerRadius(SHRadius.button)
            }
            .padding(SHSpacing.md)
        }
    }
}

// MARK: - Locked Feature Row (Settings)

struct LockedFeatureRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var onUpgrade: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.shMuted).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SHFont.body(16)).foregroundColor(Color.shMuted)
                if let s = subtitle { Text(s).font(SHFont.caption(13)).foregroundColor(Color.shMuted.opacity(0.7)) }
            }
            Spacer(minLength: 8)
            Button(action: onUpgrade) { UpgradeToUnlockBadge() }.buttonStyle(.plain)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, SHSpacing.md).padding(.vertical, SHSpacing.sm)
        .opacity(0.75)
        .accessibilityLabel("\(title). Pro feature. Tap to upgrade.")
    }
}

// MARK: - Subscription State Card

enum SubscriptionCardState {
    case freeTier(scansRemaining: Int, resetDate: String)
    case proLifetime(purchaseDate: String, price: String)
    case proMonthlyActive(renewDate: String)
    case proMonthlyExpiring(expiryDate: String)
    case proExpired
}

struct SubscriptionStateCard: View {
    let state: SubscriptionCardState
    var onUpgrade: (() -> Void)? = nil
    var onManage:  (() -> Void)? = nil

    var body: some View {
        switch state {
        case .freeTier(let rem, let reset):
            freeTierCard(remaining: rem, resetDate: reset)
        case .proLifetime(let date, let price):
            proCard(badge: "LIFETIME",  headline: "Lifetime · Unlimited",  detail: "Purchased \(date) · \(price)")
        case .proMonthlyActive(let date):
            proCard(badge: "MONTHLY",   headline: "Monthly · Unlimited",   detail: "Renews \(date)")
        case .proMonthlyExpiring(let date):
            proCard(badge: "EXPIRING",  headline: "Cancels \(date)",       detail: "Tap to resubscribe",
                    colors: [Color.shWarn, Color.shWarn.opacity(0.7)], action: onManage, actionLabel: "Resubscribe")
        case .proExpired:
            expiredCard()
        }
    }

    private func freeTierCard(remaining: Int, resetDate: String) -> some View {
        Button(action: { onUpgrade?() }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upgrade to Pro").font(SHFont.body(17, weight: .semibold)).foregroundColor(Color.shAccent)
                    Text("\(remaining) free scans remaining · resets \(resetDate)")
                        .font(SHFont.caption(13)).foregroundColor(Color.shMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Color.shMuted)
            }
            .padding(.horizontal, SHSpacing.md).padding(.vertical, SHSpacing.md)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: SHRadius.lg))
    }

    private func proCard(badge: String, headline: String, detail: String,
                         colors: [Color] = [Color.shPrimary, Color.shSecondary],
                         action: (() -> Void)? = nil, actionLabel: String? = nil) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle().fill(Color.shAccentSoft.opacity(0.25)).frame(width: 120, height: 120).offset(x: 24, y: -32)
            VStack(alignment: .leading, spacing: SHSpacing.sm) {
                Text("SCANHONEST \(badge)").font(SHFont.mono(10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8)).tracking(1.2)
                Text(headline).font(SHFont.display(22, weight: .bold)).foregroundColor(.white)
                Text(detail).font(SHFont.mono(12, weight: .medium)).foregroundColor(.white.opacity(0.8))
                if let lbl = actionLabel, let act = action {
                    Button(action: act) {
                        Text(lbl).font(SHFont.body(13, weight: .semibold))
                            .foregroundColor(colors.first ?? Color.shPrimary)
                            .padding(.horizontal, SHSpacing.md).padding(.vertical, 6)
                            .background(Color.white).cornerRadius(SHRadius.button)
                    }.buttonStyle(.plain).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(SHSpacing.md)
        }
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: SHRadius.lg))
    }

    private func expiredCard() -> some View {
        Button(action: { onUpgrade?() }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Pro subscription ended").font(SHFont.body(15, weight: .semibold)).foregroundColor(Color.shText)
                    Text("Renew from $1.99/month").font(SHFont.caption(13)).foregroundColor(Color.shMuted)
                }
                Spacer()
                SHBadge(label: "EXPIRED", variant: .limitReached)
            }
            .padding(.horizontal, SHSpacing.md).padding(.vertical, SHSpacing.md)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: SHRadius.lg))
    }
}
