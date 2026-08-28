class ApiKeys {
  // Supplied locally with --dart-define/--dart-define-from-file so the key is
  // never committed. MAPS_API_KEY matches android/local.properties, while the
  // older name remains supported for command-line runs.
  static const String _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );
  static const String _mapsApiKey = String.fromEnvironment('MAPS_API_KEY');
  static final String googleMapsApiKey = _googleMapsApiKey.isNotEmpty
      ? _googleMapsApiKey
      : _mapsApiKey;
  static const String baiApiKey = '';
  static const String baiModel = '';
  static const String openRouterApiKey = '';
  static const String cohereApiKey = '';
}
