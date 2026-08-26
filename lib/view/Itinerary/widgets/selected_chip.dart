import 'package:flutter/material.dart';

/// A removable chip that represents a selected destination.
/// Built on Flutter's [InputChip] for built-in accessibility
/// and theming support.
class SelectedChip extends StatelessWidget {
  const SelectedChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      selected: true,
      showCheckmark: false,
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 16),
      onPressed: onRemove, // tapping chip body also removes it
    );
  }
}