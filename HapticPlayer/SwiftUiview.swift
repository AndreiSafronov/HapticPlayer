//
//  SwiftUiview.swift
//  HapticPlayer
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit

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

    func resolveVideoURL() -> URL? {
        if let data = videoBookmark {
            var isStale = false
            return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
        } else if let path = videoPath, let url = URL(string: path) {
            return url
        }
        return nil
    }
    
    func resolveHapticURL() -> URL? {
        if let data = hapticBookmark {
            var isStale = false
            return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
        } else if let path = hapticPath, let url = URL(string: path) {
            return url
        }
        return nil
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

struct SyncedHapticVideoWrapper: UIViewControllerRepresentable {
    let clip: HapticClip

    func makeUIViewController(context: Context) -> SyncedHapticVideoViewController {
        let videoURL = clip.resolveVideoURL()
        let hapticURL = clip.resolveHapticURL()
        
        _ = videoURL?.startAccessingSecurityScopedResource()
        _ = hapticURL?.startAccessingSecurityScopedResource()
        
        return SyncedHapticVideoViewController(videoURL: clip.videoSource, haptic: clip.hapticSource)
    }

    func updateUIViewController(_ uiViewController: SyncedHapticVideoViewController, context: Context) {}
    
    static func dismantleUIViewController(_ uiViewController: SyncedHapticVideoViewController, coordinator: ()) {
        uiViewController.dismiss(animated: false)
    }
}

// MARK: - Main Glass Grid View

struct HapticClipGridView: View {
    @StateObject private var store = HapticStore()
    @State private var selectedClip: HapticClip?
    @State private var showAddSheet = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundCanvas()

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.clips) { clip in
                            Button {
                                selectedClip = clip
                            } label: {
                                VideoThumbnailCard(clip: clip)
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Haptic Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPairingSheet { newClip in
                    store.clips.append(newClip)
                }
            }
            .fullScreenCover(item: $selectedClip) { clip in
                SyncedHapticVideoWrapper(clip: clip)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Video Thumbnail Card (Liquid Glass)

private struct VideoThumbnailCard: View {
    let clip: HapticClip
    
    @State private var thumbnail: UIImage? = nil
    @State private var durationString: String = "--:--"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(
                        Group {
                            if let img = thumbnail {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                ProgressView().tint(.white.opacity(0.5))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                
                Text(durationString)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            Text(clip.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .task {
            await loadThumbnailData()
        }
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
                let mins = seconds / 60
                let secs = seconds % 60
                durationString = String(format: "%d:%02d", mins, secs)
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

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundCanvas()

                ScrollView {
                    VStack(spacing: 24) {
                        GlassTextField(placeholder: "Combo Name", text: $title)

                        VStack(spacing: 12) {
                            GlassFileButton(
                                title: videoURL == nil ? "Select Video File (.mp4 / .mov)" : videoURL!.lastPathComponent,
                                icon: "video.fill",
                                isSelected: videoURL != nil
                            ) { showVideoPicker = true }

                            GlassFileButton(
                                title: hapticURL == nil ? "Select Haptic Pattern (.ahap)" : hapticURL!.lastPathComponent,
                                icon: "waveform.path",
                                isSelected: hapticURL != nil
                            ) { showHapticPicker = true }
                        }

                        Button {
                            guard let video = videoURL, let haptic = hapticURL else { return }
                            
                            _ = video.startAccessingSecurityScopedResource()
                            _ = haptic.startAccessingSecurityScopedResource()
                            
                            let vData = try? video.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                            let hData = try? haptic.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                            
                            video.stopAccessingSecurityScopedResource()
                            haptic.stopAccessingSecurityScopedResource()
                            
                            let clip = HapticClip(
                                title: title,
                                subtitle: nil,
                                isBundled: false,
                                videoBookmark: vData,
                                hapticBookmark: hData
                            )
                            onSave(clip)
                            dismiss()
                        } label: {
                            Text("Save Combo")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(isValid ? .black : .white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(isValid ? Color.white : Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: isValid ? .white.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
                        }
                        .disabled(!isValid)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Combo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .fileImporter(isPresented: $showVideoPicker, allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie]) { result in
                if case .success(let url) = result {
                    videoURL = url
                    if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
                }
            }
            .fileImporter(isPresented: $showHapticPicker, allowedContentTypes: [UTType(filenameExtension: "ahap") ?? .json]) { result in
                if case .success(let url) = result { hapticURL = url }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reusable UI Components

private struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .foregroundStyle(.white)
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
                    .foregroundStyle(isSelected ? .green : .white.opacity(0.7))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isSelected ? .green : .white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isSelected ? Color.green.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct LiquidBackgroundCanvas: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.25)).frame(width: 280, height: 280).blur(radius: 80).offset(x: -100, y: -200)
            Circle().fill(Color.purple.opacity(0.2)).frame(width: 320, height: 320).blur(radius: 90).offset(x: 120, y: 150)
        }
    }
}
