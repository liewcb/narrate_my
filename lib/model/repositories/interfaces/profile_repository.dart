import '../../entities/Profile.dart';

abstract class ProfileRepository {
  Future<Profile> fetchProfile(String id);
  Future<void> saveProfile(Profile profile);
}