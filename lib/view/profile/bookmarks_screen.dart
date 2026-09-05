import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/place_image.dart';
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
                    return Card(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: Tooltip(
                          message: place.photoGoogleMapsUri == null
                              ? 'Place photo'
                              : 'View photo on Google Maps',
                          child: InkWell(
                            onTap: place.photoGoogleMapsUri == null
                                ? null
                                : () => launchUrl(
                                    Uri.parse(place.photoGoogleMapsUri!),
                                    mode: LaunchMode.externalApplication,
                                  ),
                            borderRadius: BorderRadius.circular(10),
                            child: PlaceImage(
                              imageUrl: place.imageUrl,
                              width: 58,
                              height: 58,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        title: Text(
                          place.placeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (place.category?.trim().isNotEmpty == true)
                              place.category!.trim(),
                            if (place.placeAddress.trim().isNotEmpty)
                              place.placeAddress.trim(),
                            if (place.imageUrl?.trim().isNotEmpty == true)
                              'Photo · Google Maps',
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove bookmark',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                          onPressed: () => _confirmRemove(
                            context,
                            vm,
                            bookmark.id,
                            place.placeName,
                          ),
                        ),
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
        title: const Text('Remove bookmark?'),
        content: Text('Remove $placeName from your bookmarks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await vm.remove(bookmarkId);
  }
}
