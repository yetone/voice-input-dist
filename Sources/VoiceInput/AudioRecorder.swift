import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.yetone.VoiceInput", category: "AudioRecorder")

final class AudioRecorder {
    var onAudioLevel: ((Float) -> Void)?
    var onFinished: ((Data?) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var buffer: AVAudioPCMBuffer?
    private var fileURL: URL?

    func startRecording() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.onAudioLevel?(self.computeLevel(buffer))

            // 写入临时文件（避免内存暴涨）
            if let file = self.writeFile {
                try? file.write(from: buffer)
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("voice_input_\(UUID().uuidString).wav")
        self.fileURL = url
        self.writeFile = try? AVAudioFile(forWriting: url, settings: format.settings)

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            logger.error("AudioEngine failed: \(error.localizedDescription)")
            cleanup()
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        guard let url = fileURL else {
            onFinished?(nil)
            cleanup()
            return
        }

        // 在后台线程读取文件数据返回
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                self?.onFinished?(data)
                self?.cleanup()
            }
        }
    }

    func cancel() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        cleanup()
    }

    // MARK: - Private

    private var writeFile: AVAudioFile?

    private func cleanup() {
        writeFile = nil
        fileURL = nil
    }

    private func computeLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrtf(sum / Float(max(frameLength, 1)))
        let dB = 20 * log10(max(rms, 1e-6))
        return max(0, min(1, (dB + 50) / 40))
    }
}
