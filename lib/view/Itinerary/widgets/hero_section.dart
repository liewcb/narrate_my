import 'package:flutter/material.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.network(
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAjoMOyNUU_sUsJSzZmVtJzfHbhIj8jhZW7G_Odot2SNaVKVnJUK2pi28iG6Z5_p6NeD1viA-juSzeFSOsJpxARIQxItG1ZI2no_UF5XVhIrEbwbiYfAVHn6fPEOffgGQxvXY-wB01ZM8UScIYWhWrcYAEGR9suIe2mXINwwg8somEkCxaVk47G5nb-RfGeeat2lDVxjHayhjXb-2BB_5dBjGGuYC3NixF2MDNNJqMtE5Hb9SB5pQ-b',
            fit: BoxFit.cover,
          ),
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFF1A201E).withOpacity(0.8),
                  const Color(0xFF1A201E).withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Text Content
          Positioned(
            bottom: 32,
            left: 32,
            right: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Text(
                    "PREVIEW",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Text(
                  "Kuala Lumpur\nGetaway",
                  style: TextStyle(
                    fontFamily: 'Playfair Display',
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "4 Days • 12-15 Aug",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}