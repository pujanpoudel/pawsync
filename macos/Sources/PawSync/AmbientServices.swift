import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit
import CoreMedia
import AudioToolbox

@MainActor final class WindowEdgeService: ObservableObject {
    @Published private(set) var authorized = AXIsProcessTrusted()
    func requestPermission() {
        // Only the explicit window traversal setting calls this prompt.
        authorized = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func focusedFrame() -> CGRect? {
        authorized = AXIsProcessTrusted()
        guard authorized, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success, let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let focused = unsafeBitCast(window, to: AXUIElement.self)
        var location: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &location) == .success,
              AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &size) == .success,
              let location, let size, CFGetTypeID(location) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(location, to: AXValue.self), .cgPoint, &point), AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: point.x, y: mainTop-point.y-dimensions.height, width: dimensions.width, height: dimensions.height)
    }
}

/// Stores energy and timing only. It has no audio-buffer ownership or persistence path.
struct AudioOnsetDetector {
    private(set) var lastSound = -Double.infinity
    private(set) var lastBeat = -Double.infinity
    private var previousEnergy = 0.0
    private(set) var beat = 0.5
    mutating func consume(energy: Double, at time: Double) -> Bool {
        guard energy.isFinite else { return false }
        if energy > 0.004 { lastSound = time }
        let onset = energy > 0.01 && energy > previousEnergy*1.45 && time-lastBeat > 0.25
        if onset { if lastBeat.isFinite { beat = max(0.33,min(1,beat*0.7+(time-lastBeat)*0.3)) }; lastBeat = time }
        previousEnergy = energy
        return onset
    }
    func isAudible(at time: Double) -> Bool { time-lastSound < 3 }
}

private final class AudioEnergyOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onEnergy: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    private var lastAnalysis = -Double.infinity
    func stream(_ stream: SCStream, didStopWithError error: Error) { onError?(error.localizedDescription) }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, buffer.isValid else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastAnalysis >= 0.2 else { return }; lastAnalysis = now
        guard let format = buffer.formatDescription, let description = CMAudioFormatDescriptionGetStreamBasicDescription(format),
              description.pointee.mFormatID == kAudioFormatLinearPCM, description.pointee.mBitsPerChannel == 32,
              description.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
        var block: CMBlockBuffer?
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(buffer, bufferListSizeNeededOut: nil, bufferListOut: &list, bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block)
        guard result == noErr, let data = list.mBuffers.mData else { return }
        let count = Int(list.mBuffers.mDataByteSize)/MemoryLayout<Float>.size
        guard count > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        var sum = 0.0, n = 0
        for i in stride(from: 0, to: count, by: max(1,count/512)) { let x = Double(samples[i]); if x.isFinite { sum += x*x; n += 1 } }
        if n > 0 { onEnergy?(sqrt(sum/Double(n)), now) }
        // Neither sample pointers nor buffers escape this callback. Only the scalar RMS does.
    }
}

@MainActor final class MusicReactionService: ObservableObject {
    @Published private(set) var status = "Music reactions are off."
    @Published private(set) var audible = false
    @Published private(set) var beat: TimeInterval = 0.5
    var onSignal: ((Bool, TimeInterval) -> Void)?
    private var stream: SCStream?
    private let output = AudioEnergyOutput()
    private let queue = DispatchQueue(label: "com.pawsync.audio.energy", qos: .utility)
    private var detector = AudioOnsetDetector()
    private var generation = 0
    private var timer: Timer?
    private var liteHandle: UnsafeMutableRawPointer?
    private typealias PlayingFunction = @convention(c) (DispatchQueue, @convention(block) (Bool) -> Void) -> Void
    private var liteQuery: PlayingFunction?
    init() {
        output.onEnergy = { [weak self] energy, now in Task { @MainActor in self?.receive(energy: energy, now: now) } }
        output.onError = { [weak self] message in Task { @MainActor in self?.status = "Music capture stopped: \(message)"; self?.stop() } }
    }
    func configure(enabled: Bool, lite: Bool, visible: Bool, requestPermission: Bool = false) async {
        generation += 1; let attempt = generation
        await stopCapture()
        guard enabled, visible, generation == attempt else { status = enabled ? "Music reactions pause while your pet is hidden or the display sleeps." : "Music reactions are off."; return }
        if lite {
            // Optional private-API fallback: playing boolean only, no track metadata.
            if liteHandle == nil { liteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) }
            if let handle = liteHandle, let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") { liteQuery = unsafeBitCast(symbol, to: PlayingFunction.self) }
            guard liteQuery != nil else { status = "Now Playing lite mode is unavailable on this macOS version."; return }
            status = "Now Playing lite mode: only supported players are detected."
            startTimer(lite: true); return
        }
        var permitted = CGPreflightScreenCaptureAccess()
        if !permitted, requestPermission { permitted = CGRequestScreenCaptureAccess() }
        guard permitted else { status = "Enable Screen & System Audio Recording for PawSync, then recheck. Audio is analyzed in memory and discarded."; return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard generation == attempt else { return }
            let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { throw PawError.message("No active display for audio capture.") }
            let config = SCStreamConfiguration(); config.capturesAudio = true; config.excludesCurrentProcessAudio = true
            config.sampleRate = 16000; config.channelCount = 1
            // SCStream requires a display filter. No screen output or recording output is attached.
            config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(seconds: 30, preferredTimescale: 1); config.queueDepth = 3
            let capture = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: output)
            try capture.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
            try await capture.startCapture()
            guard generation == attempt else { try? await capture.stopCapture(); return }
            stream = capture; status = "Listening for system sound. Audio is never saved or uploaded."
            startTimer(lite: false)
        } catch { status = "Could not start music reactions: \(error.localizedDescription)" }
    }
    private func receive(energy: Double, now: Double) {
        guard stream != nil else { return }
        _ = detector.consume(energy: energy, at: now); update(audible: detector.isAudible(at: now), beat: detector.beat)
    }
    private func update(audible value: Bool, beat timing: Double) {
        let changed = audible != value || abs(beat-timing) > 0.08
        audible = value; beat = timing
        if changed { onSignal?(value, timing) }
    }
    private func startTimer(lite: Bool) {
        timer = Timer.scheduledTimer(withTimeInterval: lite ? 2 : 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if lite { self.liteQuery?(DispatchQueue.main, { [weak self] value in Task { @MainActor in self?.update(audible: value, beat: 0.5) } }) }
                else { self.update(audible: self.detector.isAudible(at: ProcessInfo.processInfo.systemUptime), beat: self.detector.beat) }
            }
        }; timer?.tolerance = lite ? 0.3 : 0.1
    }
    private func stopCapture() async {
        timer?.invalidate(); timer = nil; liteQuery = nil
        let old = stream; stream = nil; if let old { try? await old.stopCapture() }
        detector = AudioOnsetDetector(); update(audible: false, beat: 0.5)
    }
    func stop() { generation += 1; Task { await stopCapture() } }
}
