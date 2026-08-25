import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/uc402_messages.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs the logged-in Profile home screen: loads the summary shown at the
/// top (avatar/name/username) and owns logout. Section-specific editing
/// (Personal Info, Preferences, Language, Bookmarks) each has its own,
/// more focused ViewModel — this one is deliberately thin.
class ProfileVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  ProfileVm({
    ProfileRepository? profileRepository,
  }) : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    load();
  }

  Profile? profile;
  bool isLoading = false;
  String? errorMessage;

  // Added at Foo's request — separate flag from [isLoading] so an avatar
  // upload shows a small spinner over the avatar itself rather than
  // replacing the whole screen with the full-page loading state.
  bool isUploadingAvatar = false;
  String? avatarErrorMessage;

  // Separate from [errorMessage] (which drives the full-screen retry state
  // for a failed profile *load*) so a failed delete instead surfaces as an
  // inline message the caller can show in a SnackBar/dialog without the
  // whole Profile screen flipping into its error-retry layout.
  bool isDeletingAccount = false;
  String? deleteAccountErrorMessage;

  /// UC402 A1: retrieval failure — [errorMessage] carries M3, and the
  /// screen should offer a Retry that just calls this again.
  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      profile = await _profileRepository.fetchProfile();
    } on AuthFailure catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() => _profileRepository.logout();

  // --- Added at Foo's request — NOT in the written spec ----------------------

  /// Opens the system photo picker, uploads the chosen image, and saves it
  /// as the new avatar. Returns false (with no error set) if the tourist
  /// simply cancelled the picker — that's not a failure worth showing.
  Future<bool> pickAndUploadAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked == null) return false;
    isUploadingAvatar = true;
    avatarErrorMessage = null;
    notifyListeners();
    try {
      final bytes = await picked.readAsBytes();
      final dotIndex = picked.path.lastIndexOf('.');
      final ext = dotIndex == -1 ? 'jpg' : picked.path.substring(dotIndex + 1).toLowerCase();
      profile = await _profileRepository.updateAvatar(bytes: bytes, fileExt: ext);
      isUploadingAvatar = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isUploadingAvatar = false;
      avatarErrorMessage = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      isUploadingAvatar = false;
      avatarErrorMessage = Uc402Messages.m25UnableToUpdatePhoto;
      notifyListeners();
      return false;
    }
  }

  /// Irreversible — the calling screen must confirm with the tourist
  /// before calling this. Returns true on success; the caller should then
  /// navigate away (there is no profile left to show).
  Future<bool> deleteAccount() async {
    isDeletingAccount = true;
    deleteAccountErrorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.deleteAccount();
      isDeletingAccount = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isDeletingAccount = false;
      deleteAccountErrorMessage = e.message;
      notifyListeners();
      return false;
    }
  }
}
