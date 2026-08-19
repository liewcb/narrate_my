/// Base class for all third-party services (Firebase, Maps, etc.)
abstract class AppService {
  Future<void> init();
}

class SampleService extends AppService {
  @override
  Future<void> init() async {
    print("Service initialized");
  }
}
