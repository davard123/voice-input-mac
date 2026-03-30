import Cocoa
import Speech
import AVFoundation
import Carbon.HIToolbox

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    var statusItem: NSStatusItem?
    var audioEngine: AVAudioEngine?
    var speechRecognizer: SFSpeechRecognizer?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    var isRecording = false
    var currentTranscription = ""
    
    var floatingWindow: NSWindow?
    var waveformBars: [NSView] = []
    
    var onTranscriptionUpdate: ((String) -> Void)?
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: ((String?) -> Void)?
    
    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSpeechRecognizer()
        setupStatusItem()
        setupFloatingWindow()
        startListeningForFnKey()
        
        print("✅ Voice Input started")
    }
    
    // MARK: - Setup
    func setupSpeechRecognizer() {
        let languageCode = UserDefaults.standard.string(forKey: "language") ?? "zh-CN"
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
            button.action = #selector(showMenu)
        }
    }
    
    func setupFloatingWindow() {
        let rect = NSRect(x: 0, y: 0, width: 400, height: 56)
        floatingWindow = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        floatingWindow?.level = .floating
        floatingWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floatingWindow?.isOpaque = false
        floatingWindow?.hasShadow = true
        floatingWindow?.backgroundColor = NSColor.clear
        floatingWindow?.alphaValue = 0
        
        // 创建毛玻璃效果
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 28
        visualEffectView.layer?.masksToBounds = true
        
        // 波形容器
        let waveformContainer = NSView(frame: NSRect(x: 8, y: 12, width: 44, height: 32))
        
        // 创建 5 个波形条
        let barWidth: CGFloat = 6
        let spacing: CGFloat = 4
        let totalWidth = CGFloat(5) * barWidth + CGFloat(4) * spacing
        let startX = (waveformContainer.frame.width - totalWidth) / 2
        
        for i in 0..<5 {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.white.cgColor
            bar.layer?.cornerRadius = barWidth / 2
            bar.layer?.anchorPoint = CGPoint(x: 0.5, y: 0)
            
            let x = startX + CGFloat(i) * (barWidth + spacing)
            bar.frame = NSRect(x: x, y: 0, width: barWidth, height: waveformContainer.frame.height)
            bar.layer?.transform = CATransform3DMakeScale(1.0, 0.2, 1.0)
            
            waveformContainer.addSubview(bar)
            waveformBars.append(bar)
        }
        
        visualEffectView.addSubview(waveformContainer)
        
        // 文本标签
        let textView = NSTextField(labelWithString: "")
        textView.frame = NSRect(x: 60, y: 16, width: 300, height: 24)
        textView.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textView.textColor = NSColor.white
        textView.backgroundColor = NSColor.clear
        textView.isBezeled = false
        textView.isEditable = false
        textView.identifier = NSUserInterfaceItemIdentifier("textView")
        visualEffectView.addSubview(textView)
        
        floatingWindow?.contentView = visualEffectView
        
        // 居中显示
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = (screenFrame.width - rect.width) / 2 + screenFrame.origin.x
            let y = screenFrame.origin.y + 100
            floatingWindow?.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    // MARK: - Hot Key Listening
    func startListeningForFnKey() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, type, event, _) in
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 63 { // Fn key
                    if type == .keyDown {
                        DispatchQueue.main.async { self.startRecording() }
                        return nil // Suppress Fn key
                    } else if type == .keyUp {
                        DispatchQueue.main.async { self.stopRecording() }
                        return nil // Suppress Fn key
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    // MARK: - Recording
    func startRecording() {
        guard !isRecording else { return }
        guard let speechRecognizer = speechRecognizer else { return }
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus != .authorized {
                    print("❌ Speech recognition not authorized: \(authStatus)")
                    return
                }
                
                self.startRecordingInternal()
            }
        }
    }
    
    func startRecordingInternal() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.currentTranscription = result.bestTranscription.formattedString
                self.updateTextView(with: self.currentTranscription)
            }
            
            if error != nil || result?.isFinal == true {
                self.stopRecordingInternal()
                self.onRecordingStop?(self.currentTranscription)
            }
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine,
              let inputNode = audioEngine.inputNode as? AVAudioInputNode else { return }
        
        let audioFormat = inputNode.inputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { buffer, _ in
            recognitionRequest.append(buffer)
            self.updateAudioLevel(buffer: buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        isRecording = true
        currentTranscription = ""
        showFloatingWindow()
        onRecordingStart?()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        stopRecordingInternal()
    }
    
    func stopRecordingInternal() {
        isRecording = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        hideFloatingWindow()
    }
    
    // MARK: - UI Updates
    func showFloatingWindow() {
        floatingWindow?.alphaValue = 0
        floatingWindow?.setScale(0.9)
        floatingWindow?.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            floatingWindow?.animator().alphaValue = 1
            floatingWindow?.animator().setScale(1.0)
        }, completionHandler: nil)
    }
    
    func hideFloatingWindow() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            floatingWindow?.animator().alphaValue = 0
            floatingWindow?.animator().setScale(0.8)
        }, completionHandler: { [weak self] in
            self?.floatingWindow?.orderOut(nil)
        })
    }
    
    func updateTextView(with text: String) {
        guard let contentView = floatingWindow?.contentView else { return }
        if let textView = contentView.view(withIdentifier: NSUserInterfaceItemIdentifier("textView")) as? NSTextField {
            textView.stringValue = text
        }
    }
    
    func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        let channelData = buffer.floatChannelData?[0]
        let frameLength = Int(buffer.frameLength)
        
        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelData?[i] ?? 0.0
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        for (i, bar) in waveformBars.enumerated() {
            let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
            let jitter = Float.random(in: -0.04...0.04)
            var target = min(max(rms * weights[i] + jitter, 0.1), 1.0)
            
            let currentScale = bar.layer?.transform.m22 ?? 0.2
            let newScale: CGFloat = target > currentScale ?
                currentScale + CGFloat((target - Float(currentScale)) * 0.4) :
                currentScale - CGFloat((Float(currentScale) - target) * 0.15)
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.05)
            bar.layer?.transform = CATransform3DMakeScale(1.0, max(newScale, 0.1), 1.0)
            CATransaction.commit()
        }
    }
    
    // MARK: - Menu
    @objc func showMenu() {
        let menu = NSMenu()
        
        let languageMenu = NSMenu()
        let languages = [("zh-CN", "简体中文"), ("zh-TW", "繁體中文"), ("en-US", "English"), ("ja-JP", "日本語"), ("ko-KR", "한국어")]
        
        for (code, name) in languages {
            let item = NSMenuItem(title: name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.tag = code.hash
            item.state = (UserDefaults.standard.string(forKey: "language") == code) ? .on : .off
            languageMenu.addItem(item)
        }
        
        menu.addItem(NSMenuItem(title: "Language / 语言", action: nil, keyEquivalent: ""))
        menu.item(at: 0)?.submenu = languageMenu
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Voice Input", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc func changeLanguage(_ sender: NSMenuItem) {
        let languages = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
        let index = sender.tag % languages.count
        UserDefaults.standard.set(languages[index], forKey: "language")
        setupSpeechRecognizer()
    }
    
    @objc func quitApp() {
        stopRecording()
        NSApp.terminate(nil)
    }
}

// MARK: - Helper Extensions
extension NSWindow {
    func setScale(_ scale: CGFloat) {
        self.contentView?.setScale(scale)
    }
}
