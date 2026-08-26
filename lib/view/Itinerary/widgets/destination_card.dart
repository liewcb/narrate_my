import 'package:flutter/material.dart';

import '../../../model/entities/destination.dart';

/// A tappable image card representing a single destination.
/// Shows a check badge when [isSelected] is true and a primary-colour
/// border via [Card.shape].
class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final Destination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isSelected
              ? BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 3,
          )
              : BorderSide.none,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image ──
            Image.network(
              destination.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, size: 40),
              ),
            ),

            // ── Dark gradient overlay ──
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                  stops: [0.0, 0.6],
                ),
              ),
            ),

            // ── Selection badge (top-right) ──
            Positioned(
              top: 8,
              right: 8,
              child: isSelected
                  ? CircleAvatar(
                radius: 13,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
                  : Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white60,
                    width: 2,
                  ),
                ),
              ),
            ),

            // ── Name label (bottom-left) ──
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Text(
                destination.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}