import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../entities/ar_placement.dart';
import '../../repositories/interfaces/ar_heritage_repository.dart';
import '../../repositories/adapters/ar_heritage_repository_adapter.dart';
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
  final ARHeritageRepository _heritageRepo;
  final AuthRemoteDataSource _authDataSource;

  StoryScript? _currentScript;
  TTSLanguageOption _currentLanguage = TTSLanguageOption.allLanguages.first;
  int _currentParagraphIndex = 0;
  int _currentSpokenWordIndex = 0; // Tracks word progress in current paragraph
  StoryPlaybackState _playbackState = StoryPlaybackState.stopped;
  Timer? _fallbackTimer;
  Timer? _wordProgressTimer;

  final _subtitleController = StreamController<String>.broadcast();
  final _stateController = StreamController<StoryPlaybackState>.broadcast();

  PlayNarrationService({
    FlutterTts? flutterTts,
    ARHeritageRepository? heritageRepo,
    AuthRemoteDataSource? authDataSource,
  })  : _flutterTts = flutterTts ?? FlutterTts(),
        _heritageRepo = heritageRepo ?? SupabaseARHeritageRepositoryAdapter(),
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
      await _flutterTts?.setSpeechRate(0.48); // Clear, friendly guide pace
      await _flutterTts?.setPitch(1.08); // Cheerful, warm avatar pitch
      await _flutterTts?.setVolume(1.0);

      // Track exact word position from native TTS
      _flutterTts?.setProgressHandler((String text, int startOffset, int endOffset, String word) {
        if (_playbackState == StoryPlaybackState.playing && _currentScript != null) {
          final paragraphs = _currentScript!.narrationParagraphs;
          if (_currentParagraphIndex < paragraphs.length) {
            final fullText = paragraphs[_currentParagraphIndex];
            final spokenSub = fullText.substring(0, endOffset.clamp(0, fullText.length));
            final wordsCount = spokenSub.trim().split(RegExp(r'\s+')).length;
            if (wordsCount > _currentSpokenWordIndex) {
              _currentSpokenWordIndex = wordsCount;
            }
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
    } catch (e) {
      debugPrint("TTS setLanguage error: $e");
    }

    // 2. Load script
    if (initialScript != null) {
      _currentScript = initialScript;
    } else {
      try {
        _currentScript = await _heritageRepo.getHeritageStory(markerId, landmarkName);
      } catch (e) {
        _currentScript = StoryScript.defaultForMarker(markerId, landmarkName);
      }
    }
    _currentParagraphIndex = 0;
    _currentSpokenWordIndex = 0;
    _playbackState = StoryPlaybackState.stopped;
    _emitSubtitle(_currentScript?.initialGreeting ?? "");
    _emitState(_playbackState);
    await _safeStopTts();
  }

  /// Starts or resumes playing narration with TTS voice in user's preferred language
  Future<void> play() async {
    if (_currentScript == null) return;
    _playbackState = StoryPlaybackState.playing;
    _emitState(_playbackState);

    await _speakCurrentParagraph();
  }

  /// Speaks the current paragraph.
  /// If resuming after pause, only speaks from the unread breakpoint words!
  Future<void> _speakCurrentParagraph() async {
    if (_currentScript == null) return;
    final paragraphs = _currentScript!.narrationParagraphs;
    if (paragraphs.isEmpty || _currentParagraphIndex >= paragraphs.length) {
      stop();
      return;
    }

    final fullText = paragraphs[_currentParagraphIndex];
    _emitSubtitle(fullText);

    final allWords = fullText.split(RegExp(r'\s+'));

    // Determine text to speak (Full paragraph vs. Remaining words after pause)
    String textToSpeak = fullText;
    int baseWordIndex = _currentSpokenWordIndex;

    if (baseWordIndex > 0 && baseWordIndex < allWords.length) {
      // Resume directly from where it was paused!
      textToSpeak = allWords.sublist(baseWordIndex).join(' ');
    } else {
      _currentSpokenWordIndex = 0;
      baseWordIndex = 0;
    }

    _fallbackTimer?.cancel();
    _wordProgressTimer?.cancel();

    // Internal word tracker for devices without native setProgressHandler
    final segmentWords = textToSpeak.split(RegExp(r'\s+'));
    int relativeWordIdx = 0;

    void stepWordTimer() {
      if (_playbackState != StoryPlaybackState.playing || relativeWordIdx >= segmentWords.length) {
        return;
      }
      final currentWord = segmentWords[relativeWordIdx];
      relativeWordIdx++;
      _currentSpokenWordIndex = baseWordIndex + relativeWordIdx;

      final wordLen = currentWord.length;
      final durationMs = (wordLen * 45 + 190).clamp(230, 520);

      _wordProgressTimer = Timer(Duration(milliseconds: durationMs), () {
        if (_playbackState == StoryPlaybackState.playing) {
          stepWordTimer();
        }
      });
    }

    _wordProgressTimer = Timer(const Duration(milliseconds: 150), stepWordTimer);

    final estimatedSeconds = (segmentWords.length / 2.0).clamp(3.0, 18.0).toInt();

    try {
      await _safeStopTts();
      await _flutterTts?.setLanguage(_currentLanguage.code);
      await _flutterTts?.speak(textToSpeak);

      _fallbackTimer = Timer(Duration(seconds: estimatedSeconds + 1), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });
    } catch (e) {
      _fallbackTimer = Timer(const Duration(seconds: 6), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _onParagraphSpeechCompleted();
        }
      });
    }
  }

  /// Triggered when the current paragraph speech finishes
  void _onParagraphSpeechCompleted() {
    _fallbackTimer?.cancel();
    _wordProgressTimer?.cancel();
    if (_playbackState != StoryPlaybackState.playing || _currentScript == null) return;

    _currentSpokenWordIndex = 0;

    final paragraphs = _currentScript!.narrationParagraphs;
    if (_currentParagraphIndex < paragraphs.length - 1) {
      _currentParagraphIndex++;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (_playbackState == StoryPlaybackState.playing) {
          _speakCurrentParagraph();
        }
      });
    } else {
      // Finished all paragraphs
      stop();
    }
  }

  /// Pauses narration and saves exact playback checkpoint position
  Future<void> pause() async {
    _playbackState = StoryPlaybackState.paused;
    _fallbackTimer?.cancel();
    _wordProgressTimer?.cancel();
    await _safeStopTts();
    _emitState(_playbackState);
  }

  /// Stops narration and resets to initial greeting
  Future<void> stop() async {
    _playbackState = StoryPlaybackState.stopped;
    _fallbackTimer?.cancel();
    _wordProgressTimer?.cancel();
    await _safeStopTts();
    _currentParagraphIndex = 0;
    _currentSpokenWordIndex = 0;
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
    _wordProgressTimer?.cancel();
    _safeStopTts();
    _subtitleController.close();
    _stateController.close();
  }
}
