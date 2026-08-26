import 'package:flutter/material.dart';

class CustomSegmentedToggle extends StatelessWidget {
  final bool showBookmarks;
  final Color primaryColor;
  final Color mutedText;
  final ValueChanged<bool> onToggle;

  const CustomSegmentedToggle({
    Key? key,
    required this.showBookmarks,
    required this.primaryColor,
    required this.mutedText,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade300.withOpacity(0.5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Expanded(child: _buildToggleButton("Bookmarks", true)),
          Expanded(child: _buildToggleButton("Search Maps", false)),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isBookmarkTab) {
    bool isActive = showBookmarks == isBookmarkTab;
    return GestureDetector(
      onTap: () => onToggle(isBookmarkTab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? primaryColor : mutedText,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}