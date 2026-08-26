import 'package:flutter/material.dart';

/// Legacy modal placeholder (manual language switching is replaced by automatic Supabase profile preferred_language)
class TTSLanguageModal extends StatelessWidget {
  const TTSLanguageModal({super.key});

  static void show(BuildContext context) {}

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
