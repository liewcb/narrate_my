import 'package:flutter/material.dart';

/// UI layer for UC500: AI Travel Assistant.
///
/// The ViewModel will later replace the local message list with Gemini and
/// Supabase-backed conversation data.
class TravelAssistantScreen extends StatefulWidget {
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
  State<TravelAssistantScreen> createState() => _TravelAssistantScreenState();
}

class _TravelAssistantScreenState extends State<TravelAssistantScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  late List<_ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      const _ChatMessage(
        text: 'Here’s Manja, Your AI Travel Assistant!',
        sender: _MessageSender.assistant,
      ),
    ];
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final question = _inputController.text.trim();

    if (question.isEmpty) {
      setState(() {
        _messages.add(
          const _ChatMessage(
            text: 'Please type a question before sending.',
            sender: _MessageSender.system,
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages.add(
        _ChatMessage(text: question, sender: _MessageSender.tourist),
      );
    });
    _inputController.clear();
    _scrollToBottom();

    // TODO: AITravelAssistantViewModel.sendQuestion(...)
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

    if (shouldReset != true || !mounted) return;

    setState(() {
      _messages = [
        const _ChatMessage(
          text: 'Here’s Manja, Your AI Travel Assistant!',
          sender: _MessageSender.assistant,
        ),
      ];
    });
  }

  void _searchConversation() {
    showSearch<void>(
      context: context,
      delegate: _ConversationSearchDelegate(messages: _messages),
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

  @override
  Widget build(BuildContext context) {
    final attractionName = widget.attractionName?.trim();

    return Scaffold(
      backgroundColor: _TravelAssistantColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (attractionName != null && attractionName.isNotEmpty)
              _buildAttractionContext(attractionName),
            Expanded(child: _buildMessageList()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: _TravelAssistantColors.teal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Travel Assistant',
                  style: TextStyle(
                    color: _TravelAssistantColors.teal,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Search conversation',
            icon: const Icon(Icons.search),
            onPressed: _searchConversation,
          ),
          Container(
            decoration: BoxDecoration(
              color: _TravelAssistantColors.teal,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              tooltip: 'Reset conversation',
              icon: const Icon(Icons.refresh, color: Colors.white),
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
        color: const Color(0xFFE5EFED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8D0CC)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: _TravelAssistantColors.teal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Discussing: ' + attractionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _TravelAssistantColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _ChatBubble(message: _messages[index]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x22000000))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _TravelAssistantColors.bubbleBorder),
              ),
              child: TextField(
                controller: _inputController,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Ask something... (e.g. History of A Famosa)',
                  hintStyle: TextStyle(
                    color: _TravelAssistantColors.hintGray,
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
              onTap: _sendMessage,
              borderRadius: BorderRadius.circular(30),
              child: Ink(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: _TravelAssistantColors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isTourist = message.sender == _MessageSender.tourist;
    final isSystem = message.sender == _MessageSender.system;

    final bubbleColor = isTourist
        ? _TravelAssistantColors.teal
        : isSystem
        ? const Color(0xFFFFE9D7)
        : Colors.white;

    final textColor = isTourist
        ? Colors.white
        : isSystem
        ? const Color(0xFF8A4A23)
        : _TravelAssistantColors.textDark;

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
              : Border.all(color: _TravelAssistantColors.bubbleBorder),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: textColor, fontSize: 16, height: 1.35),
        ),
      ),
    );
  }
}

enum _MessageSender { tourist, assistant, system }

class _ChatMessage {
  const _ChatMessage({required this.text, required this.sender});

  final String text;
  final _MessageSender sender;
}

class _ConversationSearchDelegate extends SearchDelegate<void> {
  _ConversationSearchDelegate({required this.messages});

  final List<_ChatMessage> messages;

  List<_ChatMessage> get _matches {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return const [];

    return messages
        .where((message) => message.text.toLowerCase().contains(keyword))
        .toList();
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        tooltip: 'Clear search',
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Close search',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildMatches();

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches();

  Widget _buildMatches() {
    final matches = _matches;

    if (query.trim().isEmpty) {
      return const Center(
        child: Text('Search messages in this conversation.'),
      );
    }

    if (matches.isEmpty) {
      return const Center(
        child: Text('No matches found in this conversation.'),
      );
    }

    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final message = matches[index];
        return ListTile(
          leading: Icon(
            message.sender == _MessageSender.tourist
                ? Icons.person_outline
                : Icons.smart_toy_outlined,
          ),
          title: Text(message.text),
        );
      },
    );
  }
}

class _TravelAssistantColors {
  static const background = Color(0xFFF6F1E7);
  static const teal = Color(0xFF2E6B67);
  static const orange = Color(0xFFE08A4B);
  static const bubbleBorder = Color(0xFFE3DDCF);
  static const textDark = Color(0xFF1F2E2C);
  static const hintGray = Color(0xFF9B978C);
}
