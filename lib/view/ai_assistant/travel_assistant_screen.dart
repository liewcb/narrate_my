import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/entities/ai_attraction_context.dart';
import '../../model/entities/ai_chat_message.dart';
import '../../viewmodel/ai_assistant/ai_travel_assistant_view_model.dart';

/// UC500 chat screen. Gemini is called securely through a Supabase Edge
/// Function; no Gemini key exists in Flutter code.
class TravelAssistantScreen extends StatelessWidget {
  const TravelAssistantScreen({
    super.key,
    this.attractionId,
    this.attractionName,
    this.contextSource = 'none',
  });

  final String? attractionId;
  final String? attractionName;
  final String contextSource;

  @override
  Widget build(BuildContext context) {
    final cleanName = attractionName?.trim();
    final hasContext = attractionId != null || (cleanName?.isNotEmpty ?? false);

    return ChangeNotifierProvider(
      create: (_) => AiTravelAssistantViewModel(
        initialContext: hasContext
            ? AiAttractionContext(
          attractionId: attractionId,
          attractionName: cleanName,
          source: contextSource,
        )
            : null,
      ),
      child: const _TravelAssistantView(),
    );
  }
}

class _TravelAssistantView extends StatefulWidget {
  const _TravelAssistantView();

  @override
  State<_TravelAssistantView> createState() => _TravelAssistantViewState();
}

class _TravelAssistantViewState extends State<_TravelAssistantView> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

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

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(vm),
            if (attractionName != null && attractionName.isNotEmpty)
              _buildAttractionContext(attractionName),
            Expanded(child: _buildMessageList(vm)),
            _buildInputBar(vm.isSending || vm.isSummarizing),
          ],
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
            onPressed: () => Navigator.of(context).maybePop(),
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
          const Icon(
            Icons.location_on_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Discussing: ' + attractionName,
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

  Widget _buildMessageList(AiTravelAssistantViewModel vm) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: vm.messages.length + (vm.isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == vm.messages.length) return const _TypingBubble();
        return _ChatBubble(message: vm.messages[index]);
      },
    );
  }

  Widget _buildInputBar(bool isSending) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.moduleBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.moduleBorder),
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
                  hintStyle: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 15,
                  ),
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
                  color: isSending
                      ? AppColors.inkFaint
                      : AppColors.accent,
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
        child: Text(
          summary,
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final AiChatMessage message;

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
          border: isTourist
              ? null
              : Border.all(color: AppColors.moduleBorder),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: textColor, fontSize: 16, height: 1.35),
        ),
      ),
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
      return const Center(child: Text('No matches found in this conversation.'));
    }
    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
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

