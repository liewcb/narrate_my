import '../../../core/config/itinerary_constants.dart';
import '../../entities/coordinates.dart';
import './scoring_service.dart';

class _KMeansResult {
  final List<List<ScoredAttraction>> clusters;
  final List<Coordinates> centroids;

  const _KMeansResult({
    required this.clusters,
    required this.centroids,
  });
}

class Cluster {
  final List<ScoredAttraction> attractions;
  final Coordinates center;
  final int dayIndex;
  const Cluster({required this.attractions, required this.center, required this.dayIndex});
  List<ScoredAttraction> get sortedByScore => [...attractions]..sort((a, b) => b.score.compareTo(a.score));
  ScoredAttraction? get anchor => attractions.isNotEmpty ? sortedByScore.first : null;
}

class ClusteringService {
  static const double _convergenceThreshold = 0.001;

  List<Cluster> clusterPlaces({
    required List<ScoredAttraction> scoredPlaces,
    required int numberOfDays,
    String pace = 'Standard',
  }) {
    if (scoredPlaces.isEmpty) return [];
    if (numberOfDays <= 1) {
      return [Cluster(attractions: scoredPlaces, center: _calculateCenter(scoredPlaces), dayIndex: 0)];
    }

    final kMeansResult = _kMeansClustering(scoredPlaces, numberOfDays);
    List<List<ScoredAttraction>> rawClusters = kMeansResult.clusters;

    final int minAttractions = ItineraryConstants.attractionsPerDayFor(pace);
    final int maxAttractions = ItineraryConstants.maxAttractionsPerDay;

    rawClusters = _balanceClusters(rawClusters, minAttractions, maxAttractions);

    return rawClusters.asMap().entries.map((entry) {
      return Cluster(
        attractions: entry.value,
        center: _calculateCenter(entry.value),
        dayIndex: entry.key,
      );
    }).toList();
  }

  /// Pure geographic clustering.
  ///
  /// Groups geographically close candidate places into [clusterCount]
  /// clusters. Cluster indexes are NOT itinerary days — they are context
  /// for DeepSeek, which decides the actual day allocation.
  ///
  /// Must-visit places are always preserved in the cluster nearest to them,
  /// and never dropped by the balancing step.
  List<Cluster> clusterGeographically({
    required List<ScoredAttraction> scoredPlaces,
    required int clusterCount,
  }) {
    if (scoredPlaces.isEmpty) return [];

    final int k = clusterCount.clamp(1, scoredPlaces.length);
    if (k <= 1) {
      return [
        Cluster(
          attractions: List.of(scoredPlaces),
          center: _calculateCenter(scoredPlaces),
          dayIndex: 0,
        ),
      ];
    }

    final result = _kMeansClustering(scoredPlaces, k);
    final rawClusters = result.clusters;
    _ensureNonEmpty(rawClusters, scoredPlaces, result.centroids);

    return rawClusters.asMap().entries.map((entry) {
      return Cluster(
        attractions: entry.value,
        center: _calculateCenter(entry.value),
        dayIndex: entry.key,
      );
    }).toList();
  }

  /// Repairs empty clusters using the actual K-Means centroid.
  /// Must-visit places are never moved by this corrective step.
  void _ensureNonEmpty(
      List<List<ScoredAttraction>> clusters,
      List<ScoredAttraction> scored,
      List<Coordinates> centroids,
      ) {
    for (int i = 0; i < clusters.length; i++) {
      if (clusters[i].isNotEmpty) continue;

      final nearestIdx = _findNearestMovablePlace(
        scored: scored,
        target: centroids[i],
        clusters: clusters,
      );
      if (nearestIdx == -1) continue;

      final place = scored[nearestIdx];
      for (final cluster in clusters) {
        if (cluster.remove(place)) {
          clusters[i].add(place);
          break;
        }
      }
    }
  }

