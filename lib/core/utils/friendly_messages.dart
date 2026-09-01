import 'dart:async';

/// Maps raw exceptions to user-friendly messages for the itinerary UI.
///
/// Technical details (stack traces, exception types, HTTP status codes, DB
/// errors) are NEVER exposed to the user.  They remain in [debugPrint] logs
/// where developers can inspect them.
///
/// Usage:
///   debugPrint('[ADD_CUSTOM] Save failed: $e');           // developer
///   _saveError = friendlyErrorMessage(e);                  // user
String friendlyErrorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error == null) return fallback;
  final name = error.runtimeType.toString();

  // Timeout (network / AI)
  if (error is TimeoutException ||
      name.contains('TimeoutException') ||
      name.contains('Timeout')) {
    return 'The request took too long. Please try again.';
  }

  // Network connectivity
  if (name.contains('SocketException') ||
      name.contains('HandshakeException') ||
      name.contains('ClientException') ||
      name.contains('HttpException')) {
    return 'Unable to connect. Check your internet connection and try again.';
  }

  // Backend / API
  if (name.contains('PostgrestException') ||
      name.contains('Supabase') ||
      name.contains('AiApiException') ||
      name.contains('ApiException')) {
    return "We couldn't reach the server. Please try again.";
  }

  // AI model output
  if (name.contains('AiModelOutputException') ||
      name.contains('FormatException') ||
      name.contains('JsonUnsupportedObject')) {
    return 'The data was not in the expected format. Please try again.';
  }

  // Local database
  if (name.contains('DatabaseException') ||
      name.contains('Sqflite') ||
      name.contains('Sqlite')) {
    return "We couldn't save to your device. Please try again.";
  }

  return fallback;
}