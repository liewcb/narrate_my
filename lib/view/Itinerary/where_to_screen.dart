import 'package:flutter/material.dart';
import '../../model/entities/destination.dart';
import 'widgets/destination_card.dart';
import 'widgets/selected_chip.dart';

class WhereToScreen extends StatefulWidget {
  const WhereToScreen({super.key});

  @override
  State<WhereToScreen> createState() => _WhereToScreenState();
}

class _WhereToScreenState extends State<WhereToScreen> {
  // ── State ──────────────────────────────────────────────
  final Set<String> _selected = {'kl', 'penang'};
  final TextEditingController _searchController = TextEditingController();
  List<Destination> _filtered = kDestinations;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Handlers ───────────────────────────────────────────
  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? kDestinations
          : kDestinations
          .where((d) => d.name.toLowerCase().contains(query))
          .toList();
    });
  }

  void _toggleDestination(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _removeDestination(String id) {
    setState(() => _selected.remove(id));
  }

  void _onContinue() {
    if (_selected.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const Step2Placeholder()),
    );
  }

  // ── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final selectedDestinations =
    kDestinations.where((d) => _selected.contains(d.id)).toList();

    return Scaffold(
      // ── AppBar ──
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Step 1 of 2'),
        centerTitle: true,
        actions: const [SizedBox(width: 48)],
      ),

      // ── Scrollable Body ──
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 24),

                // ── Heading ──
                const Text(
                  'Where to next?',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Search and select one or multiple destinations.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),

                // ── Search TextField ──
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search cities, islands, regions...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _searchController.clear,
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Selected Chips ──
                if (selectedDestinations.isNotEmpty) ...[
                  Text(
                    'SELECTED (${selectedDestinations.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedDestinations.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final dest = selectedDestinations[index];
                        return SelectedChip(
                          label: dest.name,
                          onRemove: () => _removeDestination(dest.id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // ── Section Label ──
                Text(
                  _searchController.text.isNotEmpty
                      ? 'RESULTS FOR "${_searchController.text.toUpperCase()}"'
                      : 'POPULAR IN MALAYSIA',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
              ]),
            ),
          ),

          // ── 2-column Destination Grid ──
          if (_filtered.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 48),
                    SizedBox(height: 8),
                    Text('No destinations found'),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final dest = _filtered[index];
                    return DestinationCard(
                      destination: dest,
                      isSelected: _selected.contains(dest.id),
                      onTap: () => _toggleDestination(dest.id),
                    );
                  },
                  childCount: _filtered.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),

      // ── Sticky Bottom CTA ──
      floatingActionButton: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ElevatedButton.icon(
            onPressed: _selected.isNotEmpty ? _onContinue : null,
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              _selected.isEmpty
                  ? 'Select a Destination'
                  : 'Continue with ${_selected.length} '
                  'Destination${_selected.length != 1 ? "s" : ""}',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation:
      FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ── Step 2 placeholder ─────────────────────────────────────
class Step2Placeholder extends StatelessWidget {
  const Step2Placeholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Step 2 of 2'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text(
          'Step 2: Choose Dates',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}