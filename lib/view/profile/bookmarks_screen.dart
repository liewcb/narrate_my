import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/google_maps_directions_button.dart';
import '../../core/widgets/place_image.dart';
import '../../model/entities/place.dart';
import '../../viewmodel/profile_viewmodel/bookmarks_vm.dart';

/// UC402 A22 (View and Delete Bookmarks, REQ_503_21/22). Viewing the
/// bookmarked attraction's own detail page (step 4) isn't wired up here —
/// that's the AR/Itinerary modules' screen to own; this only lists the
/// bookmark records Module 5 is responsible for (view + remove).
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookmarksVm()..load(),
      child: const _BookmarksView(),
    );
  }
}

class _BookmarksView extends StatelessWidget {
  const _BookmarksView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookmarksVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.bookmarks'))),
      body: SafeArea(
        child: vm.isLoading
            ? const Center(child: CircularProgressIndicator())
            : vm.bookmarks.isEmpty
            ? Center(
                child: Text(
                  vm.errorMessage ?? AppLocalizations.t('ui.noBookmarksYet'),
                  style: const TextStyle(color: AppColors.inkFaint),
                ),
              )
            : RefreshIndicator(
                onRefresh: vm.load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: vm.bookmarks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final entry = vm.bookmarks[i];
                    final bookmark = entry.bookmark;
                    final place = entry.place;
                    return _BookmarkCard(
                      place: place,
                      onRemove: () => _confirmRemove(
                        context,
                        vm,
                        bookmark.id,
                        place.placeName,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    BookmarksVm vm,
    String bookmarkId,
    String placeName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.t('ui.removeBookmarkTitle')),
        content: Text(
          AppLocalizations.t(
            'ui.removeBookmarkMessage',
          ).replaceFirst('{place}', placeName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.t('ui.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.t('ui.remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await vm.remove(bookmarkId);
  }
}

class _BookmarkCard extends StatefulWidget {
  final Place place;
  final VoidCallback onRemove;

  const _BookmarkCard({required this.place, required this.onRemove});

  @override
  State<_BookmarkCard> createState() => _BookmarkCardState();
}

class _BookmarkCardState extends State<_BookmarkCard> {
  bool _isExpanded = false;

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final category = place.category?.trim();
    final address = place.placeAddress.trim();

    return Card(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  PlaceImage(
                    imageUrl: place.imageUrl,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      place.placeName,
                      maxLines: _isExpanded ? null : 2,
                      overflow: _isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.t('ui.removeBookmarkTooltip'),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                    ),
                    onPressed: widget.onRemove,
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        if (category?.isNotEmpty == true) ...[
                          Text(
                            category!,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (address.isNotEmpty) ...[
                          Text(
                            AppLocalizations.t('ui.address'),
                            style: const TextStyle(
                              color: AppColors.inkFaint,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(address),
                          const SizedBox(height: 16),
                        ],
                        GoogleMapsDirectionsButton(
                          destinationName: place.placeName,
                          latitude: place.placeLatitude,
                          longitude: place.placeLongitude,
                          googlePlaceId:
                              place.placeId.startsWith('narratemy-ar-')
                              ? null
                              : place.placeId,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
