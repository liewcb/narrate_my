import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../entities/ar_placement.dart';
import '../../repositories/interfaces/ar_heritage/ar_heritage_repository.dart';
import '../ar_heritage_interpretation_service/get_attraction_content_service.dart';
import '../ar_heritage_interpretation_service/translation_service.dart';
import '../../../core/localization/app_localizations.dart';

/// Business logic service matching `PlayNarrationService` in architecture diagram.
/// Manages story subtitle streaming, playback state machine, and real-time TTS voice narration.
/// Supports 5 languages (English, Chinese, Malay, Spanish, Hindi).
/// Features a universal progress ticker ensuring paragraph completion and pause-resume work
/// flawlessly across all languages regardless of Android TTS word-callback availability.
class PlayNarrationService {
  final FlutterTts? _flutterTts;
  final GetAttractionContentService _contentService;
  final TranslationService _translationService;

  StoryScript? _originalScript; // Untranslated script from database
  StoryScript? _currentScript;  // Translated script matching active language
  TTSLanguageOption _currentLanguage = TTSLanguageOption.allLanguages.first;
  int _currentParagraphIndex = 0;
  int _currentSpokenCharIndex = 0; // Tracks character progress in current paragraph
  StoryPlaybackState _playbackState = StoryPlaybackState.stopped;

  Timer? _fallbackTimer;
  Timer? _nextParagraphTimer;
  Timer? _progressTicker;
  final Stopwatch _utteranceStopwatch = Stopwatch();
  int _estimatedDurationMs = 0;

  int _baseCharOffset = 0; // Character offset where the current utterance started
  String _currentUtteranceText = ""; // Text being spoken in current utterance

  final _subtitleController = StreamController<String>.broadcast();
  final _stateController = StreamController<StoryPlaybackState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  PlayNarrationService({
    FlutterTts? flutterTts,
    GetAttractionContentService? contentService,
    ARHeritageRepository? heritageRepo,
    TranslationService? translationService,
  })  : _flutterTts = flutterTts ?? FlutterTts(),
        _contentService = contentService ??
            (heritageRepo != null
                ? GetAttractionContentService(repository: heritageRepo)
                : GetAttractionContentService()),
        _translationService = translationService ?? TranslationService() {
    _initTts();
  }

  Stream<String> get subtitleStream => _subtitleController.stream;
  Stream<StoryPlaybackState> get stateStream => _stateController.stream;
  Stream<String> get errorStream => _errorController.stream;

  StoryPlaybackState get playbackState => _playbackState;
  StoryScript? get currentScript => _currentScript;
  TTSLanguageOption get currentLanguage => _currentLanguage;
  int get currentParagraphIndex => _currentParagraphIndex;
  int get currentSpokenWordIndex => _currentSpokenCharIndex;

