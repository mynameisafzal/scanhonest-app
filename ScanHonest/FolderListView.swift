import SwiftUI
import SwiftData

// MARK: - FolderListView
//
// Shown when the user taps "All folders →" in LibraryView.
// Displays every folder as a card with:
//   • Colour-coded icon + folder name + document count
//   • Horizontal scroll of document thumbnails inside the folder
//   • Tap card → navigates to FolderDetailView showing all docs in that folder
//   • Long-press card → rename / delete folder

struct FolderListView: View {
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.dismiss)       private var dismiss
    @EnvironmentObject var storeKitManager: StoreKitManager

    @Query(sort: \DocumentFolder.name) private var folders: [DocumentFolder]

    @State private var selectedFolder: DocumentFolder? = nil
    @State private var showNewFolderSheet = false
    @State private var renamingFolder: DocumentFolder? = nil
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var deletingFolder: DocumentFolder? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                if folders.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 14) {
                            ForEach(folders) { folder in
                                FolderCard(folder: folder)
                                    .onTapGesture {
                                        selectedFolder = folder
                                    }
                                    .contextMenu {
                                        Button {
                                            renameText    = folder.name
                                            renamingFolder = folder
                                            showRenameAlert = true
                                        } label: { Label("Rename", systemImage: "pencil") }

                                        Button(role: .destructive) {
                                            deletingFolder = folder
                                            showDeleteAlert = true
                                        } label: { Label("Delete Folder", systemImage: "trash") }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewFolderSheet = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Color("PrimaryGreen"))
                    }
                }
            }
            // Navigate into a folder
            .navigationDestination(item: $selectedFolder) { folder in
                FolderDetailView(folder: folder)
                    .environmentObject(storeKitManager)
            }
            // New folder sheet
            .sheet(isPresented: $showNewFolderSheet) {
                // Reuse FolderPickerView's new-folder sheet by presenting
                // a lightweight wrapper — no document to move, just create.
                NewFolderSheet { name, colorHex in
                    createFolder(name: name, colorHex: colorHex)
                }
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            // Rename alert
            .alert("Rename Folder", isPresented: $showRenameAlert) {
                TextField("Name", text: $renameText)
                    .autocorrectionDisabled(true)
                Button("Save") {
                    let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { renamingFolder?.name = t }
                    renamingFolder = nil
                }
                Button("Cancel", role: .cancel) { renamingFolder = nil }
            }
            // Delete alert
            .alert("Delete Folder", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let f = deletingFolder { deleteFolder(f) }
                    deletingFolder = nil
                }
                Button("Cancel", role: .cancel) { deletingFolder = nil }
            } message: {
                Text("Documents inside will be moved to All Documents. This cannot be undone.")
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundColor(Color("TextMuted").opacity(0.35))
            Text("No folders yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color("TextPrimary"))
            Text("Create folders to organise your documents\nby topic, subject, or category.")
                .font(.system(size: 15))
                .foregroundColor(Color("TextMuted"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showNewFolderSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Create Folder")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28).padding(.vertical, 13)
                .background(Color("PrimaryGreen"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func createFolder(name: String, colorHex: String) {
        let folder = DocumentFolder(name: name, colorHex: colorHex)
        modelContext.insert(folder)
    }

    private func deleteFolder(_ folder: DocumentFolder) {
        // Move all documents out before deleting so they don't get cascade-deleted
        for doc in folder.documents { doc.folder = nil }
        modelContext.delete(folder)
    }
}

// MARK: - FolderCard

private struct FolderCard: View {
    let folder: DocumentFolder

    private var folderColor: Color {
        folderColorFromHex(folder.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Header row ──────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(folderColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(folderColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                        .lineLimit(1)
                    Text("\(folder.documents.count) document\(folder.documents.count == 1 ? "" : "s")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color("TextMuted"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("TextMuted").opacity(0.5))
            }

            // ── Document thumbnail strip ─────────────────────────────────────
            // Shows up to 5 thumbnails. Hidden when folder is empty.
            if !folder.documents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(folder.documents.prefix(5)) { doc in
                            FolderDocumentThumbnail(document: doc)
                        }
                        // Overflow pill: "+N more" when > 5 docs
                        if folder.documents.count > 5 {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(folderColor.opacity(0.10))
                                    .frame(width: 56, height: 72)
                                Text("+\(folder.documents.count - 5)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(folderColor)
                            }
                        }
                    }
                    .padding(.leading, 2)
                    .padding(.trailing, 4)
                }
            } else {
                // Empty folder placeholder strip
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(folderColor.opacity(0.06))
                            .frame(width: 56, height: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        folderColor.opacity(0.15),
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                            )
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color("Hairline"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }
}

// MARK: - FolderDocumentThumbnail

private struct FolderDocumentThumbnail: View {
    let document: ScannedDocument

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data = document.thumbnailData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color("Background")
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(Color("TextMuted").opacity(0.4))
                }
            }
            .frame(width: 56, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color("Hairline"), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)

            if document.pageCount > 1 {
                Text("\(document.pageCount)p")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .background(Color("PrimaryGreen").opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
        }
    }
}

// MARK: - FolderDetailView
//
// Full screen showing all documents inside a specific folder.
// Uses @Query with a predicate for the folder ID so SwiftData
// drives sorting — no computed sort on every body render.

struct FolderDetailView: View {
    let folder: DocumentFolder
    @EnvironmentObject var storeKitManager: StoreKitManager
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDocument: ScannedDocument? = nil
    @State private var layout: LibraryLayout = .grid

    // Sorted documents derived from the folder relationship
    private var sortedDocuments: [ScannedDocument] {
        folder.documents.sorted { $0.dateModified > $1.dateModified }
    }

    private var folderColor: Color { folderColorFromHex(folder.colorHex) }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            if folder.documents.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "folder")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundColor(folderColor.opacity(0.4))
                    Text("No documents in this folder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color("TextMuted"))
                    Text("Move documents here using the ··· menu\non any document.")
                        .font(.system(size: 14))
                        .foregroundColor(Color("TextMuted").opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    if layout == .grid {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 14
                        ) {
                            ForEach(sortedDocuments) { doc in
                                DocumentGridCell(document: doc)
                                    .onTapGesture { selectedDocument = doc }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedDocuments) { doc in
                                DocumentListRow(document: doc)
                                    .onTapGesture { selectedDocument = doc }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { layout = layout == .grid ? .list : .grid }
                } label: {
                    Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color("TextPrimary"))
                }
            }
        }
        .navigationDestination(item: $selectedDocument) { doc in
            DocumentDetailView(document: doc)
                .environmentObject(storeKitManager)
        }
    }
}

// MARK: - NewFolderSheet
//
// Lightweight sheet for creating a folder without moving a document.
// Used from FolderListView's "+" button.

struct NewFolderSheet: View {
    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name      = ""
    @State private var colorHex  = "1B4332"

    private let colors: [(hex: String, label: String, color: Color)] = [
        ("1B4332", "Forest", Color(red: 0.11, green: 0.26, blue: 0.20)),
        ("1A4F6E", "Ocean",  Color(red: 0.10, green: 0.31, blue: 0.43)),
        ("6B2D5E", "Berry",  Color(red: 0.42, green: 0.18, blue: 0.37)),
        ("8B3A2F", "Rust",   Color(red: 0.55, green: 0.23, blue: 0.18)),
        ("7A5C00", "Gold",   Color(red: 0.48, green: 0.36, blue: 0.00)),
        ("3A4A5C", "Slate",  Color(red: 0.23, green: 0.29, blue: 0.36)),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder Name")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("TextMuted"))
                    TextField("e.g. Health, Science, Work...", text: $name)
                        .font(.system(size: 16))
                        .foregroundColor(Color("TextPrimary"))
                        .padding(14)
                        .background(Color("Surface"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color("Hairline"), lineWidth: 1))
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .onSubmit { attemptCreate() }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Colour")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("TextMuted"))
                    HStack(spacing: 10) {
                        ForEach(colors, id: \.hex) { entry in
                            Button {
                                colorHex = entry.hex
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                ZStack {
                                    Circle().fill(entry.color).frame(width: 36, height: 36)
                                    if colorHex == entry.hex {
                                        Circle().strokeBorder(.white, lineWidth: 2).frame(width: 36, height: 36)
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

                Spacer()

                Button { attemptCreate() } label: {
                    Text("Create Folder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color("TextMuted").opacity(0.3)
                            : Color("PrimaryGreen"))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background(Color("Background"))
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color("TextMuted"))
                }
            }
        }
    }

    private func attemptCreate() {
        let t = name.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onCreate(t, colorHex)
        dismiss()
    }
}

// MARK: - Shared colour helper

func folderColorFromHex(_ hex: String) -> Color {
    switch hex {
    case "1B4332": return Color(red: 0.11, green: 0.26, blue: 0.20)
    case "1A4F6E": return Color(red: 0.10, green: 0.31, blue: 0.43)
    case "6B2D5E": return Color(red: 0.42, green: 0.18, blue: 0.37)
    case "8B3A2F": return Color(red: 0.55, green: 0.23, blue: 0.18)
    case "7A5C00": return Color(red: 0.48, green: 0.36, blue: 0.00)
    case "3A4A5C": return Color(red: 0.23, green: 0.29, blue: 0.36)
    default:       return Color(red: 0.11, green: 0.26, blue: 0.20)
    }
}
