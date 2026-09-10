//
//  SwiftUiview.swift
//  HapticPlayer
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit
import UIKit

// MARK: - Persistence Store

class HapticStore: ObservableObject {
    @Published var clips: [HapticClip] = [] {
        didSet { save() }
    }

    init() { load() }

    private let saveKey = "SavedHapticClips"

    private func save() {
        if let data = try? JSONEncoder().encode(clips) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([HapticClip].self, from: data) {
            self.clips = decoded
        }
    }
}

// MARK: - Imported file store (survives relaunch)

enum ImportedFileStore {
    static var directory: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func ingest(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let dest = directory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
}

// MARK: - Models

struct HapticClip: Identifiable, Codable {
    var id = UUID()
    let title: String
    let subtitle: String?
    let isBundled: Bool

    var videoPath: String?
    var hapticPath: String?
    var videoBookmark: Data?
    var hapticBookmark: Data?

    func resolveVideoURL() -> URL? { Self.resolve(bookmark: videoBookmark, path: videoPath) }
    func resolveHapticURL() -> URL? { Self.resolve(bookmark: hapticBookmark, path: hapticPath) }

    private static func resolve(bookmark: Data?, path: String?) -> URL? {
        if let data = bookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) {
                return url
            }
        }
        guard let path, !path.isEmpty else { return nil }
        if path.contains("://"), let url = URL(string: path) { return url }
        return URL(fileURLWithPath: path)
    }

    var videoSource: SyncedHapticVideoViewController.HapticSource {
        if isBundled, let path = videoPath { return .bundled(name: path) }
        if let url = resolveVideoURL() { return .remoteURL(url) }
        return .bundled(name: videoPath ?? "")
    }

    var hapticSource: SyncedHapticVideoViewController.HapticSource {
        if isBundled, let path = hapticPath { return .bundled(name: path) }
        if let url = resolveHapticURL() { return .remoteURL(url) }
        return .bundled(name: hapticPath ?? "")
    }
}

// MARK: - UIKit Wrapper

struct SyncedHapticVideoRepresentable: UIViewControllerRepresentable {
    let clip: HapticClip

    func makeUIViewController(context: Context) -> SyncedHapticVideoViewController {
        let videoURL = clip.resolveVideoURL()
        let hapticURL = clip.resolveHapticURL()

        _ = videoURL?.startAccessingSecurityScopedResource()
        _ = hapticURL?.startAccessingSecurityScopedResource()

        return SyncedHapticVideoViewController(videoURL: clip.videoSource, haptic: clip.hapticSource)
    }

    func updateUIViewController(_ uiViewController: SyncedHapticVideoViewController, context: Context) {}
}

struct SyncedHapticVideoWrapper: View {
    let clip: HapticClip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            SyncedHapticVideoRepresentable(clip: clip)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .liquidGlass(in: Circle())
            .padding(.leading, 16)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Main Glass Grid View

struct HapticClipGridView: View {
    @StateObject private var store = HapticStore()
    @State private var selectedClip: HapticClip?
    @State private var showAddSheet = false
    @Namespace private var glassNS

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundCanvas()

