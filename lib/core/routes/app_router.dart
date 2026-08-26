import 'package:flutter/material.dart';
import 'app_routes.dart';
import 'itinerary_routes.dart';

/// Central route table for the whole app.
///
/// Each module contributes its own map (e.g. [itineraryRoutes]) and gets
/// merged here, so adding a module only means spreading its routes in.
class AppRouter {
  static const String initialRoute = '/';

  static final Map<String, WidgetBuilder> routes = {
    // Bottom-nav shell (AR / Itinerary / Nearby / Profile tabs)
    '/': (_) => const AppRoutes(),
    ...itineraryRoutes,
  };
}
