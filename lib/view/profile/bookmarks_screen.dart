import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/entities/bookmark.dart';
import '../../viewmodel/profile/bookmarks_vm.dart';

/// UC402 A22 (View and Delete Bookmarks, REQ_503_21/22). Viewing the
/// bookmarked attraction's own detail page (step 4) isn't wired up here —
/// that's the AR/Itinerary modules' screen to own; this only lists the
/// bookmark records Module 5 is responsible for (view + remove).
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookmarksVm(),
      child: const _BookmarksView(),
    );
  }
}

class _BookmarksView extends StatelessWidget {
  const _BookmarksView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookmarksVm>();
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: SafeArea(
        child: vm.isLoading
            ? const Center(child: CircularProgressIndicator())
            : vm.bookmarks.isEmpty
                ? Center(
                    child: Text(
                      vm.errorMessage ?? 'No bookmarks yet.',
                      style: const TextStyle(color: AppColors.inkFaint),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: vm.load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: vm.bookmarks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final Bookmark b = vm.bookmarks[i];
                        return Card(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: ListTile(
                            leading: Icon(
                              b.itemType == 'restaurant' ? Icons.restaurant : Icons.place_outlined,
                              color: AppColors.accent,
                            ),
                            title: Text(b.itemType[0].toUpperCase() + b.itemType.substring(1)),
                            subtitle: Text(b.itemId, style: const TextStyle(fontSize: 11)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: () => vm.remove(b.id),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
