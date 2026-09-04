import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../entities/ar_placement.dart';
import '../../repositories/interfaces/ar_heritage_repository.dart';
import '../ar_heritage_interpretation_service/get_attraction_content_service.dart';
import '../../data_sources/remote/auth_remote_data_source.dart';

/// Business logic service matching `PlayNarrationService` in architecture diagram.
/// Manages story subtitle streaming, playback state machine, and real-time TTS voice narration.
/// Automatically syncs user's `preferred_language` from Supabase `profiles` table:
/// - en -> English (en-US)
/// - zh -> Mandarin (zh-CN)
/// - ms -> Malay (ms-MY)
/// - es -> Spanish (es-ES)
/// - hi -> Hindi (hi-IN)
/// - If not logged in -> defaults strictly to 'en'
class PlayNarrationService {
  final FlutterTts? _flutterTts;
  final GetAttractionContentService _contentService;
  final AuthRemoteDataSource _authDataSource;

  StoryScript? _currentScript;
  TTSLanguageOption _currentLanguage = TTSLanguageOption.allLanguages.first;
  int _currentParagraphIndex = 0;
  int _currentSpokenWordIndex = 0; // Tracks word progress in current paragraph
  StoryPlaybackState _playbackState = StoryPlaybackState.stopped;
  Timer? _fallbackTimer;
  int _baseWordOffset = 0; // Word index where the current utterance started
  String _currentUtteranceText = ""; // Text being spoken in current utterance

  final _subtitleController = StreamController<String>.broadcast();
  final _stateController = StreamController<StoryPlaybackState>.broadcast();

  PlayNarrationService({
    FlutterTts? flutterTts,
    GetAttractionContentService? contentService,
    ARHeritageRepository? heritageRepo,
    AuthRemoteDataSource? authDataSource,
  })  : _flutterTts = flutterTts ?? FlutterTts(),
        _contentService = contentService ??
            (heritageRepo != null
                ? GetAttractionContentService(repository: heritageRepo)
                : GetAttractionContentService()),
        _authDataSource = authDataSource ?? AuthRemoteDataSource() {
    _initTts();
  }

  Stream<String> get subtitleStream => _subtitleController.stream;
  Stream<StoryPlaybackState> get stateStream => _stateController.stream;

  StoryPlaybackState get playbackState => _playbackState;
  StoryScript? get currentScript => _currentScript;
  TTSLanguageOption get currentLanguage => _currentLanguage;
  int get currentParagraphIndex => _currentParagraphIndex;
  int get currentSpokenWordIndex => _currentSpokenWordIndex;

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
      await _flutterTts?.setSpeechRate(0.30); // 🐢 Clear, comfortable storytelling pace (30%)
      await _flutterTts?.setPitch(1.25); // 🐻 Cute, cheerful cartoon voice for Manja
      await _flutterTts?.setVolume(1.0);

      // Track exact word position natively from TTS engine in real-time
      _flutterTts?.setProgressHandler((String text, int startOffset, int endOffset, String word) {
        if (_playbackState == StoryPlaybackState.playing && _currentUtteranceText.isNotEmpty) {
          final safeEnd = endOffset.clamp(0, _currentUtteranceText.length);
          final spokenSub = _currentUtteranceText.substring(0, safeEnd).trim();
          final wordsCount = spokenSub.isEmpty ? 0 : spokenSub.split(RegExp(r'\s+')).length;
          final totalWords = _baseWordOffset + wordsCount;
          if (totalWords > _currentSpokenWordIndex) {
            _currentSpokenWordIndex = totalWords;
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
      });
    } catch (e) {
      debugPrint("TTS initialization notice: $e");
    }
  }

  /// Loads story script for the given marker and retrieves user's preferred_language from `profiles`
  Future<void> loadScriptForMarker(String markerId, String landmarkName, {StoryScript? initialScript}) async {
    // 1. Fetch preferred_language from Supabase profiles (if logged in, else 'en')
    final langCode = await _authDataSource.fetchCurrentPreferredLanguage();
    _currentLanguage = TTSLanguageOption.fromCode(langCode);

    try {
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.setSpeechRate(0.30);
      await _flutterTts?.setPitch(1.25);
    } catch (e) {
      debugPrint("TTS setLanguage error: $e");
    }

    // 2. Load script
    if (initialScript != null) {
      _currentScript = initialScript;
    } else {
      try {
        _currentScript = await _contentService.fetchContent(
          markerId: markerId,
          landmarkName: landmarkName,
        );
      } catch (e) {
        _currentScript = StoryScript.defaultForMarker(markerId, landmarkName);
      }
    }
    _currentParagraphIndex = 0;
    _currentSpokenWordIndex = 0;
    _baseWordOffset = 0;
    _currentUtteranceText = "";
    _playbackState = StoryPlaybackState.stopped;
    _emitSubtitle(_currentScript?.initialGreeting ?? "");
    _emitState(_playbackState);
    await _safeStopTts();
  }

