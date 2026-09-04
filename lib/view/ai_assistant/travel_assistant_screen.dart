import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../model/entities/ai_attraction_context.dart';
import '../../model/entities/ai_chat_message.dart';
import '../../model/entities/place.dart';
import '../../viewmodel/ai_assistant/ai_travel_assistant_vm.dart';
import '../../viewmodel/bookmark_vm.dart';
import '../profile/auth/login_screen.dart';

/// UC500 chat screen. Gemini is called securely through a Supabase Edge
/// Function; no Gemini key exists in Flutter code.
class TravelAssistantScreen extends StatelessWidget {
  const TravelAssistantScreen({
    super.key,
    this.attractionId,
    this.attractionName,
    this.contextSource = 'none',
    this.bookmarkPlace,
  });

  final String? attractionId;
  final String? attractionName;
  final String contextSource;

  /// A verified place supplied by Recommendation or Itinerary. Gemini text is
  /// never used to invent a bookmark target.
  final Place? bookmarkPlace;

  @override
  Widget build(BuildContext context) {
    final cleanId = attractionId?.trim();
    final cleanName = attractionName?.trim();
    final placeId = bookmarkPlace?.placeId.trim();
    final placeName = bookmarkPlace?.placeName.trim();
    final resolvedAttractionId = cleanId?.isNotEmpty == true
        ? cleanId
        : placeId;
    final resolvedAttractionName = cleanName?.isNotEmpty == true
        ? cleanName
        : placeName;
    final hasContext =
        (resolvedAttractionId?.isNotEmpty ?? false) ||
        (resolvedAttractionName?.isNotEmpty ?? false);

    return ChangeNotifierProvider(
      create: (_) => AiTravelAssistantViewModel(
        initialContext: hasContext
            ? AiAttractionContext(
                attractionId: resolvedAttractionId,
                attractionName: resolvedAttractionName,
                source: contextSource,
              )
            : null,
        resolveBookmarkPlacesFromQuestions: bookmarkPlace == null,
      ),
      child: _TravelAssistantView(bookmarkPlace: bookmarkPlace),
    );
  }
}

class _TravelAssistantView extends StatefulWidget {
  const _TravelAssistantView({this.bookmarkPlace});

  final Place? bookmarkPlace;

  @override
  State<_TravelAssistantView> createState() => _TravelAssistantViewState();
}

