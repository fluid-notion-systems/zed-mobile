# Voice Input Technologies Research

## Overview

This document explores voice input technologies suitable for the Zed Mobile application, focusing on real-time speech recognition for sending commands to the AI assistant. We evaluate platform-specific APIs, third-party services, and implementation strategies for optimal user experience.

## Voice Recognition Requirements

### Core Requirements
1. **Real-time Recognition**: Low latency for interactive experience
2. **Continuous Listening**: Support for long-form dictation
3. **Command Detection**: Identify specific commands vs. general text
4. **Multi-language Support**: At least English with expansion capability
5. **Offline Capability**: Basic functionality without internet
6. **Wake Word Detection**: "Hey Zed" activation
7. **Noise Cancellation**: Work in various environments

### Performance Targets
- **Latency**: < 300ms for command recognition
- **Accuracy**: > 95% for common developer terms
- **Battery Impact**: < 5% additional drain during active use
- **Memory Usage**: < 50MB additional RAM

## Platform-Specific Solutions

### iOS - Speech Framework

Apple's native speech recognition framework provides high-quality recognition with tight OS integration.

```swift
// iOS Speech Framework implementation
import Speech

class ZedSpeechRecognizer {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func startRecording() throws {
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create and configure request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false // Use server for better accuracy

        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.processTranscription(text, isFinal: result.isFinal)
            }
        }
    }
}
```

#### Pros
- **Native Integration**: Seamless iOS experience
- **Privacy**: On-device processing option
- **Languages**: 50+ languages supported
- **Free**: No API costs

#### Cons
- **iOS Only**: Platform-specific implementation
- **Limits**: 1-minute continuous recognition limit
- **Permissions**: Requires explicit user permission

### Android - SpeechRecognizer API

Android's built-in speech recognition powered by Google.

```kotlin
// Android SpeechRecognizer implementation
class ZedSpeechRecognizer(private val context: Context) {
    private var speechRecognizer: SpeechRecognizer? = null
    private var recognitionIntent: Intent? = null

    fun initialize() {
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)

        recognitionIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500)
        }

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onPartialResults(partialResults: Bundle) {
                val matches = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                matches?.firstOrNull()?.let { processPartialResult(it) }
            }

            override fun onResults(results: Bundle) {
                val matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                matches?.firstOrNull()?.let { processFinalResult(it) }
            }
        })
    }
}
```

#### Pros
- **Google Quality**: Excellent recognition accuracy
- **Free**: For on-device recognition
- **Continuous**: No hard time limits
- **Offline**: Downloadable language packs

#### Cons
- **Android Only**: Platform-specific
- **Google Dependency**: Requires Google Play Services
- **Privacy**: Data may be sent to Google servers

## Cross-Platform Solutions

### 1. Google Cloud Speech-to-Text

Enterprise-grade speech recognition service with extensive features.

```dart
// Flutter implementation with Google Cloud Speech
class GoogleCloudSpeech {
  final String apiKey;
  late speech.SpeechToText _speech;

  Future<void> initialize() async {
    final config = speech.RecognitionConfig(
      encoding: speech.AudioEncoding.LINEAR16,
      sampleRateHertz: 16000,
      languageCode: 'en-US',
      enableAutomaticPunctuation: true,
      model: 'latest_long', // Optimized for voice commands
      useEnhanced: true,
      metadata: speech.RecognitionMetadata(
        interactionType: speech.InteractionType.VOICE_COMMAND,
        industryNaicsCodeOfAudio: 541511, // Custom Computer Programming
      ),
    );
  }

  Stream<String> streamingRecognize() async* {
    final streamingConfig = speech.StreamingRecognitionConfig(
      config: config,
      interimResults: true,
      singleUtterance: false,
    );

    // Stream audio and yield results
    await for (final response in _speech.streamingRecognize(streamingConfig, audioStream)) {
      yield response.results.first.alternatives.first.transcript;
    }
  }
}
```

#### Pricing
- **Standard**: $0.006 per 15 seconds
- **Enhanced**: $0.009 per 15 seconds
- **Free Tier**: 60 minutes/month

### 2. Microsoft Azure Speech Services

Comprehensive speech services with custom model training.

```dart
// Azure Cognitive Services Speech SDK
class AzureSpeechService {
  late CognitiveServicesSpeechConfig config;
  late SpeechRecognizer recognizer;

  void initialize(String subscriptionKey, String region) {
    config = CognitiveServicesSpeechConfig(
      subscription: subscriptionKey,
      region: region,
    );

    // Enable custom wake word
    config.setProperty(
      PropertyId.SpeechServiceConnection_InitialSilenceTimeoutMs,
      "10000",
    );

    // Configure for developer terminology
    final phraseList = PhraseListGrammar.fromRecognizer(recognizer);
    phraseList.addPhrase("Zed");
    phraseList.addPhrase("grep");
    phraseList.addPhrase("regex");
    // Add more developer terms
  }
}
```

### 3. OpenAI Whisper

State-of-the-art open-source speech recognition.

```python
# Whisper API integration
import whisper
import numpy as np

class WhisperService:
    def __init__(self, model_size="base"):
        self.model = whisper.load_model(model_size)

    def transcribe_stream(self, audio_stream):
        # Process audio in chunks
        for audio_chunk in audio_stream:
            # Convert to proper format
            audio_data = np.frombuffer(audio_chunk, dtype=np.float32)

            # Transcribe with timestamps
            result = self.model.transcribe(
                audio_data,
                language="en",
                task="transcribe",
                initial_prompt="AI assistant commands for Zed editor"
            )

            yield result["text"]
```

