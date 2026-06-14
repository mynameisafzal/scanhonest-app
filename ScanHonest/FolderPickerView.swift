import SwiftUI
import SwiftData

// MARK: - FolderPickerView

struct FolderPickerView: View {
    let document: ScannedDocument
    let isPro: Bool
    var onDone: () -> Void = {}

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentFolder.name) private var folders: [DocumentFolder]

    @State private var showNewFolderSheet = false
    @State private var newFolderName      = ""
    @State private var newFolderColor     = FolderColor.forest
    @State private var isCreating         = false
    @State private var errorMessage: String?

    enum FolderColor: String, CaseIterable, Identifiable {
        case forest = "1B4332"
        case ocean  = "1A4F6E"
        case berry  = "6B2D5E"
        case rust   = "8B3A2F"
        case gold   = "7A5C00"
        case slate  = "3A4A5C"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .forest: return "Forest"
            case .ocean:  return "Ocean"
            case .berry:  return "Berry"
            case .rust:   return "Rust"
            case .gold:   return "Gold"
            case .slate:  return "Slate"
            }
        }
        var color: Color {
            switch self {
            case .forest: return Color(red: 0.11, green: 0.26, blue: 0.20)
            case .ocean:  return Color(red: 0.10, green: 0.31, blue: 0.43)
            case .berry:  return Color(red: 0.42, green: 0.18, blue: 0.37)
            case .rust:   return Color(red: 0.55, green: 0.23, blue: 0.18)
            case .gold:   return Color(red: 0.48, green: 0.36, blue: 0.00)
            case .slate:  return Color(red: 0.23, green: 0.29, blue: 0.36)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                VStack(spacing: 0) {
                    folderList
                    Divider()
                    createButton
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color("TextMuted"))
                }
            }
            .sheet(isPresented: $showNewFolderSheet) { newFolderSheet }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    // MARK: Folder list

    private var folderList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                FolderRow(
                    icon: "tray", name: "All Documents",
                    subtitle: "Remove from folder",
                    color: Color("TextMuted"),
                    isActive: document.folder == nil
                ) { move(to: nil) }

                Divider().padding(.leading, 56)

                if folders.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundColor(Color("TextMuted").opacity(0.4))
                            .padding(.top, 40)
                        Text("No folders yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                        Text("Tap \"New Folder\" to create one")
                            .font(.system(size: 13))
                            .foregroundColor(Color("TextMuted").opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 24)
                } else {
                    ForEach(folders) { folder in
                        FolderRow(
                            icon: "folder.fill",
                            name: folder.name,
                            subtitle: "\(folder.documents.count) document\(folder.documents.count == 1 ? "" : "s")",
                            color: colorFromHex(folder.colorHex),
                            isActive: document.folder?.id == folder.id
                        ) { move(to: folder) }
                        if folder.id != folders.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("Hairline"), lineWidth: 1))
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        }
    }

    // MARK: Create button

    private var createButton: some View {
        Button {
            newFolderName = ""; newFolderColor = .forest
            showNewFolderSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus").font(.system(size: 17, weight: .semibold))
                Text("New Folder").font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
            .background(Color("PrimaryGreen")).clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color("Background"))
    }

    // MARK: New folder sheet

    private var newFolderSheet: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Folder Name")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                            TextField("e.g. Physics, Receipts, Work...", text: $newFolderName)
                                .font(.system(size: 16)).foregroundColor(Color("TextPrimary"))
                                .padding(14).background(Color("Surface"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color("Hairline"), lineWidth: 1))
                                .autocorrectionDisabled(true).submitLabel(.done)
                                .onSubmit { createFolderAndMove() }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Colour").font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                            HStack(spacing: 10) {
                                ForEach(FolderColor.allCases) { fc in
                                    Button {
                                        newFolderColor = fc
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        ZStack {
                                            Circle().fill(fc.color).frame(width: 36, height: 36)
                                            if newFolderColor == fc {
                                                Circle().strokeBorder(.white, lineWidth: 2)
                                                    .frame(width: 36, height: 36)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }.buttonStyle(.plain)
                                }
                                Spacer()
                            }
                        }
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(newFolderColor.color.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(newFolderColor.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(newFolderName.isEmpty ? "Folder Name" : newFolderName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(newFolderName.isEmpty
                                        ? Color("TextMuted") : Color("TextPrimary"))
                                Text("0 documents")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color("TextMuted"))
                            }
                            Spacer()
                        }
                        .padding(14).background(Color("Surface"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color("Hairline"), lineWidth: 1))
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                    Spacer()
                    Button { createFolderAndMove() } label: {
                        Group {
                            if isCreating { ProgressView().tint(.white) }
                            else {
                                Text("Create & Move Here")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color("TextMuted").opacity(0.3) : Color("PrimaryGreen"))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 20)
                }
            }
            .navigationTitle("New Folder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showNewFolderSheet = false }
                        .foregroundColor(Color("TextMuted"))
                }
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: Actions

    private func move(to folder: DocumentFolder?) {
        do {
            try FolderHierarchyService.shared.moveDocument(document, to: folder, isPro: isPro)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss(); onDone()
        } catch { errorMessage = error.localizedDescription }
    }

    private func createFolderAndMove() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        do {
            let folder = try FolderHierarchyService.shared.createFolder(
                name: name, colorHex: newFolderColor.rawValue,
                isPro: isPro, in: modelContext
            )
            try FolderHierarchyService.shared.moveDocument(document, to: folder, isPro: isPro)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showNewFolderSheet = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                dismiss(); onDone()
            }
        } catch {
            isCreating = false
            errorMessage = error.localizedDescription
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        FolderColor(rawValue: hex)?.color ?? Color(red: 0.11, green: 0.26, blue: 0.20)
    }
}

// MARK: - FolderRow

private struct FolderRow: View {
    let icon: String; let name: String; let subtitle: String
    let color: Color; let isActive: Bool; let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 18, weight: .medium))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                    Text(subtitle).font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color("TextMuted"))
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                        .foregroundColor(Color("AccentGreen"))
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("Hairline"))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    FolderPickerView(
        document: ScannedDocument(name: "Physics_Notes", pageCount: 5, fileSizeBytes: 1_200_000),
        isPro: true
    )
    .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}
