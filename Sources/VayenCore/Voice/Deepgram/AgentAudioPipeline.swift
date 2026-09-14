import AVFoundation

/// Microphone capture and agent-voice playback for a live voice session.
///
/// - Capture: inputNode tap -> AVAudioConverter -> linear16 mono at
///   `inputSampleRate`, delivered on a serial queue to `onAudio`.
/// - Playback: provider linear16 chunks at `outputSampleRate` -> converter ->
///   player node. `flushPlayback()` implements barge-in: queued buffers are
///   dropped the instant the provider reports `UserStartedSpeaking`.
///
/// Thread safety: tap and playback callbacks run on realtime/audio threads, so
/// all mutable state is guarded by a serial queue. The class is Sendable by
/// contract; do not touch `engine` off the queue except during setup.
public final class AgentAudioPipeline: @unchecked Sendable {

    public let inputSampleRate: Int
    public let outputSampleRate: Int

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "ai.vayen.audio-pipeline")

    private var captureConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    /// Format the player node emits; equals the mixer's output format so the
    /// connection needs no further conversion.
    private var playbackFormat: AVAudioFormat?
    private var capturing = false
    private var playing = false
    private var engineRunning = false
    private var configObserver: NSObjectProtocol?

    /// Mic input must be linear16 PCM at this rate for the provider.
    public init(inputSampleRate: Int = 16_000, outputSampleRate: Int = 24_000) {
        self.inputSampleRate = inputSampleRate
        self.outputSampleRate = outputSampleRate
    }

    // MARK: - Lifecycle

    /// Attach the player node and start the engine. Safe to call repeatedly.
    public func startEngine() throws {
        try queue.sync {
            if engineRunning { return }
            let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            playbackFormat = outputFormat
            if playerNode.engine == nil {
                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
            } else {
                engine.disconnectNodeOutput(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
            }
            try engine.start()
            engineRunning = true
            observeConfigChanges()
        }
    }

    /// Stop capture, playback, and the engine. Idempotent.
    public func shutdown() {
        queue.sync {
            stopCaptureLocked()
            stopPlaybackLocked()
            if engineRunning {
                engine.stop()
                engineRunning = false
            }
            if let configObserver {
                NotificationCenter.default.removeObserver(configObserver)
                self.configObserver = nil
            }
        }
    }

    // MARK: - Capture

    /// Begin microphone capture. `onAudio` receives linear16 mono chunks at
    /// `inputSampleRate` on a private queue; it must never block.
    public func startCapture(onAudio: @escaping @Sendable (Data) -> Void) throws {
        try queue.sync {
            if capturing { return }
            if !engineRunning { try engine.start(); engineRunning = true }

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(inputSampleRate),
                channels: 1,
                interleaved: true
            ) else {
                throw VoicePipelineError.badFormat
            }
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw VoicePipelineError.badConverter
            }
            captureConverter = converter

            // ~100 ms of hardware audio per tap.
            let tapFrames = AVAudioFrameCount((inputFormat.sampleRate) / 10)
            input.installTap(onBus: 0, bufferSize: tapFrames, format: inputFormat) { buffer, _ in
                guard let out = AgentAudioPipeline.convert(buffer, with: converter, to: targetFormat),
                      let data = AgentAudioPipeline.pcm16Data(out) else { return }
                onAudio(data)
            }
            capturing = true
        }
    }

    public func stopCapture() {
        queue.sync { stopCaptureLocked() }
    }

    private func stopCaptureLocked() {
        guard capturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        captureConverter = nil
        capturing = false
    }

    /// Current microphone level in 0...1 for the listening indicator, or nil
    /// when not capturing. Reads hardware metering implicitly via tap buffers.
    public var isCapturing: Bool {
        queue.sync { capturing }
    }

    // MARK: - Playback

    /// Queue one provider audio chunk (linear16 mono at `outputSampleRate`).
    public func play(_ data: Data) {
        queue.sync {
            guard engineRunning, let outFormat = playbackFormat else { return }
            guard let inFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(outputSampleRate),
                channels: 1,
                interleaved: true
            ) else { return }

            let frameCount = AVAudioFrameCount(data.count / 2)
            guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount) else { return }
            inBuffer.frameLength = frameCount
            data.withUnsafeBytes { src in
                guard let base = src.baseAddress, let dst = inBuffer.int16ChannelData else { return }
                memcpy(dst[0], base, min(data.count, Int(inBuffer.frameCapacity) * MemoryLayout<Int16>.size))
            }

            if playbackConverter == nil || playbackConverter?.outputFormat != outFormat {
                playbackConverter = AVAudioConverter(from: inFormat, to: outFormat)
            }
            guard let converter = playbackConverter,
                  let outBuffer = AgentAudioPipeline.convert(inBuffer, with: converter, to: outFormat)
            else { return }

            if !playing {
                playerNode.play()
                playing = true
            }
            playerNode.scheduleBuffer(outBuffer)
        }
    }

    /// Drop all queued agent audio immediately (barge-in).
    public func flushPlayback() {
        queue.sync {
            if playing {
                playerNode.stop()
                playing = false
            }
        }
    }

    /// Stop playback without tearing down the engine.
    public func stopPlayback() {
        queue.sync { stopPlaybackLocked() }
    }

    private func stopPlaybackLocked() {
        if playing {
            playerNode.stop()
            playing = false
        }
    }

    // MARK: - Device changes

    private func observeConfigChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigChange()
        }
    }

    private func handleConfigChange() {
        // Output route changed (e.g. Bluetooth). Reconnect the player node at
        // the new output format and drop the stale converter.
        queue.sync {
            playbackConverter = nil
            let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            playbackFormat = outputFormat
            if playerNode.engine != nil {
                engine.disconnectNodeOutput(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
            }
        }
    }

    // MARK: - Conversion helpers

    /// AVAudioPCMBuffer is not Sendable and the input closure mutates captured
    /// state, but AVAudioConverter invokes the block synchronously on the
    /// calling thread, so boxing both is safe.
    private final class ConvertState: @unchecked Sendable {
        var input: AVAudioPCMBuffer
        var consumed = false
        init(input: AVAudioPCMBuffer) { self.input = input }
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 256
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        let state = ConvertState(input: input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if state.consumed {
                status.pointee = .endOfStream
                return nil
            }
            state.consumed = true
            status.pointee = .haveData
            return state.input
        }
        if error != nil { return nil }
        return output
    }

    private static func pcm16Data(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channels = buffer.int16ChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        return Data(bytes: channels[0], count: frames * channelCount * MemoryLayout<Int16>.size)
    }
}

public enum VoicePipelineError: Error, Sendable {
    case badFormat
    case badConverter
    case microphoneDenied
}

/// Microphone permission. The app must carry NSMicrophoneUsageDescription.
public enum MicrophonePermission {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func request() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
