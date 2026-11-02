import AVFoundation
import Flutter
import Foundation
import Speech

/// One-shot dictation for the text box of the assistant. The Dart side is lib/network/native_bridges.dart (SpeechBridge).
/// It listens once and hands back what it understood; it never sends anything anywhere and never starts a movement.
/// With `onDeviceOnly` the audio is recognised on the iPhone and never leaves it: a language that has no recognizer on the
/// device answers `needsOnline` and nothing is listened to (the person decides in the settings whether Apple's online
/// recognition may be used).
final class SpeechChannel {
  static let shared = SpeechChannel()

  private let engine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var pending: FlutterResult?
  private var best = ""
  private var timeoutTimer: Timer?
  private var silenceTimer: Timer?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "hydra_umc/speech", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "listen":
        guard let args = call.arguments as? [String: Any] else {
          result(["status": "failed", "text": ""])
          return
        }
        shared.listen(
          languageTag: args["language"] as? String ?? "en-US",
          onDeviceOnly: args["onDeviceOnly"] as? Bool ?? true,
          timeoutMs: args["timeoutMs"] as? Int ?? 15000,
          result: result
        )
      case "cancel":
        shared.finish(status: nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func listen(languageTag: String, onDeviceOnly: Bool, timeoutMs: Int, result: @escaping FlutterResult) {
    if pending != nil { finish(status: nil) }
    SFSpeechRecognizer.requestAuthorization { speechStatus in
      guard speechStatus == .authorized else {
        DispatchQueue.main.async { result(["status": "denied", "text": ""]) }
        return
      }
      AVAudioSession.sharedInstance().requestRecordPermission { micAllowed in
        DispatchQueue.main.async {
          guard micAllowed else {
            result(["status": "denied", "text": ""])
            return
          }
          self.start(languageTag: languageTag, onDeviceOnly: onDeviceOnly, timeoutMs: timeoutMs, result: result)
        }
      }
    }
  }

  private func start(languageTag: String, onDeviceOnly: Bool, timeoutMs: Int, result: @escaping FlutterResult) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageTag)), recognizer.isAvailable else {
      result(["status": "unavailable", "text": ""])
      return
    }
    if onDeviceOnly && !recognizer.supportsOnDeviceRecognition {
      result(["status": "needsOnline", "text": ""])
      return
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = onDeviceOnly
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let input = engine.inputNode
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
        request.append(buffer)
      }
      engine.prepare()
      try engine.start()
    } catch {
      result(["status": "failed", "text": ""])
      return
    }
    self.recognizer = recognizer
    self.request = request
    self.pending = result
    self.best = ""
    task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
      DispatchQueue.main.async {
        guard let self = self, self.pending != nil else { return }
        if let recognition = recognition {
          self.best = recognition.bestTranscription.formattedString
          if recognition.isFinal {
            self.finish(status: self.best.isEmpty ? "empty" : "ok")
            return
          }
          // The person stopped talking: a pause ends the dictation instead of waiting for the whole time.
          self.silenceTimer?.invalidate()
          self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            self.finish(status: self.best.isEmpty ? "empty" : "ok")
          }
        } else if error != nil {
          self.finish(status: self.best.isEmpty ? "failed" : "ok")
        }
      }
    }
    timeoutTimer = Timer.scheduledTimer(withTimeInterval: Double(timeoutMs) / 1000.0, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.finish(status: self.best.isEmpty ? "empty" : "ok")
    }
  }

  /// Ends the listening and answers the waiting call. `status` nil answers with whatever was understood (a cancel).
  func finish(status: String?) {
    timeoutTimer?.invalidate()
    silenceTimer?.invalidate()
    timeoutTimer = nil
    silenceTimer = nil
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    guard let reply = pending else { return }
    pending = nil
    let text = best
    reply(["status": status ?? (text.isEmpty ? "empty" : "ok"), "text": text])
  }
}