#### Deployment Options
1. **Cloud API**: OpenAI's hosted service
2. **Self-hosted**: Run on your own servers
3. **On-device**: Whisper.cpp for mobile (experimental)

## Wake Word Detection

### Porcupine Wake Word Engine

Lightweight wake word detection for "Hey Zed" activation.

```dart
// Porcupine integration for Flutter
class WakeWordDetector {
  late Porcupine _porcupine;

  Future<void> initialize() async {
    _porcupine = await Porcupine.fromKeywordPaths(
      accessKey: 'YOUR_ACCESS_KEY',
      keywordPaths: ['assets/hey_zed.ppn'], // Custom wake word model
      sensitivities: [0.5],
    );
  }

  void processAudio(Int16List frame) {
    final keywordIndex = _porcupine.process(frame);
    if (keywordIndex >= 0) {
      // Wake word detected - activate full speech recognition
      onWakeWordDetected();
    }
  }
}
```

### Custom Wake Word Training
1. **Data Collection**: Record 500+ samples of "Hey Zed"
2. **Model Training**: Use Porcupine Console or similar
3. **Optimization**: Balance accuracy vs. false positives
4. **Testing**: Verify across accents and environments

## Command Grammar Design

### Structured Command Recognition

```dart
// Command grammar for better recognition
class ZedCommandGrammar {
  static const Map<String, RegExp> commandPatterns = {
    'search': RegExp(r'(search|find|look for|grep)\s+(.+)'),
    'navigate': RegExp(r'(go to|open|jump to)\s+(.+)'),
    'edit': RegExp(r'(change|modify|edit|update)\s+(.+)'),
    'create': RegExp(r'(create|new|add)\s+(file|function|class)\s+(.+)'),
    'ai_command': RegExp(r'(ask|tell)\s+(assistant|ai|copilot)\s+(.+)'),
  };

  static Command? parseTranscription(String text) {
    for (final entry in commandPatterns.entries) {
      final match = entry.value.firstMatch(text.toLowerCase());
      if (match != null) {
        return Command(
          type: entry.key,
          arguments: match.groups(List.generate(match.groupCount, (i) => i + 1)),
        );
      }
    }
    return null;
  }
}
```

### Natural Language Understanding

```dart
// NLU for complex commands
class CommandNLU {
  // Using a lightweight on-device NLU model
  late final IntentClassifier classifier;

  Future<IntentResult> processCommand(String text) async {
    // Tokenize and extract features
    final tokens = tokenize(text);
    final features = extractFeatures(tokens);

    // Classify intent
    final intent = await classifier.classify(features);

    // Extract entities
    final entities = await extractEntities(tokens, intent);

    return IntentResult(
      intent: intent,
      entities: entities,
      confidence: classifier.confidence,
    );
  }
}
```

## Performance Optimization

### Audio Processing Pipeline

```dart
// Optimized audio processing
class AudioProcessor {
  static const int sampleRate = 16000;
  static const int frameSize = 512;

  final StreamController<Float32List> _audioStream = StreamController();
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  final NoiseSupressor _noiseSupressor = NoiseSupressor();

  void processAudioFrame(Float32List frame) {
    // Voice Activity Detection
    if (!_vad.isSpeech(frame)) {
      return; // Skip silence
    }

    // Noise suppression
    final cleanFrame = _noiseSupressor.process(frame);

    // Automatic Gain Control
    final normalizedFrame = normalizeAudio(cleanFrame);

    _audioStream.add(normalizedFrame);
  }
}
```

### Battery and Resource Management

```dart
class ResourceManager {
  Timer? _timeout;
  bool _isLowPowerMode = false;

  void startRecognition() {
    // Set timeout to prevent battery drain
    _timeout = Timer(Duration(minutes: 5), () {
      stopRecognition();
      showTimeoutMessage();
    });

    // Adjust quality based on battery
    if (Battery.level < 20) {
      _isLowPowerMode = true;
      reduceSampleRate();
      disableContinuousRecognition();
    }
  }
}
```

## Privacy and Security

### Data Handling
1. **On-device First**: Prefer local recognition when possible
2. **Explicit Consent**: Clear permissions for cloud services
3. **Data Retention**: No audio storage without user consent
4. **Encryption**: TLS for all network communication

### Implementation
```dart
class PrivacyManager {
  bool get canUseCloudServices => _preferences.getBool('cloud_speech_enabled') ?? false;
  bool get storeTranscriptions => _preferences.getBool('store_transcriptions') ?? false;

  Future<SpeechService> getSpeechService() async {
    if (await isOfflineMode() || !canUseCloudServices) {
      return OnDeviceSpeechService();
    }
    return CloudSpeechService();
  }
}
```

## Recommendation

For Zed Mobile, we recommend a hybrid approach:

1. **Primary**: Platform-native APIs (iOS Speech Framework / Android SpeechRecognizer)
   - Best performance and integration
   - No additional costs
   - Good accuracy for common commands

2. **Fallback**: Google Cloud Speech-to-Text
   - Superior accuracy for complex queries
   - Better handling of technical terms
   - Cross-platform consistency

3. **Wake Word**: Porcupine
   - Efficient battery usage
   - Customizable for "Hey Zed"
   - Proven reliability

This approach provides the best balance of performance, cost, and user experience while maintaining flexibility for future enhancements.
