import Flutter
import UIKit
import Speech

@available(iOS 10.0, *)
public class SwiftSpeechRecognitionPlugin: NSObject, FlutterPlugin, SFSpeechRecognizerDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "speech_recognition", binaryMessenger: registrar.messenger())
    let instance = SwiftSpeechRecognitionPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let speechRecognizerFr = SFSpeechRecognizer(locale: Locale(identifier: "fr_FR"))!
  private let speechRecognizerEn = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
  private let speechRecognizerRu = SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))!
  private let speechRecognizerIt = SFSpeechRecognizer(locale: Locale(identifier: "it_IT"))!
  private let speechRecognizerEs = SFSpeechRecognizer(locale: Locale(identifier: "es_ES"))!

  private var speechChannel: FlutterMethodChannel?

  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

  private var recognitionTask: SFSpeechRecognitionTask?

  private let audioEngine = AVAudioEngine()

  init(channel:FlutterMethodChannel){
    speechChannel = channel
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //result("iOS " + UIDevice.current.systemVersion)
    switch (call.method) {
    case "speech.activate":
      self.activateRecognition(result: result)
    case "speech.listen":
      self.startRecognition(lang: call.arguments as! String, result: result)
    case "speech.cancel":
      self.cancelRecognition(result: result)
    case "speech.stop":
      self.stopRecognition(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func activateRecognition(result: @escaping FlutterResult) {
    speechRecognizerFr.delegate = self
    speechRecognizerEn.delegate = self
    speechRecognizerRu.delegate = self
    speechRecognizerIt.delegate = self
    speechRecognizerEs.delegate = self

    SFSpeechRecognizer.requestAuthorization { authStatus in
      OperationQueue.main.addOperation {
        switch authStatus {
        case .authorized:
          result(true)
          self.speechChannel?.invokeMethod("speech.onCurrentLocale", arguments: "\(Locale.current.identifier)")

        case .denied:
          result(false)

        case .restricted:
          result(false)

        case .notDetermined:
          result(false)
        }
        print("SFSpeechRecognizer.requestAuthorization \(authStatus.rawValue)")
      }
    }
  }

  private func startRecognition(lang: String, result: FlutterResult) {
    print("startRecognition...")
    if audioEngine.isRunning {
      audioEngine.stop()
      recognitionRequest?.endAudio()
      result(false)
    } else {
      try! start(stringToLearn: lang)
      result(true)
    }
  }

  private func cancelRecognition(result: FlutterResult?) {
    if let recognitionTask = recognitionTask {
      recognitionTask.cancel()
      self.recognitionTask = nil
      if let r = result {
        r(false)
      }
    }
  }

  private func stopRecognition(result: FlutterResult) {
    if audioEngine.isRunning {
      audioEngine.stop()
      recognitionRequest?.endAudio()
    }
    result(false)
  }

  private func start(stringToLearn: String) throws {

    cancelRecognition(result: nil)

    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(AVAudioSessionCategoryRecord, mode: AVAudioSessionModeDefault)
    try audioSession.setActive(true, with: .notifyOthersOnDeactivation)

    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

    let inputNode = audioEngine.inputNode
    
    guard let recognitionRequest = recognitionRequest else {
      fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object")
    }

    recognitionRequest.shouldReportPartialResults = true

    let speechRecognizer = getRecognizer(lang: "en_US")

    recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
        var isFinal = false
        
        if let result = result {
            self?.speechChannel?.invokeMethod("speech.onSpeech", arguments: result.bestTranscription.formattedString)
            isFinal = result.isFinal
            if isFinal {
                if let transcription = result.transcriptions.first(where: { $0.formattedString == stringToLearn }) {
                    self?.invokeResult(with: transcription.formattedString, confidence: self?.calculateConfidence(for: transcription) ?? 0.0)
                } else {
                    self?.invokeResult(with: "", confidence: 0.0)
                }
            }
        } else {
            self?.invokeResult(with: "", confidence: 0.0)
        }
        
        if error != nil || isFinal {
            self?.audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            self?.recognitionRequest = nil
            self?.recognitionTask = nil
        }
    }
    
    let recognitionFormat = inputNode.outputFormat(forBus: 0)
      inputNode.installTap(onBus: 0, bufferSize: 1024, format: recognitionFormat) {
        (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
        self.recognitionRequest?.append(buffer)
    }
    
      audioEngine.prepare()
      try audioEngine.start()
    
      speechChannel!.invokeMethod("speech.onRecognitionStarted", arguments: nil)
    }
    
    private func calculateConfidence(for transcription: SFTranscription) -> Float {
        var confidence: Float = 0
        transcription.segments.forEach { (segment) in
            confidence += segment.confidence
        }
        let result = confidence / Float(transcription.segments.count)
        return result
    }
    
    private func invokeResult(with transcription: String, confidence: Float) {
        self.speechChannel!.invokeMethod("speech.onRecognitionComplete", arguments: transcription)
        self.speechChannel!.invokeMethod("speech.onConfidenceLevel", arguments: confidence)
    }

  private func getRecognizer(lang: String) -> Speech.SFSpeechRecognizer {
    switch (lang) {
    case "fr_FR":
      return speechRecognizerFr
    case "en_US":
      return speechRecognizerEn
    case "ru_RU":
      return speechRecognizerRu
    case "it_IT":
      return speechRecognizerIt
    case "es_ES":
        return speechRecognizerEs
    default:
      return speechRecognizerFr
    }
  }

  public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
    speechChannel?.invokeMethod("speech.onSpeechAvailability", arguments: available)
  }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
    return input as String
}
