import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

/// Streams the device's live pitch (tilt up/down), derived from the
/// accelerometer. Used alongside [compass heading] so the AR scene knows
/// not just *which way* the phone is turned, but whether it's actually
/// being held up level at the horizon at all.
///
/// Convention (matches holding the phone upright in portrait, back
/// camera facing forward — the normal AR pose):
///   0°   = held vertically, camera pointing at the horizon.
///   +90° = tilted so the camera points at the sky (screen facing you,
///          tipped backward).
///   -90° = tilted so the camera points at the ground (screen facing
///          away/down).
class OrientationService {
  /// Returns a broadcast stream of pitch in degrees, smoothed slightly
  /// to avoid jitter from raw accelerometer noise.
  Stream<double> get pitchStream {
    double? smoothed;
    return accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .map((event) => _pitchDegrees(event.x, event.y, event.z))
        .map((raw) {
      // Simple exponential smoothing — enough to stop the overlay from
      // flickering near the tolerance boundary without adding noticeable
      // lag when the tourist actually tilts the phone.
      smoothed = smoothed == null ? raw : (smoothed! * 0.8 + raw * 0.2);
      return smoothed!;
    });
  }

  double _pitchDegrees(double x, double y, double z) {
    // Standard device-frame accelerometer axes: X = right, Y = up (along
    // the screen), Z = out of the screen toward the user. Held upright
    // (portrait, camera pointing at the horizon) gravity reads almost
    // entirely on Y; tipping the camera toward the sky or ground rotates
    // that reading onto Z.
    final radians = math.atan2(-z, math.sqrt(x * x + y * y));
    return radians * (180.0 / math.pi);
  }
}