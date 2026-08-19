import '../entities/Profile.dart';
import '../repositories/interfaces/profile_repository.dart';

Map<String,String> validateProfileFields(String name, String? ageText) {
  final errors = <String,String>{};
  if (name.trim().isEmpty) errors['name'] = 'Name required';
  if (ageText!=null && ageText.isNotEmpty) {
    final a=int.tryParse(ageText);
    if (a==null) errors['age']='Age must be a number';
  }
  return errors;
}

// Orchestrator function that could call multiple repos/services:
Future<bool> updateProfile(ProfileRepository repo, Profile p) async {
  await repo.saveProfile(p);
  return true;
}