import 'package:flutter/material.dart';

import '../../view/Itinerary/my_itineraries_screen.dart';


final Map<String, WidgetBuilder> itineraryRoutes = {
  // Main list (bottom-nav tab)
  '/itinerary': (_) => const MyItinerariesScreen(),

  // NOTE: '/itinerary/add-custom-stop' was removed — AddCustomStopScreen now
  // requires runtime parameters (itineraryId, dayIndex, ...) and is
  // navigated to directly from ManageDisplayPlanScreen._openAddPlace().
};
