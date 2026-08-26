import 'package:flutter/material.dart';
import '../../model/entities/ar_object.dart';
import '../../model/entities/ar_placement.dart';
import '../../model/business_logic/ar_heritage_interpretation_service/get_attraction_content_service.dart';

/// ViewModel corresponding to `AR Heritage Interpretation VM` in the architecture diagram
class ARHeritageInterpretationViewModel extends ChangeNotifier {
  final GetAttractionContentService _contentService;

  ARHeritageInterpretationViewModel({
    GetAttractionContentService? contentService,
  }) : _contentService = contentService ?? GetAttractionContentService();

  ARMarker? currentMarker;
  StoryScript? currentStory;
  bool isLoading = false;
  bool isAvatarPlaced = false;

  /// Initializes with marker data
  Future<void> init(ARMarker marker) async {
    currentMarker = marker;
    isLoading = true;
    isAvatarPlaced = false;
    notifyListeners();

    try {
      currentStory = await _contentService.fetchContent(
        markerId: marker.markerId,
        landmarkName: marker.name,
      );
    } catch (e) {
      debugPrint('Heritage interpretation fetch error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void placeAvatar() {
    isAvatarPlaced = true;
    notifyListeners();
  }

  void resetAvatar() {
    isAvatarPlaced = false;
    notifyListeners();
  }
}