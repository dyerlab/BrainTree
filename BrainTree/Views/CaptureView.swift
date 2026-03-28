import SwiftUI
import Speech
import AVFoundation

// MARK: - Speech Recognizer

@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var permissionDenied = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var silenceTimer: Timer?

    var onSilence: (() -> Void)?

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
#if os(iOS)
        let mic = await AVAudioApplication.requestRecordPermission()
#else
        let mic = true
#endif
        let granted = speech == .authorized && mic
        permissionDenied = !granted
        return granted
    }

    func start() {
        guard !isRecording else { return }
        recognizer = SFSpeechRecognizer(locale: .current)
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }
#endif

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch { return }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [self] in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
        isRecording = true
        transcript = ""
        resetSilenceTimer()
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
        isRecording = false
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.onSilence?()
            }
        }
    }
}

// MARK: - Capture View

struct CaptureView: View {
    @State private var recognizer = SpeechRecognizer()
    @State private var phase: Phase = .idle
    @State private var textInput = ""
    @State private var useText = false
    @State private var errorMessage: String?

    enum Phase { case idle, recording, confirming, submitting, done, error }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                switch phase {
                case .idle:      idleView
                case .recording: recordingView
                case .confirming: confirmingView
                case .submitting: submittingView
                case .done:      doneView
                case .error:     errorView
                }

                Spacer()
                Spacer()
            }
            .padding()
            .navigationTitle("Capture")
            .onChange(of: phase) { _, new in
                if new == .idle { recognizer.stop() }
            }
        }
    }

    // MARK: Phases

    private var idleView: some View {
        VStack(spacing: 24) {
            Button {
                Task { await startRecording() }
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Text("Tap to speak")
                .foregroundStyle(.secondary)

            Button("Type instead") { useText = true }
                .font(.callout)
        }
        .sheet(isPresented: $useText) {
            textEntrySheet
        }
    }

    private var recordingView: some View {
        VStack(spacing: 20) {
            Button {
                recognizer.stop()
                phase = recognizer.transcript.isEmpty ? .idle : .confirming
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            .buttonStyle(.plain)

            Text(recognizer.transcript.isEmpty ? "Listening…" : recognizer.transcript)
                .multilineTextAlignment(.center)
                .foregroundStyle(recognizer.transcript.isEmpty ? .secondary : .primary)
                .animation(.easeInOut, value: recognizer.transcript)
        }
    }

    private var confirmingView: some View {
        VStack(spacing: 24) {
            Text(recognizer.transcript)
                .multilineTextAlignment(.center)
                .font(.body)

            HStack(spacing: 20) {
                Button("Discard") { phase = .idle }
                    .buttonStyle(.bordered)
                Button("Submit") {
                    Task { await submit(recognizer.transcript) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var submittingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Capturing…").foregroundStyle(.secondary)
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Captured!")
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            phase = .idle
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text(errorMessage ?? "Something went wrong")
                .multilineTextAlignment(.center)
            Button("Try Again") { phase = .idle }
                .buttonStyle(.borderedProminent)
        }
    }

    private var textEntrySheet: some View {
        NavigationStack {
            TextEditor(text: $textInput)
                .padding()
                .navigationTitle("New Thought")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { useText = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            useText = false
                            Task { await submit(textInput) }
                        }
                        .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }

    // MARK: Actions

    private func startRecording() async {
        let granted = await recognizer.requestPermissions()
        guard granted else {
            errorMessage = "Microphone or speech recognition permission denied. Enable in Settings."
            phase = .error
            return
        }
        recognizer.onSilence = {
            if !self.recognizer.transcript.isEmpty { self.phase = .confirming }
        }
        recognizer.start()
        phase = .recording
    }

    private func submit(_ text: String) async {
        phase = .submitting
        do {
            try await MCPClient.captureThought(text)
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
        }
    }
}
