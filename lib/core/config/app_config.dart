/// Global app configuration: third-party service credentials and
/// tunable constants for the AR Exploration flow (UC100).
class AppConfig {
  // --- Supabase ---
  // TODO: move these to --dart-define / .env before shipping; hardcoded
  // here only so the scaffold runs out of the box during development.
  static const String supabaseUrl = 'https://mrvnphhstihhjhcextuh.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydm5waGhzdGloaGpoY2V4dHVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1MjA3NzQsImV4cCI6MjEwMjA5Njc3NH0.nPEza57C2eVhpJWJuIPNXzB60nd2kgBbK9onK0XoMQ4';

  // --- AR Exploration tuning (UC100) ---

  /// [C2] Geofence & Scan Radius Boundary — the DB query for nearby
  /// markers is bounded to this radius so we don't pull the whole table.
  static const double defaultScanRadiusMeters = 500;

  /// A marker only counts as "nearby" once the tourist is within its own
  /// activation_radius (per-marker override of the scan radius above).
  static const double fallbackActivationRadiusMeters = 100;

  /// [C3] How close (in degrees) the device compass heading must be to a
  /// marker's bearing for that marker to count as "directly faced" and be
  /// promoted to the primary anchored overlay (BF-6, BF-7).
  static const double headingToleranceDegrees = 20;

  /// How often we recompute distance/bearing against the live compass +
  /// GPS stream. Kept modest to avoid excessive rebuilds.
  static const Duration recomputeThrottle = Duration(milliseconds: 150);
}
