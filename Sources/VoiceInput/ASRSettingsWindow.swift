import AppKit

final class ASRSettingsWindow: NSPanel {
    private let apiBaseURLField = NSTextField()
    private let apiKeyField = NSTextField()
    private let modelField = NSTextField()
    private let languageField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "LLM ASR Settings"
        isReleasedWhenClosed = false
        setupUI()
        loadSettings()
        center()
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        apiBaseURLField.placeholderString = "https://openrouter.ai/api/v1"
        apiKeyField.placeholderString = "sk-or-v1-..."
        modelField.placeholderString = "openai/whisper-large-v3-turbo"
        languageField.placeholderString = "zh"

        let labels = ["API Base URL:", "API Key:", "Model:", "Language:"].map { text -> NSTextField in
            let label = NSTextField(labelWithString: text)
            label.alignment = .right
            return label
        }

        let grid = NSGridView(views: [
            [labels[0], apiBaseURLField],
            [labels[1], apiKeyField],
            [labels[2], modelField],
            [labels[3], languageField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 12
        grid.columnSpacing = 8

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let testButton = NSButton(title: "Test", target: self, action: #selector(test))
        testButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [statusLabel, testButton, saveButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        cv.addSubview(grid)
        cv.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            apiBaseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            modelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            languageField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 20),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
        ])

        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func loadSettings() {
        let client = LLMASRClient.shared
        apiBaseURLField.stringValue = client.apiBaseURL
        apiKeyField.stringValue = client.apiKey
        modelField.stringValue = client.model
        languageField.stringValue = client.language
    }

    @objc private func test() {
        applyFields()

        let client = LLMASRClient.shared
        guard client.isConfigured else {
            showStatus("API key is empty", success: false)
            return
        }

        // 生成一个简短的静音 wav 作为测试（约 0.1 秒）
        guard let testAudio = generateTestWAV() else {
            showStatus("Failed to generate test audio", success: false)
            return
        }

        showStatus("Testing...", success: nil)

        client.transcribe(audioData: testAudio) { [weak self] result in
            switch result {
            case .success(let text):
                self?.showStatus("OK: \(text)", success: true)
            case .failure(let error):
                self?.showStatus(error.localizedDescription, success: false)
            }
        }
    }

    @objc private func save() {
        applyFields()
        let client = LLMASRClient.shared
        if client.isConfigured {
            client.isEnabled = true
        }
        close()
    }

    private func applyFields() {
        let client = LLMASRClient.shared
        client.apiBaseURL = apiBaseURLField.stringValue
        client.apiKey = apiKeyField.stringValue
        client.model = modelField.stringValue
        client.language = languageField.stringValue
    }

    private func showStatus(_ text: String, success: Bool?) {
        statusLabel.stringValue = text
        switch success {
        case .some(true):
            statusLabel.textColor = .systemGreen
        case .some(false):
            statusLabel.textColor = .systemRed
        case .none:
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    private func generateTestWAV() -> Data? {
        let sampleRate: Double = 16000
        let duration: Double = 0.1
        let channelCount: UInt32 = 1
        let bitDepth: UInt32 = 16
        let numSamples = Int(sampleRate * duration)

        var wavData = Data()

        // PCM data (silent)
        let pcmSize = numSamples * 2
        let dataSize = pcmSize

        // RIFF header
        let fileSize = 36 + dataSize
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM format
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channelCount).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = UInt32(sampleRate) * channelCount * bitDepth / 8
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channelCount * bitDepth / 8).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(bitDepth).littleEndian) { Array($0) })

        // data chunk
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        wavData.append(contentsOf: [UInt8](repeating: 0, count: pcmSize))

        return wavData
    }
}
