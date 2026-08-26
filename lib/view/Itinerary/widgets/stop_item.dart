import 'package:flutter/material.dart';

class StopItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final bool isLast;
  final bool isHollowDot;

  const StopItem({
    Key? key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.isLast = false,
    this.isHollowDot = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color brandLine = Color(0xFFE3DECF);
    const Color brandSecondary = Color(0xFF194D44);
    const Color brandBg = Color(0xFFF6F3EB);
    const Color brandText = Color(0xFF1A201E);
    const Color brandTextMuted = Color(0xFF5A6663);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Line & Dot
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: isHollowDot ? brandBg : brandSecondary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isHollowDot ? brandLine : brandBg,
                      width: isHollowDot ? 2 : 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: brandLine,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: brandText,
                            height: 1.2,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: brandTextMuted,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  if (imageUrl != null) ...[
                    const SizedBox(width: 16),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: brandLine.withOpacity(0.5)),
                        image: DecorationImage(
                          image: NetworkImage(imageUrl!),
                          fit: BoxFit.cover,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                    ),
                  ]
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}