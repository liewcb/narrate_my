/// Global app configuration: third-party service credentials and
/// tunable constants for the AR Exploration flow (UC100).
class AppConfig {
  // --- Supabase ---
  // TODO: move these to --dart-define / .env before shipping; hardcoded
  // here only so the scaffold runs out of the box during development.
  static const String supabaseUrl = 'https://mrvnphhstihhjhcextuh.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydm5waGhzdGloaGpoY2V4dHVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1MjA3NzQsImV4cCI6MjEwMjA5Njc3NH0.nPEza57C2eVhpJWJuIPNXzB60nd2kgBbK9onK0XoMQ4';

  // --- AR Exploration tuning (UC100) ---

  /// [C2] Geofence & Scan Radius Boundary — the DB query for nearby
  /// markers is bounded to this radius so we don't pull the whole table.
  static const double defaultScanRadiusMeters = 500;

  /// A marker only counts as "nearby" once the tourist is within its own
  /// activation_radius (per-marker override of the scan radius above).
  static const double fallbackActivationRadiusMeters = 100;

  /// Public AR sites loaded for the Nearby map. This is intentionally wider
  /// than the camera scan radius: the map helps tourists discover where AR is
  /// available before they physically travel there.
  static const double nearbyArSiteRadiusMeters = 30000;

  /// [C3] How close (in degrees) the device compass heading must be to a
  /// marker's bearing for that marker to count as "directly faced" and be
  /// promoted to the primary anchored overlay (BF-6, BF-7).
  static const double headingToleranceDegrees = 20;

  /// How often we recompute distance/bearing against the live compass +
  /// GPS stream. Kept modest to avoid excessive rebuilds.
  static const Duration recomputeThrottle = Duration(milliseconds: 150);

  // --- Module 5: hCaptcha (REQ_501_12/REQ_502_21, UC400 A8/C4) ---

  /// hCaptcha SITE key — public by design, safe to ship client-side (it
  /// only identifies which hCaptcha account/site the challenge belongs to;
  /// the SECRET key that actually verifies a solve never goes in the app —
  /// it's a Supabase Edge Function secret, see
  /// `supabase/functions/verify-captcha/index.ts`).
  ///
  /// Real site key from https://dashboard.hcaptcha.com — the matching
  /// SECRET key must be set as the `HCAPTCHA_SECRET` Supabase Edge Function
  /// secret (never committed here); see
  /// `supabase/functions/verify-captcha/index.ts`.
  static const String hcaptchaSiteKey = '06e67972-2304-45ca-9a8c-0fb4edd63dac';

  /// Max device pitch (degrees, 0 = held level/upright pointing at the
  /// horizon) before markers are hidden. Beyond this the tourist is
  /// pointing the camera at the ground or the sky, not at a building, so
  /// there's nothing valid to anchor a marker to.
  static const double pitchToleranceDegrees = 35;

  /// Width (in degrees) of the soft zone at the edge of the FOV / pitch
  /// tolerance over which a marker fades and slides out, instead of
  /// snapping away the instant it crosses the boundary.
  static const double edgeFadeDegrees = 10;

  /// Altitude difference (meters, marker minus tourist) that maps to the
  /// full [altitudeVerticalRangeFraction] vertical swing on screen. Two
  /// markers whose altitude differs by more than this collapse to the
  /// same clamped edge instead of separating further — keeps a distant
  /// rooftop from flying off the top of the screen.
  static const double maxExpectedAltitudeRangeMeters = 50;

  /// How much of the screen height the altitude offset is allowed to move
  /// a marker, up or down, from the fixed anchor line.
  static const double altitudeVerticalRangeFraction = 0.18;

  /// Clamp bounds (fraction of screen height) for the marker's final
  /// vertical position, so an extreme altitude delta can't push a marker
  /// off the top/bottom of the screen entirely.
  static const double markerMinDyFraction = 0.10;
  static const double markerMaxDyFraction = 0.62;
}