  void _emitError(String error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  void _emitSubtitle(String subtitle) {
    if (!_subtitleController.isClosed) {
      _subtitleController.add(subtitle);
    }
  }

  void _emitState(StoryPlaybackState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  /// Initializes TTS engine with optimal parameters for tour guide avatar Manja
  Future<void> _initTts() async {
    try {
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.setSpeechRate(0.50); // Natural, clear storytelling pace
      await _flutterTts?.setPitch(1.20); // Cheerful cartoon voice for Manja
      await _flutterTts?.setVolume(1.0);

      // Track exact position natively if supported by TTS engine
      _flutterTts?.setProgressHandler((String text, int startOffset, int endOffset, String word) {
        if (_playbackState == StoryPlaybackState.playing && _currentUtteranceText.isNotEmpty) {
          final safeEnd = endOffset.clamp(0, _currentUtteranceText.length);
          final totalOffset = _baseCharOffset + safeEnd;
          if (totalOffset > _currentSpokenCharIndex) {
            _currentSpokenCharIndex = totalOffset;
          }
        }
      });

      _flutterTts?.setCompletionHandler(() {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });

      _flutterTts?.setErrorHandler((msg) {
        debugPrint("TTS speech error: $msg");
        _emitError("TTS speech generation failed: $msg");
      });
    } catch (e) {
      debugPrint("TTS initialization notice: $e");
    }
  }

  /// Checks if current paragraph has completed speaking or is at the trailing tail
  bool _isCurrentParagraphFinished() {
    if (_currentScript == null) return true;
    final paragraphs = _currentScript!.narrationParagraphs;
    if (_currentParagraphIndex >= paragraphs.length) return true;
    final fullText = paragraphs[_currentParagraphIndex].trim();
    if (fullText.isEmpty) return true;

    // 1. Spoken characters reached or exceeded total length
    if (_currentSpokenCharIndex >= fullText.length) return true;

    // 2. Trailing tail check: <= 4 characters remaining or >= 85% elapsed
    final remainingChars = fullText.length - _currentSpokenCharIndex;
    if (remainingChars <= 4 || (_currentSpokenCharIndex / fullText.length) >= 0.85) {
      return true;
    }

    // 3. Time-based check: if stopwatch passed 88% of estimated utterance duration
    if (_estimatedDurationMs > 0 &&
        _utteranceStopwatch.elapsedMilliseconds >= (_estimatedDurationMs * 0.88)) {
      return true;
    }

    return false;
  }

  /// Loads story script for the given marker and retrieves user's preferred_language from `profiles`
  /// REQ_201_4: Automatically translates the attraction content into the user's preferred language before narration generation.
  Future<void> loadScriptForMarker(String markerId, String landmarkName, {StoryScript? initialScript}) async {
    // Use the active app language; profile synchronization belongs to the profile layer.
    final langCode = AppLocalizations.currentCode;
    _currentLanguage = TTSLanguageOption.fromCode(langCode);

    try {
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.setSpeechRate(0.50);
      await _flutterTts?.setPitch(1.20);
    } catch (e) {
      debugPrint("TTS setLanguage error: $e");
    }

    // 2. Load script
    if (initialScript != null) {
      _originalScript = initialScript;
    } else {
      _originalScript = await _contentService.fetchContent(
        markerId: markerId,
        landmarkName: landmarkName,
      );
    }

    // Check if content retrieval failed
    if (_originalScript == null || _originalScript!.id.startsWith('error_')) {
      final errorMsg = _currentLanguage.code.startsWith('zh')
          ? "无法获取 $landmarkName 的景点讲解内容。"
          : _currentLanguage.code.startsWith('ms')
              ? "Kandungan tarikan untuk $landmarkName tidak dapat dimuatkan."
              : _currentLanguage.code.startsWith('es')
                  ? "No se pudo obtener el contenido de la atracción para $landmarkName."
                  : _currentLanguage.code.startsWith('hi')
                      ? "$landmarkName के लिए आकर्षण सामग्री लोड नहीं की जा सकी।"
                      : (_originalScript?.initialGreeting.replaceFirst('Error: ', '') ??
                          "Unable to retrieve attraction content for $landmarkName.");
      _emitError(errorMsg);
      throw Exception(errorMsg);
    }

    // 3. REQ_201_4: Translate content into determined language before narration generation
    if (!_currentLanguage.code.startsWith('en')) {
      _currentScript = await _translationService.translateStoryScript(
        _originalScript!,
        _currentLanguage.code,
      );
    } else {
      _currentScript = _originalScript;
    }

    _currentParagraphIndex = 0;
    _currentSpokenCharIndex = 0;
    _baseCharOffset = 0;
    _currentUtteranceText = "";
    _playbackState = StoryPlaybackState.stopped;
    _progressTicker?.cancel();
    _utteranceStopwatch.reset();
    _emitSubtitle(_currentScript?.initialGreeting ?? "");
    _emitState(_playbackState);
    await _safeStopTts();
  }

  /// Changes the narration language dynamically and re-translates script if necessary
  Future<void> changeLanguage(TTSLanguageOption newLanguage) async {
    if (_currentLanguage.code == newLanguage.code) return;
    _currentLanguage = newLanguage;
    try {
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.setSpeechRate(0.50);
      await _flutterTts?.setPitch(1.20);
    } catch (e) {
      debugPrint("TTS setLanguage error: $e");
    }

    if (_originalScript != null) {
      if (_currentLanguage.code.startsWith('en')) {
        _currentScript = _originalScript;
      } else {
        _currentScript = await _translationService.translateStoryScript(
          _originalScript!,
          _currentLanguage.code,
        );
      }

      if (_playbackState == StoryPlaybackState.playing) {
        await _safeStopTts();
        _currentSpokenCharIndex = 0;
        _baseCharOffset = 0;
        await _speakCurrentParagraph();
      } else {
        if (_currentParagraphIndex == 0 && _currentSpokenCharIndex == 0) {
          _emitSubtitle(_currentScript?.initialGreeting ?? "");
        } else if (_currentParagraphIndex < (_currentScript?.narrationParagraphs.length ?? 0)) {
          _emitSubtitle(_currentScript!.narrationParagraphs[_currentParagraphIndex]);
        }
      }
    }
  }

  /// Starts or resumes playing narration with TTS voice in user's preferred language
  Future<void> play() async {
    if (_currentScript == null) return;
    if (_playbackState == StoryPlaybackState.completed) {
      _currentParagraphIndex = 0;
      _currentSpokenCharIndex = 0;
      _baseCharOffset = 0;
    } else {
      // If current paragraph already finished or is near the end, advance immediately!
      final paragraphs = _currentScript!.narrationParagraphs;
      if (_isCurrentParagraphFinished()) {
        if (_currentParagraphIndex < paragraphs.length - 1) {
          _currentParagraphIndex++;
          _currentSpokenCharIndex = 0;
          _baseCharOffset = 0;
          _currentUtteranceText = "";
        } else {
          await _onAllParagraphsFinished();
          return;
        }
      }
    }
    _playbackState = StoryPlaybackState.playing;
    _emitState(_playbackState);

    await _speakCurrentParagraph();
  }

  /// Speaks the current paragraph in the user's preferred language.
  /// If resuming after pause, speaks from the exact breakpoint!
  Future<void> _speakCurrentParagraph() async {
    if (_currentScript == null) return;
    final paragraphs = _currentScript!.narrationParagraphs;
    if (paragraphs.isEmpty || _currentParagraphIndex >= paragraphs.length) {
      await _onAllParagraphsFinished();
      return;
    }

    // Auto-advance if already finished this paragraph
    if (_isCurrentParagraphFinished()) {
      if (_currentParagraphIndex < paragraphs.length - 1) {
        _currentParagraphIndex++;
        _currentSpokenCharIndex = 0;
        _baseCharOffset = 0;
      } else {
        await _onAllParagraphsFinished();
        return;
      }
    }

    var fullText = paragraphs[_currentParagraphIndex];
    _emitSubtitle(fullText);

    // Determine text to speak (Full paragraph vs. Remaining breakpoint text after pause)
    String textToSpeak = fullText;

    if (_currentSpokenCharIndex > 0 && _currentSpokenCharIndex < fullText.length) {
      var remaining = fullText.substring(_currentSpokenCharIndex).trim();
      // Clean leading punctuation
      while (remaining.isNotEmpty &&
          (remaining.startsWith(',') ||
              remaining.startsWith('.') ||
              remaining.startsWith('!') ||
              remaining.startsWith('?') ||
              remaining.startsWith('，') ||
              remaining.startsWith('。') ||
              remaining.startsWith('！') ||
              remaining.startsWith('？') ||
              remaining.startsWith('；') ||
              remaining.startsWith(';'))) {
        remaining = remaining.substring(1).trim();
      }

      // If only 1-3 characters of trailing punctuation remaining, move to next paragraph directly
      if (remaining.isNotEmpty && remaining.length > 3) {
        _baseCharOffset = fullText.length - remaining.length;
        textToSpeak = remaining;
      } else {
        if (_currentParagraphIndex < paragraphs.length - 1) {
          _currentParagraphIndex++;
          _currentSpokenCharIndex = 0;
          _baseCharOffset = 0;
          fullText = paragraphs[_currentParagraphIndex];
          _emitSubtitle(fullText);
          textToSpeak = fullText;
        } else {
          await _onAllParagraphsFinished();
          return;
        }
      }
    } else {
      _currentSpokenCharIndex = 0;
      _baseCharOffset = 0;
      textToSpeak = fullText;
    }
    _currentUtteranceText = textToSpeak;

    _fallbackTimer?.cancel();
    _nextParagraphTimer?.cancel();
    _progressTicker?.cancel();

    // Universal duration estimation:
    // Chinese: ~3.2 characters / sec at 0.50 rate
    // Others (English, Malay, Spanish, Hindi): ~2.8 words / sec at 0.50 rate
    if (_currentLanguage.code.startsWith('zh')) {
      _estimatedDurationMs = ((textToSpeak.length / 3.2) * 1000).round() + 400;
    } else {
      final wordsCount = textToSpeak.split(RegExp(r'\s+')).length;
      _estimatedDurationMs = ((wordsCount / 2.8) * 1000).round() + 500;
    }

    _utteranceStopwatch.reset();
    _utteranceStopwatch.start();

    // Periodic ticker (every 100ms): ensures progress advances smoothly across ALL languages
    _progressTicker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_playbackState != StoryPlaybackState.playing) {
        timer.cancel();
        return;
      }
      final elapsed = _utteranceStopwatch.elapsedMilliseconds;
      if (_estimatedDurationMs > 0) {
        final ratio = (elapsed / _estimatedDurationMs).clamp(0.0, 1.0);
        final estChars = (ratio * textToSpeak.length).round();
        final currentEst = _baseCharOffset + estChars;
        if (currentEst > _currentSpokenCharIndex) {
          _currentSpokenCharIndex = currentEst;
        }
      }
    });

