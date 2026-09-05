import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Displays a remote place photo with one consistent, reusable fallback.
class PlaceImage extends StatelessWidget {
  static const fallbackAsset =
      'assets/images/placeholders/no_image_available.png';

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const PlaceImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final placeholder = Container(
      width: width,
      height: height,
      color: const Color(0xFFF2EEE7),
      alignment: Alignment.center,
      child: Image.asset(
        fallbackAsset,
        width: 54,
        height: 54,
        color: AppColors.inkFaint,
        semanticLabel: 'No image available',
      ),
    );

    final image = url == null || url.isEmpty
        ? placeholder
        : Image.network(
            url,
            width: width,
            height: height,
            fit: fit,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );

    return borderRadius == null
        ? image
        : ClipRRect(borderRadius: borderRadius!, child: image);
  }
}
