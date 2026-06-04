// PopupViews.swift
//
// Custom bottom-sheet and centered-modal popups that match the ScanHonest
// design system exactly.
//
//   • ImportChoicePopup   — Screen 11B-A: source picker for the Import flow
//   • OCRProPopup         — Screen 11B-B: upgrade prompt when a free user taps OCR
//   • DeleteDocumentPopup — Screen 11C:  destructive-action confirmation

import SwiftUI

// MARK: - Shared helpers

/// A view that renders a standard drag-handle pill (36×4, rounded, translucent).
private struct DragHandle: View {
    var body: some View {
        Capsule()
            .fill(Color.black.opacity(0.18))
            .frame(width: 36, height: 4)
    }
}

/// Full-screen dim overlay used behind every popup.
private struct DimOverlay: View {
    let onTap: () -> Void
    var body: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
    }
}

// MARK: - 11B-A  Import Choice Popup
//
// Bottom sheet with two tappable source cards (Camera Roll / Files App)
// and a Cancel button.  Presented whenever the user taps the Import button.

struct ImportChoicePopup: View {
    let onCameraRoll: () -> Void
    let onFiles:      () -> Void
    let onCancel:     () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            DimOverlay(onTap: onCancel)

            VStack(spacing: 0) {
                // Drag handle
                DragHandle().padding(.top, 10).padding(.bottom, 18)

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Document")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(Color.shText)
                    Text("Choose your source")
                        .font(.system(size: 13))
                        .foregroundColor(Color.shMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Options
                VStack(spacing: 10) {
                    ImportOptionRow(
                        emoji: "🖼",
                        title: "Camera Roll",
                        sub:   "JPEG · HEIC · PNG",
                        action: onCameraRoll
                    )
                    ImportOptionRow(
                        emoji: "📄",
                        title: "Files App",
                        sub:   "PDF · images · any document",
                        action: onFiles
                    )
                }
                .padding(.horizontal, 20)

                // Cancel
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.shMuted)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.black.opacity(0.07))
                        .cornerRadius(25)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, max((UIApplication.shared
                    .connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first?.windows.first(where: \.isKeyWindow)?
                    .safeAreaInsets.bottom ?? 0), 16))
            }
            .background(
                Color.shBackground
                    .clipShape(RoundedCornerShape(radius: 28, corners: [.topLeft, .topRight]))
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .ignoresSafeArea()
    }
}

private struct ImportOptionRow: View {
    let emoji:  String
    let title:  String
    let sub:    String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Color.shAccentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.shText)
                    Text(sub)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.shMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.shPrimary.opacity(0.5))
            }
            .padding(16)
            .background(Color.shSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.shHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PopupRowButtonStyle())
    }
}

// MARK: - 11B-B  OCR Pro Popup
//
// Bottom sheet shown when a free user taps the OCR action.
// Lists four key benefits, then presents the paywall CTA.

struct OCRProPopup: View {
    let onUpgrade:    () -> Void
    let onMaybeLater: () -> Void

    private let features = [
        "Search inside any scanned document",
        "Copy & paste extracted text",
        "Export as plain .txt file",
        "Works offline — no cloud needed",
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            DimOverlay(onTap: onMaybeLater)

            VStack(spacing: 0) {
                // Drag handle
                DragHandle().padding(.top, 10).padding(.bottom, 20)

                // Icon + badge + headline
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.shAccentSoft)
                            .frame(width: 56, height: 56)
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(Color.shPrimary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("PRO FEATURE", systemImage: "star.fill")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.shGold)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.shGold.opacity(0.12))
                            .cornerRadius(999)

                        Text("Extract Text (OCR)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color.shText)
                        Text("Search inside your docs, copy text,\nand export as TXT.")
                            .font(.system(size: 13))
                            .foregroundColor(Color.shMuted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Feature list card
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.self) { f in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.shAccent)
                                .frame(width: 16)
                            Text(f)
                                .font(.system(size: 14))
                                .foregroundColor(Color.shText)
                        }
                    }
                }
                .padding(16)
                .background(Color.shSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.shHairline, lineWidth: 1))
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // CTA button
                Button(action: onUpgrade) {
                    Text("Upgrade to Pro — $4.99")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.shPrimary)
                        .cornerRadius(26)
                        .shadow(color: Color.shPrimary.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                // Maybe Later
                Button(action: onMaybeLater) {
                    Text("Maybe Later")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.shMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, max((UIApplication.shared
                    .connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first?.windows.first(where: \.isKeyWindow)?
                    .safeAreaInsets.bottom ?? 0), 16))
            }
            .background(
                Color.shBackground
                    .clipShape(RoundedCornerShape(radius: 28, corners: [.topLeft, .topRight]))
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - 11C  Delete Document Popup
//
// Centered modal with a red trash icon, the document name, and two actions.
// Uses an alert-card style (not a system dialog) to match the design spec.

struct DeleteDocumentPopup: View {
    let documentName: String
    let onDelete:     () -> Void
    let onCancel:     () -> Void

    var body: some View {
        ZStack {
            DimOverlay(onTap: onCancel)

            VStack(spacing: 0) {
                // Top content
                VStack(spacing: 0) {
                    // Red trash circle
                    ZStack {
                        Circle()
                            .fill(Color.shDanger.opacity(0.10))
                            .frame(width: 60, height: 60)
                        Image(systemName: "trash")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(Color.shDanger)
                    }
                    .padding(.bottom, 16)

                    Text("Delete Document?")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.shText)
                        .padding(.bottom, 8)

                    Group {
                        Text(documentName)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.shText)
                        + Text(" will be permanently removed and cannot be recovered.")
                            .foregroundColor(Color.shMuted)
                    }
                    .font(.system(size: 13.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 20)

                // Divider
                Divider().foregroundColor(Color.shHairline)

                // Delete button
                Button(action: {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    onDelete()
                }) {
                    Text("Delete Forever")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.shDanger)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)

                // Divider
                Divider().foregroundColor(Color.shHairline)

                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.shText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
            }
            .background(Color.shSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Helpers

/// Clips only specific corners of a shape.
private struct RoundedCornerShape: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

/// Scale-on-press style for popup rows.
private struct PopupRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Color tokens are provided by DesignSystem.swift (Color.shPrimary, .shText, etc.)
