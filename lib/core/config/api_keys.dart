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
  // static const String googleMapsApiKey = 'AIzaSyCLg1gBrQOjcfJrg2YCbrLAiGoX602LMIQ';
  static const String baiApiKey = 'sk-wy3505ikrt9kzkwviip5o7ymui5j9a2s';
  static const String baiModel = 'deepseek-v4-flash';
  static const String openRouterApiKey = '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';
  static const String cohereApiKey = 'lKBNvJX7bEGZ7RSIjxH8TVaEHGdVF8KOul2deV9w';
  static const String weatherApikey = '11c8446740d749b88bb95110262608';
}
