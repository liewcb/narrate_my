// lib/ViewModel/Profile_VM.dart

import 'package:flutter/foundation.dart';
import '../Model/Business Logic/profile_service.dart';

/// ViewModel: contains business logic, validation, and coordinates repository.
class ProfileVM extends ChangeNotifier {
  final ProfileRepository repository;

  Profile? _profile;
  bool isLoading = false;
  String? error;

  // Editable fields
  String name = '';
  String? ageText;
  String? religion;
  String? ethnicity;
  String? language;
  String? country;
  Gender? gender;

  ProfileVM({required this.repository});

  Profile? get profile => _profile;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      _profile = await repository.fetchProfile();
      name = _profile?.name ?? '';
      ageText = _profile?.age?.toString();
      religion = _profile?.religion;
      ethnicity = _profile?.ethnicity;
      language = _profile?.language;
      country = _profile?.country;
      gender = _profile?.gender;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Map<String, String> validate() {
    final Map<String, String> errors = {};
    if (name.trim().isEmpty) errors['name'] = 'Name is required.';
    if (ageText != null && ageText!.isNotEmpty) {
      final v = int.tryParse(ageText!);
      if (v == null) errors['age'] = 'Age must be a number.';
      else if (v < 0 || v > 120) errors['age'] = 'Age must be between 0 and 120.';
    }
    return errors;
  }

  Future<bool> save() async {
    final errors = validate();
    if (errors.isNotEmpty) {
      error = errors.values.first;
      notifyListeners();
      return false;
    }

    isLoading = true;
    notifyListeners();
    try {
      final int? parsedAge = (ageText != null && ageText!.isNotEmpty) ? int.tryParse(ageText!) : null;
      final updated = Profile(
        id: _profile?.id ?? 'user_1',
        name: name.trim(),
        age: parsedAge,
        religion: religion,
        ethnicity: ethnicity,
        language: language,
        country: country,
        gender: gender,
      );
      await repository.saveProfile(updated);
      _profile = updated;
      error = null;
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void resetEdits() {
    if (_profile != null) {
      name = _profile!.name;
      ageText = _profile!.age?.toString();
      religion = _profile!.religion;
      ethnicity = _profile!.ethnicity;
      language = _profile!.language;
      country = _profile!.country;
      gender = _profile!.gender;
      notifyListeners();
    }
  }
}
