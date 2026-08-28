import 'dart:math';
import 'package:flutter/cupertino.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../entities/coordinates.dart';
import 'candidate_retrieval_service.dart';
import 'scoring_service.dart';

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
  final Random _random = Random();

  List<Cluster> clusterPlaces({
    required List<ScoredAttraction> scoredPlaces,
    required int numberOfDays,
    String pace = 'Standard',
  }) {
    if (scoredPlaces.isEmpty) return [];
    if (numberOfDays <= 1) {
      return [Cluster(attractions: scoredPlaces, center: _calculateCenter(scoredPlaces), dayIndex: 0)];
    }

    List<List<ScoredAttraction>> rawClusters = _kMeansClustering(scoredPlaces, numberOfDays);

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

  List<List<ScoredAttraction>> _kMeansClustering(List<ScoredAttraction> scored, int k) {
    if (scored.length <= k) {
      final clusters = List.generate(k, (_) => <ScoredAttraction>[]);
      for (int i = 0; i < scored.length; i++) clusters[i].add(scored[i]);
      return clusters;
    }

    List<Coordinates> centroids = _initializeCentroids(scored, k);
    List<List<ScoredAttraction>> clusters = [];
    bool converged = false;
    int iterations = 0;

    while (!converged && iterations < 50) {
      clusters = List.generate(k, (_) => []);
      for (final item in scored) {
        int nearest = _findNearestCentroid(item.place.coordinates, centroids);
        clusters[nearest].add(item);
      }
      List<Coordinates> newCentroids = clusters.map((c) => c.isNotEmpty ? _calculateCenter(c) : centroids[clusters.indexOf(c)]).toList();
      converged = _centroidsConverged(centroids, newCentroids);
      centroids = newCentroids;
      iterations++;
    }

    // FIX: Robust Empty Cluster Correction
    for (int i = 0; i < clusters.length; i++) {
      if (clusters[i].isEmpty) {
        final nearestIdx = _findNearestPlaceToCentroid(scored, centroids[i]);
        if (nearestIdx != -1) {
          final place = scored[nearestIdx];
          for (var c in clusters) {
            if (c.contains(place)) {
              c.remove(place);
              clusters[i].add(place);
              break;
            }
          }
        }
      }
    }
    return clusters;
  }

  List<List<ScoredAttraction>> _balanceClusters(List<List<ScoredAttraction>> clusters, int min, int max) {
    // Basic balancing logic to ensure no cluster is empty and none exceed max significantly
    for (int i = 0; i < clusters.length; i++) {
      if (clusters[i].length < min) {
        // Try to steal from largest cluster
        int largestIdx = 0;
        for (int j = 1; j < clusters.length; j++) {
          if (clusters[j].length > clusters[largestIdx].length) largestIdx = j;
        }
        if (clusters[largestIdx].length > min) {
          final toMove = clusters[largestIdx].removeAt(0);
          clusters[i].add(toMove);
        }
      }
    }
    return clusters;
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
