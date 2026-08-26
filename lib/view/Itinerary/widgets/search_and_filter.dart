import 'package:flutter/material.dart';

class SearchAndFilter extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;

  const SearchAndFilter({
    Key? key,
    required this.selectedFilter,
    required this.onFilterChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color outlineColor = Colors.grey.shade500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: outlineColor),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "Search by name...",
                    hintStyle: TextStyle(color: outlineColor.withOpacity(0.7)),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Filter Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _buildFilterTab("All"),
              const SizedBox(width: 8),
              _buildFilterTab("Upcoming"),
              const SizedBox(width: 8),
              _buildFilterTab("Ongoing"),
              const SizedBox(width: 8),
              _buildFilterTab("Past"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String label) {
    final bool isSelected = selectedFilter == label;
    const Color primaryColor = Color(0xFF0F3D35);
    final Color unselectedTextColor = Colors.grey.shade700;

    return GestureDetector(
      onTap: () => onFilterChanged(label), // Tells the parent screen to update
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: primaryColor.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : unselectedTextColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}