//
//  SyncedHapticVideoViewController.swift
//  HapticPlayer
//
//  Created by Thomas Dye on 26/08/2025.
//

import UIKit
import AVKit
import CoreHaptics

final class SyncedHapticVideoViewController: UIViewController {

    enum HapticSource {
        case remoteURL(URL)
        case bundled(name: String) // resource name, with or without extension
    }

    // MARK: - Public API

    init(videoURL: HapticSource, haptic: HapticSource) {
        self.videoSource = videoURL
        self.hapticSource = haptic
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Private

    private let videoSource: HapticSource
    private let hapticSource: HapticSource

    private let avController = AVPlayerViewController()
    private var player: AVPlayer?
    private var timeObserver: Any?

    private var engine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var isPrepared = false
    private var hasStartedHaptics = false
    private var didTeardown = false

    private var kvoAdded_timeControlStatus = false

    private let repinInterval: Double = 0.3
    private var lastRepinAt: CFTimeInterval = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupHapticsEngine()
        setupVideo()
    }

    deinit { teardown() }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed { teardown() }
    }

    // MARK: - Setup

    private func setupVideo() {
        guard let url = resolveVideoURL() else {
            print("Video: failed to resolve URL")
            showCenteredMessage("Couldn’t load video")
            return
        }

        let player = AVPlayer(url: url)
        self.player = player

        avController.player = player
        avController.exitsFullScreenWhenPlaybackEnds = true
        avController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(avController)
        view.addSubview(avController.view)
        avController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            avController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            avController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            avController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            avController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options: [.new, .old], context: nil)
        kvoAdded_timeControlStatus = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeJumped),
            name: .AVPlayerItemTimeJumped,
            object: player.currentItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: player.currentItem
        )

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.periodicRepinIfNeeded()
        }

        player.currentItem?.preferredForwardBufferDuration = 1.5
        prepareHapticsPattern()
        player.play()
    }

    private func setupHapticsEngine() {
        guard supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.stoppedHandler = { reason in
                print("Haptics engine stopped: \(reason.rawValue)")
            }
            engine?.resetHandler = { [weak self] in
                DispatchQueue.main.async {
                    print("Haptics engine reset – rebuilding player")
                    self?.isPrepared = false
                    self?.hasStartedHaptics = false
                    self?.prepareHapticsPattern()
                }
            }
        } catch {
            print("Haptics engine init failed: \(error)")
            supportsHaptics = false
        }
    }

    private func resolveVideoURL() -> URL? {
        switch videoSource {
        case .bundled(let name):
            return Self.bundledURL(name: name, extensions: ["mov", "mp4", "m4v"])
        case .remoteURL(let url):
            return url
        }
    }

    private func resolveHapticURL() -> URL? {
        switch hapticSource {
        case .bundled(let name):
            return Self.bundledURL(name: name, extensions: ["ahap"])
        case .remoteURL(let url):
            return url
        }
    }

    private static func bundledURL(name: String, extensions: [String]) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let ns = trimmed as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? trimmed : ns.deletingPathExtension

        if !ext.isEmpty, let url = Bundle.main.url(forResource: base, withExtension: ext) {
            return url
        }

        for candidate in extensions {
            if let url = Bundle.main.url(forResource: base, withExtension: candidate) {
                return url
            }
        }

        return Bundle.main.url(forResource: trimmed, withExtension: nil)
    }

    private func prepareHapticsPattern() {
        guard supportsHaptics else { return }
        guard let url = resolveHapticURL() else {
            print("AHAP: missing file")
            return
        }

        do {
            try engine?.start()
            let pattern = try CHHapticPattern(contentsOf: url)
            hapticPlayer = try engine?.makeAdvancedPlayer(with: pattern)
            hasStartedHaptics = false
            isPrepared = true
            print("AHAP: prepared")

            if player?.timeControlStatus == .playing {
                repinHaptics(to: videoTimeSeconds())
            }
        } catch {
            print("AHAP: prepare error -> \(error)")
        }
    }

    // MARK: - Sync helpers

    private func videoTimeSeconds() -> Double {
        guard let item = player?.currentItem else { return 0 }
        let t = item.currentTime().seconds
        return t.isFinite ? t : 0
    }

    private func repinHaptics(to videoSeconds: Double) {
        guard supportsHaptics, let hp = hapticPlayer else { return }
        do {
            try engine?.start()
            try hp.seek(toOffset: videoSeconds)
            if !hasStartedHaptics {
                try hp.start(atTime: 0)
                hasStartedHaptics = true
            } else if player?.timeControlStatus == .playing {
                try hp.resume(atTime: 0)
            }
        } catch {
            print("Haptics repin error -> \(error)")
        }
    }

    private func periodicRepinIfNeeded() {
        guard supportsHaptics,
              player?.timeControlStatus == .playing,
              hapticPlayer != nil else { return }

        let now = CACurrentMediaTime()
        if now - lastRepinAt >= repinInterval {
            lastRepinAt = now
            repinHaptics(to: videoTimeSeconds())
        }
    }

    // MARK: - AVPlayer events

    @objc private func itemDidPlayToEnd() {
        stopHapticsAndResetFlag()
    }

    @objc private func timeJumped() {
        repinHaptics(to: videoTimeSeconds())
    }

    @objc private func playbackStalled() {
        guard let hp = hapticPlayer else { return }
        do { try hp.pause(atTime: 0) } catch { }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {

        if keyPath == #keyPath(AVPlayer.timeControlStatus) {
            switch player?.timeControlStatus {
            case .playing:
                repinHaptics(to: videoTimeSeconds())
            case .paused, .waitingToPlayAtSpecifiedRate:
                if let hp = hapticPlayer { try? hp.pause(atTime: 0) }
            default:
                break
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func stopHapticsAndResetFlag() {
        guard let hp = hapticPlayer else { return }
        do { try hp.stop(atTime: 0) } catch { }
        hasStartedHaptics = false
    }

    // MARK: - Teardown

    private func teardown() {
        guard !didTeardown else { return }
        didTeardown = true

        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        NotificationCenter.default.removeObserver(self)

        if kvoAdded_timeControlStatus, let player {
            player.removeObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus))
            kvoAdded_timeControlStatus = false
        }

        stopHapticsAndResetFlag()
        try? engine?.stop()
        engine = nil
        hapticPlayer = nil
        player?.pause()
        player = nil
    }

    private func showCenteredMessage(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}