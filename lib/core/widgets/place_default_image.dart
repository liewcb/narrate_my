import 'package:flutter/material.dart';
import '../config/api_keys.dart';
import '../theme/app_theme.dart';

class PlaceDefaultImage extends StatelessWidget {
  final String? photoRef;
  final double height;
  final double width;
  final BoxFit fit;

  const PlaceDefaultImage({
    Key? key,
    this.photoRef,
    this.height = 180,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: height,
        width: width,
        color: AppColors.surface2,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    final imageUrl = _buildPhotoUrl(photoRef);
    if (imageUrl == null || imageUrl.isEmpty) {
      return const _PlaceholderIcon();
    }
    return Image.network(
      imageUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => const _PlaceholderIcon(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  String? _buildPhotoUrl(String? photoRef, {int maxWidth = 400}) {
    if (photoRef == null || photoRef.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=$maxWidth'
        '&photoreference=$photoRef'
        '&key=${ApiKeys.googleMapsApiKey}';
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.place_outlined, size: 56, color: AppColors.inkFaint),
    );
  }
}