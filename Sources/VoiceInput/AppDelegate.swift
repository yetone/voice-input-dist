import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let speechEngine = SpeechEngine()
    private let audioRecorder = AudioRecorder()
    private let textInjector = TextInjector()
    private lazy var overlayPanel = OverlayPanel()

    private var isEnabled = true
    private var isRecording = false
    private var lastPartialResult = ""
    private var finalResultTimer: Timer?
    private var asrModeMenuItem: NSMenuItem!

    private var enableMenuItem: NSMenuItem!
    private var llmMenuItem: NSMenuItem!
    private lazy var settingsWindow = SettingsWindow()
    private var languageItems: [NSMenuItem] = []
    private var selectedLocaleCode: String {
        get { UserDefaults.standard.string(forKey: "selectedLocaleCode") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLocaleCode") }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedCode = selectedLocaleCode
        if !savedCode.isEmpty {
            speechEngine.locale = Locale(identifier: savedCode)
        }

        setupStatusBar()
        setupSpeechCallbacks()

        SpeechEngine.requestPermissions { [weak self] granted, errorMsg in
            if !granted, let msg = errorMsg {
                self?.showAlert(title: "Permission Required", message: msg)
            }
        }

        if !keyMonitor.start() {
            showAccessibilityAlert()
        }

        keyMonitor.onFnDown = { [weak self] in self?.fnDown() }
        keyMonitor.onFnUp = { [weak self] in self?.fnUp() }
    }

    // MARK: - Key events

    private var useLLMASR: Bool {
        LLMASRClient.shared.isEnabled && LLMASRClient.shared.isConfigured
    }

    private func fnDown() {
        guard isEnabled, !isRecording else { return }
        LLMRefiner.shared.cancel()
        isRecording = true
        lastPartialResult = ""

        updateStatusIcon(recording: true)
        overlayPanel.show(text: "Listening...")
        NSSound(named: .init("Tink"))?.play()

        if useLLMASR {
            audioRecorder.startRecording()
        } else {
            speechEngine.startRecording()
        }
    }

    private func fnUp() {
        guard isRecording else { return }
        isRecording = false

        updateStatusIcon(recording: false)

        if useLLMASR {
            audioRecorder.stopRecording()
        } else {
            speechEngine.stopRecording()
            finalResultTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.finishTranscription()
            }
        }
    }

    // MARK: - Speech callbacks

    private func setupSpeechCallbacks() {
        speechEngine.onPartialResult = { [weak self] text in
            guard let self else { return }
            self.lastPartialResult = text
            self.overlayPanel.updateText(text)
        }

        speechEngine.onFinalResult = { [weak self] text in
            guard let self else { return }
            self.lastPartialResult = text
            self.finalResultTimer?.invalidate()
            self.finalResultTimer = nil
            self.finishTranscription()
        }

        speechEngine.onError = { [weak self] msg in
            guard let self else { return }
            self.overlayPanel.updateText("Error: \(msg)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.overlayPanel.dismiss()
            }
        }

        speechEngine.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }

        speechEngine.onLocaleUnavailable = { [weak self] msg in
            self?.showAlert(title: "Language Unavailable", message: msg)
        }

        // LLM ASR 回调
        audioRecorder.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }

        audioRecorder.onFinished = { [weak self] audioData in
            guard let self, let data = audioData else {
                self?.overlayPanel.updateText("录音失败")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.overlayPanel.dismiss()
                }
                return
            }

            self.overlayPanel.updateText("识别中...")
            LLMASRClient.shared.transcribe(audioData: data) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        self.lastPartialResult = text
                        self.finishTranscription()
                    case .failure(let error):
                        self.overlayPanel.updateText("ASR 失败: \(error.localizedDescription)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.overlayPanel.dismiss()
                        }
                    }
                }
            }
        }
    }

    private func finishTranscription() {
        finalResultTimer?.invalidate()
        finalResultTimer = nil

        let text = lastPartialResult.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            overlayPanel.dismiss()
            lastPartialResult = ""
            return
        }

        let refiner = LLMRefiner.shared
        if refiner.isEnabled && refiner.isConfigured {
            overlayPanel.showRefining()
            refiner.refine(text) { [weak self] result in
                guard let self else { return }
                let finalText: String
                switch result {
                case .success(let refined):
                    finalText = refined.isEmpty ? text : refined
                    let wasRefined = finalText != text
                    if wasRefined {
                        self.overlayPanel.updateText("✨ \(finalText)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.overlayPanel.dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.textInjector.inject(finalText)
                                NSSound(named: .init("Pop"))?.play()
                            }
                        }
                    } else {
                        self.overlayPanel.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.textInjector.inject(finalText)
                            NSSound(named: .init("Pop"))?.play()
                        }
                    }
                case .failure(let error):
                    NSLog("[LLMRefiner] Refine failed: %@", error.localizedDescription)
                    finalText = text
                    self.overlayPanel.updateText("Refine failed: \(error.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.overlayPanel.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.textInjector.inject(finalText)
                            NSSound(named: .init("Pop"))?.play()
                        }
                    }
                }
                self.lastPartialResult = ""
            }
        } else {
            overlayPanel.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.textInjector.inject(text)
                NSSound(named: .init("Pop"))?.play()
            }
            lastPartialResult = ""
        }
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(recording: false)

        let menu = NSMenu()

        enableMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        menu.addItem(.separator())

        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let languages: [(String, String)] = [
            ("System Default", ""),
            ("English (US)", "en-US"),
            ("中文 (简体)", "zh-CN"),
            ("中文 (繁體)", "zh-TW"),
            ("日本語", "ja-JP"),
            ("한국어", "ko-KR"),
        ]
        for (name, code) in languages {
            let item = NSMenuItem(title: name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == selectedLocaleCode ? .on : .off
            languageItems.append(item)
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // LLM Refinement submenu
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        llmMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleLLM), keyEquivalent: "")
        llmMenuItem.target = self
        llmMenuItem.state = LLMRefiner.shared.isEnabled ? .on : .off
        llmMenu.addItem(llmMenuItem)

        llmMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openLLMSettings), keyEquivalent: "")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        // ASR Provider submenu
        let asrItem = NSMenuItem(title: "ASR Provider", action: nil, keyEquivalent: "")
        let asrMenu = NSMenu()

        asrModeMenuItem = NSMenuItem(title: "Use LLM ASR", action: #selector(toggleASRMode), keyEquivalent: "")
        asrModeMenuItem.target = self
        asrModeMenuItem.state = LLMASRClient.shared.isEnabled ? .on : .off
        asrMenu.addItem(asrModeMenuItem)

        asrMenu.addItem(.separator())

        let asrSettingsItem = NSMenuItem(title: "ASR Settings...", action: #selector(openASRSettings), keyEquivalent: "")
        asrSettingsItem.target = self
        asrMenu.addItem(asrSettingsItem)

        asrItem.submenu = asrMenu
        menu.addItem(asrItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VoiceInput", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusIcon(recording: Bool) {
        guard let button = statusItem.button else { return }
        let name = recording ? "mic.fill" : "mic"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Voice Input")
        button.contentTintColor = recording ? .systemRed : nil
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        enableMenuItem.state = isEnabled ? .on : .off

        if isEnabled {
            if !keyMonitor.start() {
                showAccessibilityAlert()
            }
        } else {
            keyMonitor.stop()
            if isRecording {
                speechEngine.cancel()
                audioRecorder.cancel()
                overlayPanel.dismiss()
                isRecording = false
                updateStatusIcon(recording: false)
            }
        }
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        selectedLocaleCode = code
        speechEngine.locale = code.isEmpty ? .current : Locale(identifier: code)

        for item in languageItems {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }
    }

    @objc private func toggleLLM() {
        let refiner = LLMRefiner.shared
        refiner.isEnabled.toggle()
        llmMenuItem.state = refiner.isEnabled ? .on : .off
    }

    @objc private func openLLMSettings() {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleASRMode() {
        let client = LLMASRClient.shared
        client.isEnabled.toggle()
        asrModeMenuItem.state = client.isEnabled ? .on : .off
    }

    private lazy var asrSettingsWindow = ASRSettingsWindow()

    @objc private func openASRSettings() {
        asrSettingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            VoiceInput needs Accessibility permission to monitor the Fn key.

            1. Open System Settings → Privacy & Security → Accessibility
            2. Add and enable VoiceInput
            3. Restart the app
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
