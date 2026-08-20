import '../interfaces/profile_repository.dart';
import '../../entities/Profile.dart';

class InMemoryProfileAdapter implements ProfileRepository {
  Profile? _cached;
  @override Future<Profile> fetchProfile(String id) async {
    await Future.delayed(const Duration(milliseconds:300));
    return _cached ??= const Profile(id:'user_1', name:'New User');
  }
  @override Future<void> saveProfile(Profile profile) async {
    await Future.delayed(const Duration(milliseconds:300));
    _cached = profile;
  }
}