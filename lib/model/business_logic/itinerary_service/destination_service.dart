import '../../entities/destination.dart';
import '../../repositories/interfaces/destination_repository.dart';

/// Use case for getting all destinations.
class GetAllDestinationsUseCase {
  final DestinationRepository _repository;

  const GetAllDestinationsUseCase(this._repository);

  /// Execute the use case
  Future<List<Destination>> execute() async {
    return await _repository.getAllDestinations();
  }
}

// ============================================================
// USE CASE 2: Search Destinations
// ============================================================

/// Use case for searching destinations by name.
class SearchDestinationsUseCase {
  final DestinationRepository _repository;

  const SearchDestinationsUseCase(this._repository);

  /// Execute the use case
  Future<List<Destination>> execute(String query) async {
    if (query.isEmpty) {
      return await _repository.getAllDestinations();
    }
    return await _repository.searchDestinations(query);
  }
}

// ============================================================
// USE CASE 3: Get Popular Destinations
// ============================================================

/// Use case for getting popular destinations.
class GetPopularDestinationsUseCase {
  final DestinationRepository _repository;

  const GetPopularDestinationsUseCase(this._repository);

  /// Execute the use case
  Future<List<Destination>> execute({int limit = 6}) async {
    return await _repository.getPopularDestinations(limit: limit);
  }
}