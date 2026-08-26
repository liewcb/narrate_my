import 'package:flutter/material.dart';
import 'dart:ui';
import 'widgets/hero_section.dart';
import 'widgets/day_section.dart';
import 'widgets/stop_item.dart';
import 'widgets/overview_bottom_actions.dart';

class ItineraryOverviewScreen extends StatelessWidget {
  const ItineraryOverviewScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color brandBg = Color(0xFFF6F3EB);

    return Scaffold(
      backgroundColor: brandBg,
      body: Stack(
        children: [
          // Scrollable Content
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 140), // Space for bottom nav
            child: Column(
              children: [
                const HeroSection(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: Column(
                    children: [
                      DaySection(
                        dayTitle: "Day 1",
                        daySubtitle: "12 Aug • 3 stops",
                        stops: const [
                          StopItem(
                            title: "Batu Caves",
                            imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCMjfKoAV8mJFPqYcGt7W9V38ahl71KbJP1smTNeuVWigqEDbqi1UTKTdufCchlD4A-2R3UVkrT8JeGACQJ98KXYFj-AlA60LkCeDZruoyJJVT32iAna1Y01BzNVWEpax0dCj0wrDfVQ8TpN8RLie9iSssxzP7FiqTrqmf3zJGxjdJ9M8tic_gLzcR9547dF80namyuqav95o2h2XhLH8Sz5PW2VBavNxn7ReCnXySZiO7R8wWjSLiy',
                          ),
                          StopItem(
                            title: "Precious Old China",
                          ),
                          StopItem(
                            title: "Petronas Towers",
                            imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDZZVN7aN6DhplnPpA6q8dpviHE4phNqrmopw0FayUIJHupdAj6jX_LlK5OCFnNxhfrqUsPkvsCieZ5j4HaHssoOjMM4IcTQV2zt801l5ffqlqwEGOySEcIkSF3KlhGrGwvUtIauXtRQNGyswMd1Hm02lxG2kRY3l3Q_Zm1bXU6OC0NqlNBaL6NLhhw65GnPptLOn0hlAbo8zlMe0PRnD2_fLGV-u6d7KoFwTMLUoKX_D70b8QZiofB',
                            isLast: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      DaySection(
                        dayTitle: "Day 2",
                        daySubtitle: "13 Aug • 2 stops",
                        stops: const [
                          StopItem(
                            title: "Merdeka Square",
                          ),
                          StopItem(
                            title: "Central Market",
                            imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBR2NOj0y6xqVT2cUk01wFyh6-ceWXnyP4vUIkG0BEEYQiU1pbWHoZ6jKxXKnfecJ0uD4F3CV75dC6zhJnflzHPqhIdS6sZCo_FOmKA3ORzQwSM6jH4nQgIEciX-LSDZ44RxXDtfP745Eg2zU1mEVv7WWDpn0inF15fiMHyeHQLVtdpaL1VGvWPxTR3mN2QWhsRPmQLSt-egUPgaZ2ib5gVcZvLyakUvFmxcnfx3YmM4OLlIxfUMrMF',
                            isLast: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      DaySection(
                        dayTitle: "Day 3",
                        daySubtitle: "14 Aug • 2 stops",
                        stops: const [
                          StopItem(
                            title: "Islamic Arts Museum",
                            imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBe_-jtOFsMMcpRr_srJbRV4NI7seouPScae_e1GEBC-ILcgJKJMbe3OnNyr0HpIyT4B3l9ptd1FTVqrJWWhdCxRex9UAAhoHPexzXr0Z3nbBEVcB8n54tavayl6LOZ72K6v_hNXUSPP0jMaEel4uvsHhtBJ1SPOXCjIUognFm0SfzIta7QQoPe1VSQAxoUp2eRuhUxA0ZneLOGLeBtQPlVQj8CYz72Sp7VsRmQW5M8S8BjGIFN-1uV',
                          ),
                          StopItem(
                            title: "Jalan Alor",
                            isLast: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      DaySection(
                        dayTitle: "Day 4",
                        daySubtitle: "15 Aug • 1 stop",
                        stops: const [
                          StopItem(
                            title: "KLCC Park",
                            subtitle: "Free until departure",
                            isHollowDot: true,
                            isLast: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Transparent Top App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGlassIconButton(Icons.arrow_back, () => Navigator.maybePop(context)),
                    _buildGlassIconButton(Icons.more_vert, () {}),
                  ],
                ),
              ),
            ),
          ),

          // Sticky Bottom Actions
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: OverviewBottomActions(),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton(IconData icon, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            color: Colors.black.withOpacity(0.2),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}