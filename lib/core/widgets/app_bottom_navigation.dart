// lib/View/widgets/app_bottom_nav_bar.dart
//
// Custom bottom navigation bar matching the design spec:
// - white background
// - fixed 65dp height
// - thin light-gray (#F3F4F6) top border

import 'package:flutter/material.dart';

/// Data for a single bottom nav destination.
class BottomNavItem {
  const BottomNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<BottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double _height = 65;
  static const Color _borderColor = Color(0xFFF3F4F6);
  static const Color _unselectedColor = Color(0xFF9CA3AF);
  // Matches the teal used for the selected "Nearby" pin in the design.
  static const Color _selectedColor = Color(0xFF2D6A5E);

  @override
  Widget build(BuildContext context) {
    const primary = _selectedColor;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _height,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == currentIndex;
              final color = selected ? primary : _unselectedColor;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? (item.selectedIcon ?? item.icon) : item.icon,
                        color: color,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
