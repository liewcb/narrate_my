import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/services/database_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/dto/bookmark_with_place_dto.dart';
import '../../../model/repositories/interfaces/bookmark_repository.dart';

class AddFromBookmarksScreen extends StatefulWidget {
  final String userId;

  const AddFromBookmarksScreen({super.key, required this.userId});

  @override
  State<AddFromBookmarksScreen> createState() => _AddFromBookmarksScreenState();
}

class _AddFromBookmarksScreenState extends State<AddFromBookmarksScreen> {
  final BookmarkRepository _repo = DatabaseManager().bookmarkRepository;

  List<BookmarkWithPlaceDTO> _bookmarks = [];
  final Set<String> _selectedPlaceIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _bookmarks = await _repo.getBookmarksWithPlaces(widget.userId);
    } catch (_) {
      _bookmarks = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _toggleSelection(String placeId) {
    setState(() {
      if (_selectedPlaceIds.contains(placeId)) {
        _selectedPlaceIds.remove(placeId);
      } else {
        _selectedPlaceIds.add(placeId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(
              top: 100, left: 20, right: 20, bottom: 140,
            ),
            children: [
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_bookmarks.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Text(
                      'No bookmarks yet.\nSave places you want to visit!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              else
                ..._bookmarks.map((dto) => _buildBookmarkCard(dto)),
            ],
          ),
          _buildStickyFooter(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            backgroundColor: AppColors.bg.withOpacity(0.9),
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.ink),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: Text("Add from bookmarks",
                style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink,
                )),
            centerTitle: false,
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkCard(BookmarkWithPlaceDTO dto) {
    final place = dto.place;
    final bool isChecked = _selectedPlaceIds.contains(place.placeId);
    final photoUrl = place.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=200&photoreference=${place.photoReference}'
        : null;
    final subtitle = place.types.isNotEmpty ? place.types.first : 'Place';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => _toggleSelection(place.placeId),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64, height: 64,
                  color: AppColors.moduleBorder,
                  child: photoUrl != null
                      ? Image.network(photoUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.moduleBorder,
                            child: const Icon(Icons.image_not_supported, size: 24),
                          ),
                        )
                      : const Icon(Icons.place, size: 24, color: AppColors.inkFaint),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.name,
                        style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink,
                        )),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(fontSize: 14, color: AppColors.inkFaint)),
                    if (place.rating > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(place.rating.toStringAsFixed(1),
                              style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isChecked ? AppColors.green : Colors.transparent,
                  border: Border.all(
                    color: isChecked ? AppColors.green : AppColors.moduleBorder,
                    width: 2,
                  ),
                ),
                child: isChecked
                    ? const Icon(Icons.check, size: 16, color: AppColors.surface)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyFooter() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: AppColors.bg.withOpacity(0.9),
              border: Border(top: BorderSide(color: AppColors.moduleBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedPlaceIds.isNotEmpty
                        ? () => Navigator.pop(context, _selectedPlaceIds.toList())
                        : null,
                    child: Text('Add ${_selectedPlaceIds.length} Places'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}