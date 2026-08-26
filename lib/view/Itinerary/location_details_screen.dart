import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/colors.dart';

class LocationDetailsScreen extends StatelessWidget {
  const LocationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // â”€â”€â”€ Hero Image â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            SizedBox(
              height: 353,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuD3AwyQqymXF9fdxO4RP0E6teexwiYIjtXiDYrf2GHcXlfwJwMgG9wMAxKlODCmOT6rzz5wzpSyaMkeMJKJDg6LMDxraOjpHJdjlxZBcZX5eJ8bjD5BPTm8rGoyuogLay6yJ5IeOHyN0hAzLxllSCDrZXdFoTszqfSoPCGtKpGUYTSor9Cra5U7bbgyWFejWfOmBO6mYa1u65Fo6DoDot3YNGbQXv7c67OeTuaXwSzaPHg5VXyS-14t',
                    fit: BoxFit.cover,
                  ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.4),
                        ],
                        stops: const [0.0, 0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                  // â”€â”€â”€ Floating Buttons â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _roundIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                        _roundIconButton(
                          icon: Icons.favorite_border,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // â”€â”€â”€ Content Card (overlapping hero) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned(
              top: 309,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14004D40),
                      offset: Offset(0, -8),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // â”€â”€â”€ Title & Rating â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'Central Market',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandGreen,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: AppColors.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '4.6',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brandCharcoal,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.star,
                                    size: 16,
                                    color: AppColors.orange,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // â”€â”€â”€ Tags â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _tagChip(
                              icon: Icons.location_on,
                              label: 'Kuala Lumpur',
                            ),
                            _tagChip(label: 'Cultural center & shopping'),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // â”€â”€â”€ Quick Info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.outlineVariant),
                              bottom: BorderSide(color: AppColors.outlineVariant),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _quickInfoItem(
                                icon: Icons.schedule,
                                label: 'Suggested: 1 hr',
                              ),
                              Container(
                                width: 1,
                                height: 32,
                                color: AppColors.outlineVariant,
                              ),
                              _quickInfoItem(
                                icon: Icons.local_activity,
                                label: 'Free Entry',
                              ),
                              Container(
                                width: 1,
                                height: 32,
                                color: AppColors.outlineVariant,
                              ),
                              _quickInfoItem(
                                icon: Icons.access_time,
                                label: '10 AM - 8 PM',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // â”€â”€â”€ About â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        const Text(
                          'About',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                            color: AppColors.outline,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Originally built in 1888 as a bustling wet market, this iconic Art Deco landmark has been beautifully transformed into a vibrant hub for Malaysian culture, arts, and crafts. Wander through the diverse stalls offering batik, antiques, and local delicacies in a comfortably air-conditioned heritage setting.',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                            color: AppColors.outline,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // â”€â”€â”€ Location Map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        const Text(
                          'Location',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                            color: AppColors.outline,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 128,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.outlineVariant),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A004D40),
                                offset: Offset(0, 4),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              'https://lh3.googleusercontent.com/aida-public/AB6AXuCKsoIdOai1lvgcg5B6RYnWWhsF-L0RXxfT7vugDF6KKatqKTWzohSlBrf0jHNG2UI60ozGn97vArQ7KOK_BgljbqM5pFbM-79lr1ELxNKSz2CyptsVOPi6vMVDPJsleVfGDfyPZbAZock1M9Uhfn9PMuvKM9kbfHTtA6DCdItbWnzcMGC-NpXGHkTuOZpiHcIDj7o-xItTEjJ_zgiDpuWfls5VBpk9qQL8DciOqAi2f8j4mRaScHNm',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.brandGrayLight,
                                child: const Icon(Icons.map, color: AppColors.outline),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // â”€â”€â”€ Sticky Footer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.95),
                  border: Border(
                    top: BorderSide(color: AppColors.outlineVariant),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A004D40),
                      offset: Offset(0, -4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Add to Itinerary',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandTerracotta,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 8,
                    shadowColor: AppColors.brandTerracotta.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€ Helper Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.9),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            offset: Offset(0, 4),
            blurRadius: 8,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.brandGreen, size: 24),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 24,
      ),
    );
  }

  Widget _tagChip({IconData? icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandGrayLight,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.brandGreen),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.brandGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickInfoItem({required IconData icon, required String label}) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.outline),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}