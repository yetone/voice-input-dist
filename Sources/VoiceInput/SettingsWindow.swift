import AppKit

final class SettingsWindow: NSPanel {
    private let apiBaseURLField = NSTextField()
    private let apiKeyField = NSTextField()
    private let modelField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "LLM Refinement Settings"
        isReleasedWhenClosed = false
        level = .floating
        hidesOnDeactivate = false
        setupUI()
        loadSettings()
        center()
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        apiBaseURLField.placeholderString = "https://api.openai.com/v1"
        apiKeyField.placeholderString = "sk-..."
        modelField.placeholderString = "gpt-4o-mini"

        let labels = ["API Base URL:", "API Key:", "Model:"].map { text -> NSTextField in
            let label = NSTextField(labelWithString: text)
            label.alignment = .right
            return label
        }

        let grid = NSGridView(views: [
            [labels[0], apiBaseURLField],
            [labels[1], apiKeyField],
            [labels[2], modelField],
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

            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 20),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
        ])

        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func loadSettings() {
        let refiner = LLMRefiner.shared
        apiBaseURLField.stringValue = refiner.apiBaseURL
        apiKeyField.stringValue = refiner.apiKey
        modelField.stringValue = refiner.model
    }

    @objc private func test() {
        applyFields()

        let refiner = LLMRefiner.shared
        guard refiner.isConfigured else {
            showStatus("API key is empty", success: false)
            return
        }

        showStatus("Testing...", success: nil)

        refiner.refine("Hello, this is a test.", force: true) { [weak self] result in
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
        close()
    }

    private func applyFields() {
        let refiner = LLMRefiner.shared
        refiner.apiBaseURL = apiBaseURLField.stringValue
        refiner.apiKey = apiKeyField.stringValue
        refiner.model = modelField.stringValue
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
}
