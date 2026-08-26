enum AiChatMessageSender { tourist, assistant, system }

/// A display-ready message in the current AI chat session.
///
/// This is intentionally independent from the future Supabase DTO so the View
/// and ViewModel do not need to know the database JSON shape.
class AiChatMessage {
  AiChatMessage({
    required this.text,
    required this.sender,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String text;
  final AiChatMessageSender sender;
  final DateTime createdAt;
}