  int _findNearestMovablePlace({
    required List<ScoredAttraction> scored,
    required Coordinates target,
    required List<List<ScoredAttraction>> clusters,
  }) {
    int bestIndex = -1;
    double bestDistance = double.infinity;

    for (int i = 0; i < scored.length; i++) {
      final place = scored[i];
      if (place.isMustVisit) continue;
      if (!clusters.any((cluster) => cluster.contains(place))) continue;

      final distance = place.place.coordinates.distanceTo(target);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  _KMeansResult _kMeansClustering(
      List<ScoredAttraction> scored,
      int k,
      ) {
    if (scored.length <= k) {
      final clusters = List.generate(k, (_) => <ScoredAttraction>[]);
      final centroids = <Coordinates>[];
      for (int i = 0; i < scored.length; i++) {
        clusters[i].add(scored[i]);
        centroids.add(scored[i].place.coordinates);
      }
      while (centroids.length < k) {
        centroids.add(scored.last.place.coordinates);
      }
      return _KMeansResult(clusters: clusters, centroids: centroids);
    }

    var centroids = _initializeCentroids(scored, k);
    var clusters = <List<ScoredAttraction>>[];
    var converged = false;
    var iterations = 0;

    while (!converged && iterations < 50) {
      clusters = List.generate(k, (_) => <ScoredAttraction>[]);
      for (final item in scored) {
        final nearest = _findNearestCentroid(item.place.coordinates, centroids);
        clusters[nearest].add(item);
      }

      final newCentroids = List.generate(k, (index) {
        final c = clusters[index];
        return c.isNotEmpty ? _calculateCenter(c) : centroids[index];
      });

      converged = _centroidsConverged(centroids, newCentroids);
      centroids = newCentroids;
      iterations++;
    }

    return _KMeansResult(clusters: clusters, centroids: centroids);
  }

  List<List<ScoredAttraction>> _balanceClusters(
      List<List<ScoredAttraction>> clusters,
      int min,
      int max,
      ) {
    for (int i = 0; i < clusters.length; i++) {
      if (clusters[i].length >= min) continue;

      final donorIndex = _findBestDonorCluster(
        clusters,
        min,
        excludeIndex: i,
      );
      if (donorIndex == -1) continue;

      final donor = clusters[donorIndex];
      final movableIndex = _findMovableIndex(donor);
      if (movableIndex == -1) continue;

      clusters[i].add(donor.removeAt(movableIndex));
    }
    return clusters;
  }

  int _findBestDonorCluster(
      List<List<ScoredAttraction>> clusters,
      int min, {
        required int excludeIndex,
      }) {
    var bestIndex = -1;
    var bestSize = min;
    for (int i = 0; i < clusters.length; i++) {
      if (i == excludeIndex) continue;
      if (clusters[i].length > bestSize) {
        bestSize = clusters[i].length;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  int _findMovableIndex(List<ScoredAttraction> cluster) {
    for (int i = cluster.length - 1; i >= 0; i--) {
      if (!cluster[i].isMustVisit) return i;
    }
    return -1;
  }

  Coordinates _calculateCenter(List<ScoredAttraction> cluster) {
    if (cluster.isEmpty) return const Coordinates(latitude: 0, longitude: 0);
    double lat = cluster.map((e) => e.place.coordinates.latitude).reduce((a, b) => a + b) / cluster.length;
    double lng = cluster.map((e) => e.place.coordinates.longitude).reduce((a, b) => a + b) / cluster.length;
    return Coordinates(latitude: lat, longitude: lng);
  }

  List<Coordinates> _initializeCentroids(List<ScoredAttraction> scored, int k) {
    return scored.take(k).map((e) => e.place.coordinates).toList();
  }

  int _findNearestCentroid(Coordinates p, List<Coordinates> centroids) {
    int best = 0; double min = double.infinity;
    for (int i = 0; i < centroids.length; i++) {
      double d = p.distanceTo(centroids[i]);
      if (d < min) { min = d; best = i; }
    }
    return best;
  }

  bool _centroidsConverged(List<Coordinates> c1, List<Coordinates> c2) {
    for (int i = 0; i < c1.length; i++) if (c1[i].distanceTo(c2[i]) > _convergenceThreshold) return false;
    return true;
  }

  int _findNearestPlaceToCentroid(List<ScoredAttraction> scored, Coordinates c) {
    int best = -1; double min = double.infinity;
    for (int i = 0; i < scored.length; i++) {
      double d = scored[i].place.coordinates.distanceTo(c);
      if (d < min) { min = d; best = i; }
    }
    return best;
  }
}