    final safeTimeoutSeconds = (_estimatedDurationMs ~/ 1000) + 6;

    try {
      await _safeStopTts();
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.setSpeechRate(0.50);
      await _flutterTts?.speak(textToSpeak);

      _fallbackTimer = Timer(Duration(seconds: safeTimeoutSeconds), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });
    } catch (e) {
      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });
    }
  }

  /// Triggered when the current paragraph speech finishes
  void _onParagraphSpeechCompleted() {
    _fallbackTimer?.cancel();
    _nextParagraphTimer?.cancel();
    _progressTicker?.cancel();
    _utteranceStopwatch.stop();

    if (_playbackState != StoryPlaybackState.playing || _currentScript == null) return;

    _currentSpokenCharIndex = 0;
    _baseCharOffset = 0;
    _currentUtteranceText = "";

    final paragraphs = _currentScript!.narrationParagraphs;
    if (_currentParagraphIndex < paragraphs.length - 1) {
      _currentParagraphIndex++;
      // Immediately emit the next paragraph subtitle so the user and UI see it right away!
      _emitSubtitle(paragraphs[_currentParagraphIndex]);
      // Crisp, natural 150ms transition to the next paragraph
      _nextParagraphTimer = Timer(const Duration(milliseconds: 150), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _speakCurrentParagraph();
        }
      });
    } else {
      // Finished all paragraphs -> Transition to completed
      _onAllParagraphsFinished();
    }
  }

  /// Handles landmark narration completion with closing message
  Future<void> _onAllParagraphsFinished() async {
    _playbackState = StoryPlaybackState.completed;
    _fallbackTimer?.cancel();
    _nextParagraphTimer?.cancel();
    _progressTicker?.cancel();
    _utteranceStopwatch.stop();
    await _safeStopTts();
    _currentParagraphIndex = 0;
    _currentSpokenCharIndex = 0;
    _baseCharOffset = 0;
    _currentUtteranceText = "";
    _emitState(_playbackState);

    final name = _currentScript?.landmarkName ?? 'this landmark';
    final completionMsg = _currentLanguage.code.startsWith('zh')
        ? "🎉 你已经听完了 $name 的精彩故事！希望你喜欢这次旅程！"
        : _currentLanguage.code.startsWith('ms')
            ? "🎉 Anda telah selesai mendengar cerita $name! Semoga anda menikmati perjalanan ini!"
            : _currentLanguage.code.startsWith('es')
                ? "🎉 ¡Has completado la historia de $name! ¡Esperamos que hayas disfrutado del viaje!"
                : _currentLanguage.code.startsWith('hi')
                    ? "🎉 आपने $name की कहानी पूरी कर ली है! आशा है आपको यात्रा पसंद आई होगी!"
                    : "🎉 You've completed the story of $name! Hope you enjoyed the journey!";
    _emitSubtitle(completionMsg);
  }

  /// Pauses narration and saves exact playback checkpoint position
  Future<void> pause() async {
    _playbackState = StoryPlaybackState.paused;
    _fallbackTimer?.cancel();
    _nextParagraphTimer?.cancel();
    _progressTicker?.cancel();
    _utteranceStopwatch.stop();
    await _safeStopTts();

    // If current paragraph was already finished or near the end, advance immediately!
    if (_currentScript != null) {
      final paragraphs = _currentScript!.narrationParagraphs;
      if (_isCurrentParagraphFinished()) {
        if (_currentParagraphIndex < paragraphs.length - 1) {
          _currentParagraphIndex++;
          _currentSpokenCharIndex = 0;
          _baseCharOffset = 0;
          _currentUtteranceText = "";
          _emitSubtitle(paragraphs[_currentParagraphIndex]);
        } else {
          await _onAllParagraphsFinished();
          return;
        }
      }
    }

    _emitState(_playbackState);
  }

  /// Stops narration and resets to initial greeting
  Future<void> stop() async {
    _playbackState = StoryPlaybackState.stopped;
    _fallbackTimer?.cancel();
    _nextParagraphTimer?.cancel();
    _progressTicker?.cancel();
    _utteranceStopwatch.stop();
    await _safeStopTts();
    _currentParagraphIndex = 0;
    _currentSpokenCharIndex = 0;
    _baseCharOffset = 0;
    _currentUtteranceText = "";
    _emitState(_playbackState);
    if (_currentScript != null) {
      _emitSubtitle(_currentScript!.initialGreeting);
    }
  }

  Future<void> _safeStopTts() async {
    try {
      await _flutterTts?.stop();
    } catch (_) {}
  }

  /// Advances to next paragraph manually
  void nextParagraph() {
    if (_currentScript == null) return;
    final paragraphs = _currentScript!.narrationParagraphs;
    if (_currentParagraphIndex < paragraphs.length - 1) {
      _currentParagraphIndex++;
      _currentSpokenCharIndex = 0;
      if (_playbackState == StoryPlaybackState.playing) {
        _speakCurrentParagraph();
      } else {
        _emitSubtitle(paragraphs[_currentParagraphIndex]);
      }
    }
  }

  void dispose() {
    _fallbackTimer?.cancel();
    _nextParagraphTimer?.cancel();
    _progressTicker?.cancel();
    _utteranceStopwatch.stop();
    _safeStopTts();
    _subtitleController.close();
    _stateController.close();
    _errorController.close();
  }
}
