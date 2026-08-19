/// Custom failure classes for consistent error handling across the app.
abstract class Failure {
  final String message;
  Failure(this.message);
}

class NetworkFailure extends Failure {
  NetworkFailure([String message = "No Internet Connection"]) : super(message);
}

class ServerFailure extends Failure {
  ServerFailure([String message = "Server Error Occurred"]) : super(message);
}

class CacheFailure extends Failure {
  CacheFailure([String message = "Cache Error Occurred"]) : super(message);
}