class _TravelAssistantViewState extends State<_TravelAssistantView> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _allowPop = false;
  bool _leaveDialogOpen = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final question = _inputController.text.trim();
    if (question.isNotEmpty) _inputController.clear();

    await context.read<AiTravelAssistantViewModel>().sendQuestion(question);
    if (!mounted) return;
    _scrollToBottom();
  }

  Future<void> _resetConversation() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset conversation?'),
        content: const Text(
          'Your current chat messages and attraction context will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (shouldReset == true && mounted) {
      context.read<AiTravelAssistantViewModel>().resetConversation();
    }
  }

  Future<void> _confirmLeave() async {
    if (_allowPop || _leaveDialogOpen) return;
    _leaveDialogOpen = true;
    final shouldLeave = await showConfirmationDialog(
      context: context,
      title: 'Leave AI chat?',
      message:
          'Your current conversation will be cleared when you leave. '
          'Are you sure you want to continue?',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
      confirmColor: AppColors.primary,
      icon: Icons.exit_to_app_rounded,
      iconBgColor: AppColors.accentSoft,
      iconColor: AppColors.primary,
    );
    _leaveDialogOpen = false;

    if (shouldLeave == true && mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  void _searchConversation(List<AiChatMessage> messages) {
    showSearch<void>(
      context: context,
      delegate: _ConversationSearchDelegate(messages: messages),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _openSummary(AiTravelAssistantViewModel vm) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: const _ConversationSummarySheet(),
      ),
    );
    vm.generateSummary();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiTravelAssistantViewModel>();
    final attractionName = vm.attractionContext?.attractionName?.trim();

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(vm),
              if (attractionName != null && attractionName.isNotEmpty)
                _buildAttractionContext(attractionName),
              Expanded(child: _buildMessageList(vm, widget.bookmarkPlace)),
              _buildInputBar(vm.isSending || vm.isSummarizing),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AiTravelAssistantViewModel vm) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.moduleBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: _confirmLeave,
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Show conversation summary',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: vm.isSending || vm.isSummarizing
                    ? null
                    : () => _openSummary(vm),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            color: AppColors.surface,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Travel Assistant',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Search conversation',
            icon: const Icon(Icons.search),
            onPressed: () => _searchConversation(vm.messages),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              tooltip: 'Reset conversation',
              icon: const Icon(Icons.refresh, color: AppColors.surface),
              onPressed: _resetConversation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttractionContext(String attractionName) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.moduleBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Discussing: $attractionName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    AiTravelAssistantViewModel vm,
    Place? bookmarkPlace,
  ) {
    final latestAssistantIndex = vm.messages.lastIndexWhere(
      (message) => message.sender == AiChatMessageSender.assistant,
    );
    final suppliedBookmarkTarget =
        bookmarkPlace != null && bookmarkPlace.placeId.trim().isNotEmpty
        ? <Place>[bookmarkPlace]
        : const <Place>[];
    final bookmarkTargets = suppliedBookmarkTarget.isNotEmpty
        ? suppliedBookmarkTarget
        : vm.bookmarkCandidates;
    final latestTouristIndex = vm.messages.lastIndexWhere(
      (message) => message.sender == AiChatMessageSender.tourist,
    );
    final latestTouristQuestion = latestTouristIndex < 0
        ? null
        : vm.messages[latestTouristIndex].text;
    final mapDestination = _mapDestinationFromQuestion(latestTouristQuestion);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: vm.messages.length + (vm.isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == vm.messages.length) return const _TypingBubble();

        final message = vm.messages[index];
        final showBookmarkAction =
            bookmarkTargets.isNotEmpty &&
            !vm.isSending &&
            message.sender == AiChatMessageSender.assistant &&
            index == latestAssistantIndex &&
            vm.messages.any(
              (item) => item.sender == AiChatMessageSender.tourist,
            );
        final showMapAction =
            mapDestination != null &&
            !vm.isSending &&
            message.sender == AiChatMessageSender.assistant &&
            index == latestAssistantIndex;

        return _ChatBubble(
          message: message,
          bookmarkPlaces: showBookmarkAction
              ? bookmarkTargets
              : const <Place>[],
          isResolvingPlaces:
              message.sender == AiChatMessageSender.assistant &&
              index == latestAssistantIndex &&
              vm.isResolvingBookmarkPlaces,
          mapDestination: showMapAction ? mapDestination : null,
          mapPlace: showMapAction && bookmarkTargets.length == 1
              ? bookmarkTargets.single
              : null,
        );
      },
    );
  }

  String? _mapDestinationFromQuestion(String? question) {
    if (question == null) return null;
    final normalized = question.trim().toLowerCase();
    final isMapRequest = RegExp(
      r"\bwhere(?:'s|\s+is)\b|\bdirections?\b|\bnavigate\b|"
      r'\broute\s+to\b|\bhow\s+(?:do|can)\s+i\s+get\s+to\b',
    ).hasMatch(normalized);
    if (!isMapRequest) return null;

    var destination = question.trim();
    final prefixes = <RegExp>[
      RegExp(r"^where(?:'s|\s+is)\s+(?:the\s+)?", caseSensitive: false),
      RegExp(r'^how\s+(?:do|can)\s+i\s+get\s+to\s+', caseSensitive: false),
      RegExp(
        r'^(?:can\s+you\s+)?(?:show|give)\s+(?:me\s+)?directions?\s+to\s+',
        caseSensitive: false,
      ),
      RegExp(r'^(?:navigate|route)\s+(?:me\s+)?to\s+', caseSensitive: false),
    ];
    for (final prefix in prefixes) {
      destination = destination.replaceFirst(prefix, '');
    }
    destination = destination.replaceAll(RegExp(r'[?!.]+$'), '').trim();
    return destination.isEmpty ? question.trim() : destination;
  }

  Widget _buildInputBar(bool isSending) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _inputController,
                enabled: !isSending,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Ask something... (e.g. History of A Famosa)',
                  hintStyle: TextStyle(color: AppColors.inkFaint, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Send question',
            child: InkWell(
              onTap: isSending ? null : _sendMessage,
              borderRadius: BorderRadius.circular(30),
              child: Ink(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSending ? AppColors.inkFaint : AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: isSending
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      )
                    : const Icon(Icons.arrow_upward, color: AppColors.surface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only overlay. It displays Gemini's recap but has no editable field,
/// save action, or edit action.
class _ConversationSummarySheet extends StatelessWidget {
  const _ConversationSummarySheet();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiTravelAssistantViewModel>();
    final screenHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      top: false,
      child: Container(
        height: screenHeight * 0.58,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.inkFaint,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Summary',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close summary',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _buildSummaryContent(context, vm)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryContent(
    BuildContext context,
    AiTravelAssistantViewModel vm,
  ) {
    if (vm.isSummarizing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.summaryErrorMessage != null) {
      return Center(
        child: Text(
          vm.summaryErrorMessage!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.accentDark, fontSize: 16),
        ),
      );
    }

    final summary = vm.conversationSummary;
    if (summary == null || summary.isEmpty) {
      return const Center(
        child: Text(
          'No conversation summary is available yet.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(22),
      ),
      child: SingleChildScrollView(
        child: _SimpleMarkdownText(
          text: summary,
          style: const TextStyle(
            color: AppColors.inkSoft,
            fontSize: 17,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// Small renderer for the subset of Markdown returned by the assistant.
/// It supports **bold text** and `*`/`-` bullet lines without adding another
/// package to the application.
class _SimpleMarkdownText extends StatelessWidget {
  const _SimpleMarkdownText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final normalizedText = text.replaceAllMapped(
      RegExp(r'^\s*[\*-]\s+', multiLine: true),
      (_) => '• ',
    );
    final boldPattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in boldPattern.allMatches(normalizedText)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: normalizedText
                .substring(cursor, match.start)
                .replaceAll('**', ''),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: style.copyWith(fontWeight: FontWeight.w700),
        ),
      );
      cursor = match.end;
    }

    if (cursor < normalizedText.length) {
      spans.add(
        TextSpan(text: normalizedText.substring(cursor).replaceAll('**', '')),
      );
    }

    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    this.bookmarkPlaces = const [],
    this.isResolvingPlaces = false,
    this.mapDestination,
    this.mapPlace,
  });

  final AiChatMessage message;
  final List<Place> bookmarkPlaces;
  final bool isResolvingPlaces;
  final String? mapDestination;
  final Place? mapPlace;

  @override
  Widget build(BuildContext context) {
    final isTourist = message.sender == AiChatMessageSender.tourist;
    final isSystem = message.sender == AiChatMessageSender.system;
    final bubbleColor = isTourist
        ? AppColors.primary
        : isSystem
        ? AppColors.accentSoft
        : AppColors.surface;
    final textColor = isTourist
        ? AppColors.surface
        : isSystem
        ? AppColors.accentDark
        : AppColors.ink;

    return Align(
      alignment: isTourist ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18),
          border: isTourist ? null : Border.all(color: AppColors.moduleBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SimpleMarkdownText(
              text: message.text,
              style: TextStyle(color: textColor, fontSize: 16, height: 1.35),
            ),
            if (isResolvingPlaces) ...[
              const SizedBox(height: 12),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Checking verified places…',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
                ],
              ),
            ],
            if (mapDestination != null) ...[
              const SizedBox(height: 12),
              _GoogleMapsButton(destination: mapDestination!, place: mapPlace),
            ],
            if (bookmarkPlaces.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AiBookmarkPlaces(places: bookmarkPlaces),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoogleMapsButton extends StatelessWidget {
  const _GoogleMapsButton({required this.destination, this.place});

  final String destination;
  final Place? place;

  Uri get _directionsUri {
    final resolvedPlace = place;
    final hasCoordinates =
        resolvedPlace != null &&
        resolvedPlace.placeLatitude != 0 &&
        resolvedPlace.placeLongitude != 0;
    final parameters = <String, String>{
      'api': '1',
      'destination': hasCoordinates
          ? '${resolvedPlace.placeLatitude},${resolvedPlace.placeLongitude}'
          : destination,
    };
    final googlePlaceId = resolvedPlace?.placeId.trim();
    if (googlePlaceId != null && googlePlaceId.startsWith('ChIJ')) {
      parameters['destination_place_id'] = googlePlaceId;
    }
    return Uri.https('www.google.com', '/maps/dir/', parameters);
  }

  Future<void> _openGoogleMaps(BuildContext context) async {
    final opened = await launchUrl(
      _directionsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      link: true,
      label: 'Open directions to $destination in Google Maps',
      child: OutlinedButton.icon(
        onPressed: () => _openGoogleMaps(context),
        icon: const Icon(Icons.directions_rounded, size: 18),
        label: const Text('Open in Google Maps'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

class _AiBookmarkPlaces extends StatelessWidget {
  const _AiBookmarkPlaces({required this.places});

  final List<Place> places;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          places.length == 1 ? 'Verified place' : 'Choose a verified place',
          style: const TextStyle(
            color: AppColors.inkSoft,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < places.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          ChangeNotifierProvider(
            key: ValueKey(places[index].placeId),
            create: (_) => BookmarkVm()..load(places[index].placeId),
            child: _AiBookmarkPlaceCard(place: places[index]),
          ),
        ],
      ],
    );
  }
}

class _AiBookmarkPlaceCard extends StatelessWidget {
  const _AiBookmarkPlaceCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.moduleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            place.placeName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (place.placeAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              place.placeAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
            ),
          ],
          const SizedBox(height: 7),
          _AiBookmarkButton(place: place),
        ],
      ),
    );
  }
}

class _AiBookmarkButton extends StatelessWidget {
  const _AiBookmarkButton({required this.place});

  final Place place;

  String get _itemType {
    final category = place.category?.trim().toLowerCase();
    if (category == 'restaurant' || place.placeTypes.contains('restaurant')) {
      return 'restaurant';
    }
    return 'attraction';
  }

  Future<void> _onPressed(BuildContext context, BookmarkVm vm) async {
    final result = await vm.toggleBookmark(place, itemType: _itemType);
    if (!context.mounted || result != BookmarkResult.loginRequired) return;

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log in to bookmark'),
        content: const Text(
          'You need to log in before you can save this place to your bookmarks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log in'),
          ),
        ],
      ),
    );

    if (shouldLogin != true) {
      vm.clearPendingBookmark();
      return;
    }

    if (!context.mounted) return;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(returnOnSuccess: true),
      ),
    );
    if (loggedIn == true && context.mounted) {
      await vm.retryPendingBookmark();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookmarkVm>();
    final isLoading = vm.isChecking || vm.isSaving;
    final isBookmarked = vm.isBookmarked;
    final color = isBookmarked ? AppColors.accentDark : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: isBookmarked
              ? 'Remove ${place.placeName} from bookmarks'
              : 'Bookmark ${place.placeName}',
          child: TextButton.icon(
            onPressed: isLoading ? null : () => _onPressed(context, vm),
            style: TextButton.styleFrom(
              foregroundColor: color,
              backgroundColor: AppColors.accentSoft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: const StadiumBorder(),
            ),
            icon: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    isBookmarked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 18,
                  ),
            label: Text(
              isBookmarked ? 'Bookmarked' : 'Bookmark',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (vm.statusMessage != null) ...[
          const SizedBox(height: 7),
          Text(
            vm.statusMessage!,
            style: TextStyle(
              color: vm.errorMessage == null
                  ? AppColors.primary
                  : AppColors.error,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.moduleBorder),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ConversationSearchDelegate extends SearchDelegate<void> {
  _ConversationSearchDelegate({required this.messages});

  final List<AiChatMessage> messages;

  List<AiChatMessage> get _matches {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return const [];
    return messages
        .where((message) => message.text.toLowerCase().contains(keyword))
        .toList();
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      tooltip: 'Clear search',
      icon: const Icon(Icons.clear),
      onPressed: () => query = '',
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Close search',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildMatches();

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches();

  Widget _buildMatches() {
    final matches = _matches;
    if (query.trim().isEmpty) {
      return const Center(child: Text('Search messages in this conversation.'));
    }
    if (matches.isEmpty) {
      return const Center(
        child: Text('No matches found in this conversation.'),
      );
    }
    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final message = matches[index];
        return ListTile(
          leading: Icon(
            message.sender == AiChatMessageSender.tourist
                ? Icons.person_outline
                : Icons.smart_toy_outlined,
          ),
          title: Text(message.text),
        );
      },
    );
  }
}
