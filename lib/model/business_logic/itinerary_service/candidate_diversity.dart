/// Related Google types represent one activity, not multiple interest matches.
class CandidateDiversity {
  static const worshipTypes = {
    'place_of_worship',
    'church',
    'hindu_temple',
    'mosque',
    'synagogue',
  };

  static String groupFor(Iterable<String> types) {
    final values = types.map((t) => t.toLowerCase()).toSet();
    if (values.contains('museum')) return 'museum';
    if (values.contains('art_gallery')) return 'gallery';
    if (values.any(worshipTypes.contains)) return 'worship';
    if (values.contains('shopping_mall')) return 'mall';
    if (values.any(
      const {
        'clothing_store',
        'department_store',
        'book_store',
        'jewelry_store',
        'supermarket',
        'market',
      }.contains,
    )) {
      return 'shopping';
    }
    if (values.any(
      const {
        'park',
        'national_park',
        'natural_feature',
        'botanical_garden',
        'hiking_area',
      }.contains,
    )) {
      return 'nature';
    }
    if (values.any(const {'zoo', 'aquarium'}.contains)) return 'wildlife';
    if (values.contains('tourist_attraction')) return 'landmark';
    return values
            .where((t) => t != 'point_of_interest' && t != 'establishment')
            .firstOrNull ??
        'other';
  }
}
