import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/entities/ar_object.dart';
import 'package:narrate_my/model/entities/ar_placement.dart';
import 'package:narrate_my/model/repositories/interfaces/ar_heritage_repository.dart';
import 'package:narrate_my/model/data_sources/remote/auth_remote_data_source.dart';
import 'package:narrate_my/model/business_logic/ar_placement_service/play_narration_service.dart';

class FakeHeritageRepository implements ARHeritageRepository {
  @override
  Future<StoryScript> getHeritageStory(String markerId, String landmarkName) async {
    return StoryScript.defaultForMarker(markerId, landmarkName);
  }

  @override
  Future<ARMarker?> getHeritageMarkerById(String markerId) async {
    return null;
  }
}

class FakeAuthRemoteDataSource extends Fake implements AuthRemoteDataSource {
  @override
  Future<String> fetchCurrentPreferredLanguage() async => 'en';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayNarrationService & Storytelling Flow Tests', () {
    late PlayNarrationService narrationService;

    setUp(() {
      narrationService = PlayNarrationService(
        heritageRepo: FakeHeritageRepository(),
        authDataSource: FakeAuthRemoteDataSource(),
      );
    });

    tearDown(() {
      narrationService.dispose();
    });

    test('Loads default story script correctly for given marker', () async {
      const dummyMarker = ARMarker(
        markerId: 'klcc_101',
        latitude: 3.1575,
        longitude: 101.7116,
        name: 'KLCC Twin Towers',
        activationRadiusMeters: 80,
      );

      await narrationService.loadScriptForMarker(dummyMarker.markerId, dummyMarker.name);

      expect(narrationService.currentScript, isNotNull);
      expect(narrationService.currentScript!.landmarkName, 'KLCC Twin Towers');
      expect(narrationService.playbackState, StoryPlaybackState.stopped);
      expect(narrationService.currentScript!.narrationParagraphs.length, greaterThan(0));
    });

    test('Play, Pause, and Stop state machine transitions smoothly', () async {
      await narrationService.loadScriptForMarker('klcc_101', 'KLCC');

      // 1. Play
      await narrationService.play();
      expect(narrationService.playbackState, StoryPlaybackState.playing);

      // 2. Pause
      narrationService.pause();
      expect(narrationService.playbackState, StoryPlaybackState.paused);

      // 3. Stop
      narrationService.stop();
      expect(narrationService.playbackState, StoryPlaybackState.stopped);
      expect(narrationService.currentParagraphIndex, 0);
    });
  });

  group('ARAvatarConfig entity tests', () {
    test('Default Manja avatar configuration creates valid scaling and angles', () {
      final config = ARAvatarConfig.defaultManja();
      expect(config.modelUri, 'assets/images/3dmodel/manja.glb');
      expect(config.scale.x, 0.01);
      expect(config.scale.y, 0.01);
      expect(config.scale.z, 0.01);
    });
  });
}