  /// Starts or resumes playing narration with TTS voice in user's preferred language
  Future<void> play() async {
    if (_currentScript == null) return;
    if (_playbackState == StoryPlaybackState.completed) {
      _currentParagraphIndex = 0;
      _currentSpokenWordIndex = 0;
      _baseWordOffset = 0;
    }
    _playbackState = StoryPlaybackState.playing;
    _emitState(_playbackState);

    await _speakCurrentParagraph();
  }

  /// Speaks the current paragraph.
  /// If resuming after pause, only speaks from the exact unread breakpoint words!
  Future<void> _speakCurrentParagraph() async {
    if (_currentScript == null) return;
    final paragraphs = _currentScript!.narrationParagraphs;
    if (paragraphs.isEmpty || _currentParagraphIndex >= paragraphs.length) {
      await _onAllParagraphsFinished();
      return;
    }

    final fullText = paragraphs[_currentParagraphIndex];
    _emitSubtitle(fullText);

    final allWords = fullText.split(RegExp(r'\s+'));

    // Determine text to speak (Full paragraph vs. Remaining words after pause)
    String textToSpeak = fullText;

    if (_currentSpokenWordIndex > 0 && _currentSpokenWordIndex < allWords.length) {
      // Resume directly from the exact word that was paused!
      _baseWordOffset = _currentSpokenWordIndex;
      textToSpeak = allWords.sublist(_baseWordOffset).join(' ');
    } else {
      _currentSpokenWordIndex = 0;
      _baseWordOffset = 0;
      textToSpeak = fullText;
    }
    _currentUtteranceText = textToSpeak;

    _fallbackTimer?.cancel();

    // Generous fallback safety timeout (never cuts off slow speech prematurely)
    final segmentWords = textToSpeak.split(RegExp(r'\s+'));
    final safeTimeoutSeconds = (segmentWords.length * 4) + 15;

    try {
      await _safeStopTts();
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.speak(textToSpeak);

      _fallbackTimer = Timer(Duration(seconds: safeTimeoutSeconds), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });
    } catch (e) {
      _fallbackTimer = Timer(const Duration(seconds: 10), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });
    }
  }

  /// Triggered when the current paragraph speech finishes
  void _onParagraphSpeechCompleted() {
    _fallbackTimer?.cancel();
    if (_playbackState != StoryPlaybackState.playing || _currentScript == null) return;

    _currentSpokenWordIndex = 0;
    _baseWordOffset = 0;
    _currentUtteranceText = "";

    final paragraphs = _currentScript!.narrationParagraphs;
    if (_currentParagraphIndex < paragraphs.length - 1) {
      _currentParagraphIndex++;
      // Immediately emit the next paragraph subtitle so the user and UI see it right away!
      _emitSubtitle(paragraphs[_currentParagraphIndex]);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _speakCurrentParagraph();
        }
      });
    } else {
      // Finished all paragraphs -> Transition to completed!
      _onAllParagraphsFinished();
    }
  }

  /// Handles landmark narration completion with closing message and Replay state
  Future<void> _onAllParagraphsFinished() async {
    _playbackState = StoryPlaybackState.completed;
    _fallbackTimer?.cancel();
    await _safeStopTts();
    _currentParagraphIndex = 0;
    _currentSpokenWordIndex = 0;
    _baseWordOffset = 0;
    _currentUtteranceText = "";
    _emitState(_playbackState);
    final name = _currentScript?.landmarkName ?? 'this landmark';
    _emitSubtitle("🎉 You've completed the story of $name! Hope you enjoyed the journey!");
  }

  /// Pauses narration and saves exact playback checkpoint position
  Future<void> pause() async {
    _playbackState = StoryPlaybackState.paused;
    _fallbackTimer?.cancel();
    await _safeStopTts();
    _emitState(_playbackState);
  }

  /// Stops narration and resets to initial greeting
  Future<void> stop() async {
    _playbackState = StoryPlaybackState.stopped;
    _fallbackTimer?.cancel();
    await _safeStopTts();
    _currentParagraphIndex = 0;
    _currentSpokenWordIndex = 0;
    _baseWordOffset = 0;
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
      _currentSpokenWordIndex = 0;
      if (_playbackState == StoryPlaybackState.playing) {
        _speakCurrentParagraph();
      } else {
        _emitSubtitle(paragraphs[_currentParagraphIndex]);
      }
    }
  }

  void dispose() {
    _fallbackTimer?.cancel();
    _safeStopTts();
    _subtitleController.close();
    _stateController.close();
  }
}
