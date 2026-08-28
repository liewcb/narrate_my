import 'package:flutter/material.dart';

import '../../view/Itinerary/manage_itinerary/add_custom_screen.dart';
import '../../view/Itinerary/my_itineraries_screen.dart';


final Map<String, WidgetBuilder> itineraryRoutes = {
  // Main list (bottom-nav tab)
  '/itinerary': (_) => const MyItinerariesScreen(),

  // Adding a custom stop to a generated itinerary
  '/itinerary/add-custom-stop': (_) => const AddCustomStopScreen(),
};