                ScrollView(showsIndicators: false) {
                    if store.clips.isEmpty {
                        emptyState
                            .padding(.top, 72)
                            .padding(.horizontal, 28)
                    } else {
                        LiquidGlassContainer(spacing: 20) {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(store.clips) { clip in
                                    Button {
                                        selectedClip = clip
                                    } label: {
                                        VideoThumbnailCard(clip: clip)
                                    }
                                    .buttonStyle(.plain)
                                    .liquidGlassID(clip.id, in: glassNS)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Haptic Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(in: Circle())
                    .accessibilityLabel("New combo")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPairingSheet { newClip in
                    store.clips.append(newClip)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationBackground(.clear)
            }
            .fullScreenCover(item: $selectedClip) { clip in
                SyncedHapticVideoWrapper(clip: clip)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
            Text("No combos yet")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("Tap + to pair a video with an AHAP haptic.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), interactive: false)
    }
}

// MARK: - Video Thumbnail Card

private struct VideoThumbnailCard: View {
    let clip: HapticClip

    @State private var thumbnail: UIImage? = nil
    @State private var durationString: String = "--:--"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        if let img = thumbnail {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(durationString)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 7, style: .continuous), interactive: false)
                    .padding(8)
            }

            Text(clip.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
        }
        .padding(8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task { await loadThumbnailData() }
    }

    private func loadThumbnailData() async {
        guard let url = clip.resolveVideoURL() else { return }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = Int(CMTimeGetSeconds(duration))
            if seconds > 0 {
                durationString = String(format: "%d:%02d", seconds / 60, seconds % 60)
            } else {
                durationString = "0:00"
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)

            let cgImage = try await generator.image(at: .zero).image
            await MainActor.run {
                self.thumbnail = UIImage(cgImage: cgImage)
            }
        } catch {
            print("Thumbnail load failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Add Pairing Modal Sheet

private struct AddPairingSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var videoURL: URL?
    @State private var hapticURL: URL?

    @State private var showVideoPicker = false
    @State private var showHapticPicker = false

    var onSave: (HapticClip) -> Void

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && videoURL != nil && hapticURL != nil
    }

    private static let videoTypes: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie, .video]
    private static var hapticTypes: [UTType] {
        var types: [UTType] = []
        if let ahap = UTType(filenameExtension: "ahap") { types.append(ahap) }
        if let imported = UTType("com.apple.haptics.ahap") { types.append(imported) }
        types.append(.json)
        types.append(.data)
        return types
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundCanvas()

                ScrollView {
                    VStack(spacing: 22) {
                        GlassTextField(placeholder: "Combo Name", text: $title)

                        VStack(spacing: 12) {
                            GlassFileButton(
                                title: videoURL == nil ? "Select Video File (.mp4 / .mov)" : videoURL!.lastPathComponent,
                                icon: "video.fill",
                                isSelected: videoURL != nil
                            ) {
                                showHapticPicker = false
                                showVideoPicker = true
                            }

                            GlassFileButton(
                                title: hapticURL == nil ? "Select Haptic Pattern (.ahap)" : hapticURL!.lastPathComponent,
                                icon: "waveform.path",
                                isSelected: hapticURL != nil
                            ) {
                                showVideoPicker = false
                                showHapticPicker = true
                            }
                        }

                        Button {
                            guard let video = videoURL, let haptic = hapticURL else { return }
                            let clip = HapticClip(
                                title: title.trimmingCharacters(in: .whitespaces),
                                subtitle: nil,
                                isBundled: false,
                                videoPath: video.path,
                                hapticPath: haptic.path
                            )
                            onSave(clip)
                            dismiss()
                        } label: {
                            Text("Save Combo")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(isValid ? .black : .white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                            interactive: isValid,
                            prominent: isValid
                        )
                        .disabled(!isValid)
                        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isValid)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Combo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .background {
                DocumentPickerLauncher(isPresented: $showVideoPicker, types: Self.videoTypes) { url in
                    ingest(url, video: true)
                }
                DocumentPickerLauncher(isPresented: $showHapticPicker, types: Self.hapticTypes) { url in
                    ingest(url, video: false)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func ingest(_ url: URL, video: Bool) {
        do {
            let dest = try ImportedFileStore.ingest(url)
            if video {
                videoURL = dest
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = url.deletingPathExtension().lastPathComponent
                }
            } else {
                hapticURL = dest
            }
        } catch {
            print("Ingest failed: \(error)")
            if video { videoURL = url } else { hapticURL = url }
        }
    }
}

// MARK: - UIKit document picker (works inside a sheet)

private struct DocumentPickerLauncher: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var types: [UTType]
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.types = types
        context.coordinator.onPick = onPick
        context.coordinator.isPresented = $isPresented
        context.coordinator.sync()
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let host = UIViewController()
        var types: [UTType] = []
        var onPick: ((URL) -> Void)?
        var isPresented: Binding<Bool> = .constant(false)
        private var presenting = false

        func sync() {
            if isPresented.wrappedValue {
                presentIfNeeded()
            } else if presenting {
                presenting = false
                host.presentedViewController?.dismiss(animated: true)
            }
        }

        private func presentIfNeeded() {
            guard !presenting else { return }

            let present = { [weak self] in
                guard let self, self.isPresented.wrappedValue, !self.presenting else { return }
                guard let presenter = self.topViewController() else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.presentIfNeeded() }
                    return
                }
                self.presenting = true
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: self.types, asCopy: true)
                picker.delegate = self
                picker.allowsMultipleSelection = false
                picker.shouldShowFileExtensions = true
                presenter.present(picker, animated: true)
            }

            if host.view.window == nil {
                DispatchQueue.main.async(execute: present)
            } else {
                present()
            }
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
                ?? scenes.flatMap(\.windows).first
            var vc = window?.rootViewController
            while let presented = vc?.presentedViewController {
                vc = presented
            }
            return vc
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            presenting = false
            isPresented.wrappedValue = false
            if let url = urls.first {
                onPick?(url)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            presenting = false
            isPresented.wrappedValue = false
        }
    }
}

// MARK: - Reusable UI

private struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .foregroundStyle(.white)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
    }
}

private struct GlassFileButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.green : Color.white.opacity(0.75))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isSelected ? Color.green : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: isSelected ? Color.green.opacity(0.35) : nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isSelected)
    }
}

private struct LiquidBackgroundCanvas: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Color.black
                Circle()
                    .fill(Color.blue.opacity(0.32))
                    .frame(width: 300, height: 300)
                    .blur(radius: 82)
                    .offset(x: -110 + sin(t * 0.42) * 46, y: -210 + cos(t * 0.31) * 36)
                Circle()
                    .fill(Color.purple.opacity(0.28))
                    .frame(width: 340, height: 340)
                    .blur(radius: 92)
                    .offset(x: 120 + cos(t * 0.36) * 52, y: 160 + sin(t * 0.47) * 44)
                Circle()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(width: 240, height: 240)
                    .blur(radius: 74)
                    .offset(x: 16 + sin(t * 0.27) * 58, y: 70 + cos(t * 0.51) * 48)
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 60)
                    .offset(x: -40 + cos(t * 0.22) * 30, y: 260 + sin(t * 0.33) * 24)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Native Liquid Glass

private struct LiquidGlassContainer<Content: View>: View {

    var spacing: CGFloat = 20

    @ViewBuilder
    var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}


// MARK: - Liquid Glass Modifiers

private extension View {

    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        interactive: Bool = true,
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {

        var glass: Glass = .regular

        if prominent {
            glass = .regular.tint(.white)
        }

        if let tint {
            glass = glass.tint(tint)
        }

        if interactive {
            glass = glass.interactive()
        }

        self
            .glassEffect(
                glass,
                in: shape
            )
    }


    @ViewBuilder
    func liquidGlassID<ID: Hashable>(
        _ id: ID,
        in namespace: Namespace.ID
    ) -> some View {

        self
            .glassEffectID(
                id,
                in: namespace
            )
    }
}