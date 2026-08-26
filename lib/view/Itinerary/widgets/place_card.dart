import 'package:flutter/material.dart';

class PlaceCard extends StatelessWidget {
  final String title;
  final String rating;
  final String imageUrl;
  final String categoryText;
  final IconData categoryIcon;
  final Color categoryIconBg;
  final Color categoryIconColor;
  final IconData transitIcon;
  final String transitTime;
  final String duration;
  final bool isAdded;
  final Color primaryColor;
  final Color accentColor;
  final Color mutedText;
  final VoidCallback onAddToggle;

  const PlaceCard({
    Key? key,
    required this.title,
    required this.rating,
    required this.imageUrl,
    required this.categoryText,
    required this.categoryIcon,
    required this.categoryIconBg,
    required this.categoryIconColor,
    required this.transitIcon,
    required this.transitTime,
    required this.duration,
    required this.isAdded,
    required this.primaryColor,
    required this.accentColor,
    required this.mutedText,
    required this.onAddToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(fontFamily: 'Playfair Display', fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.orange, size: 14),
                        const SizedBox(width: 2),
                        Text(rating, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor)),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: categoryIconBg, borderRadius: BorderRadius.circular(6)),
                      child: Icon(categoryIcon, size: 12, color: categoryIconColor),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(categoryText, style: TextStyle(fontSize: 11, color: mutedText), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(transitIcon, size: 12, color: mutedText),
                        const SizedBox(width: 2),
                        Text(transitTime, style: TextStyle(fontSize: 11, color: mutedText)),
                        const SizedBox(width: 12),
                        Icon(Icons.hourglass_empty, size: 12, color: mutedText),
                        const SizedBox(width: 2),
                        Text(duration, style: TextStyle(fontSize: 11, color: mutedText)),
                      ],
                    ),
                    InkWell(
                      onTap: onAddToggle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAdded ? primaryColor : accentColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            if (isAdded) ...[
                              const Icon(Icons.check, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              isAdded ? "Added" : "Add",
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}