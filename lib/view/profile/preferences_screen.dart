import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/accessibility/accessibility_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile_business_logic/messages/profile_messages.dart';
import '../../model/business_logic/profile_business_logic/preference_options.dart';
import '../../model/entities/preferences.dart';
import '../../viewmodel/profile_viewmodel/preferences_vm.dart';
import '../widgets/attraction_tile.dart';
import '../widgets/primary_button.dart';
import '../widgets/toggle_preference_tile.dart';

/// UC402 A3 (Manage Preferences). All categories are staged locally in
/// this screen's own state and saved together, in one call, as the
/// section's single atomic update (REQ_503_11) — nothing here calls
/// `PreferencesVm.save` until the Save button is pressed.
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PreferencesVm(),
      child: const _PreferencesView(),
    );
  }
}

class _PreferencesView extends StatefulWidget {
  const _PreferencesView();

  @override
  State<_PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<_PreferencesView> {
  Set<String> _attraction = {};
  Set<String> _food = {};
  Set<String> _dietary = {};
  Set<String> _dietaryRestrictions = {};
  Set<String> _accessibility = {};
  Set<String> _exclusions = {};
  bool _synced = false;

  void _syncFrom(Preferences p) {
    if (_synced) return;
    _attraction = p.attractionInterests.toSet();
    _food = p.foodCuisineInterests.toSet();
    _dietary = p.dietaryPreferences.toSet();
    _dietaryRestrictions = p.dietaryRestrictions.toSet();
    _accessibility = p.accessibilityPreferences.toSet();
    _exclusions = p.categoryExclusions.toSet();
    _synced = true;
  }

  Future<void> _save(PreferencesVm vm) async {
    final updated = Preferences(
      attractionInterests: _attraction.toList(),
      foodCuisineInterests: _food.toList(),
      dietaryPreferences: _dietary.toList(),
      dietaryRestrictions: _dietaryRestrictions.toList(),
      accessibilityPreferences: _accessibility.toList(),
      categoryExclusions: _exclusions.toList(),
    );
    final ok = await vm.save(updated);
    if (ok && mounted) {
      // REQ_503_6: so a Visual Assistance toggle applies its text-scale
      // immediately, without waiting for the next login.
      await context.read<AccessibilityVm>().refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ProfileMessages.m2UpdatedSuccessfully)));
    }
  }

  void _cancel(Preferences? saved) {
    if (saved == null) return;
    setState(() {
      _attraction = saved.attractionInterests.toSet();
      _food = saved.foodCuisineInterests.toSet();
      _dietary = saved.dietaryPreferences.toSet();
      _dietaryRestrictions = saved.dietaryRestrictions.toSet();
      _accessibility = saved.accessibilityPreferences.toSet();
      _exclusions = saved.categoryExclusions.toSet();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(ProfileMessages.m5ChangesDiscarded)));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PreferencesVm>();
    if (vm.preferences != null) _syncFrom(vm.preferences!);
    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: SafeArea(
        child: vm.isLoading && vm.preferences == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('Attraction & Activity Interests'),
                    const SizedBox(height: 10),
                    AttractionTileGrid(
                      options: kAttractionCategories,
                      selected: _attraction,
                      crossAxisCount: 3,
                      onToggle: (v) => setState(() => _toggle(_attraction, v)),
                    ),
                    const SizedBox(height: 22),
                    _ChipSection(
                      title: 'Food & Cuisine Interests',
                      options: kFoodCuisineOptions,
                      selected: _food,
                      onToggle: (v) => setState(() => _toggle(_food, v)),
                    ),
                    _ChipSection(
                      title: 'Dietary Preferences',
                      options: kDietaryOptions,
                      selected: _dietary,
                      onToggle: (v) => setState(() => _toggle(_dietary, v)),
                    ),
                    _ChipSection(
                      title: 'Dietary Restrictions & Allergies',
                      options: kDietaryRestrictionOptions,
                      selected: _dietaryRestrictions,
                      onToggle: (v) => setState(() => _toggle(_dietaryRestrictions, v)),
                    ),
                    _SectionLabel('Accessibility Preferences'),
                    const SizedBox(height: 10),
                    ...kAccessibilityOptions.map(
                      (option) => TogglePreferenceTile(
                        title: option,
                        subtitle: kAccessibilityDescriptions[option],
                        emoji: kAccessibilityEmoji[option],
                        value: _accessibility.contains(option),
                        onChanged: (_) => setState(() => _toggle(_accessibility, option)),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _ChipSection(
                      title: 'Attraction Categories to Exclude',
                      options: kAttractionCategories,
                      selected: _exclusions,
                      onToggle: (v) => setState(() => _toggle(_exclusions, v)),
                      chipColor: AppColors.error,
                    ),
                    if (vm.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    PrimaryButton(label: 'Save', isLoading: vm.isSaving, onPressed: () => _save(vm)),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _cancel(vm.preferences),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _toggle(Set<String> set, String value) {
    if (set.contains(value)) {
      set.remove(value);
    } else {
      set.add(value);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink));
  }
}

class _ChipSection extends StatelessWidget {
  final String title;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final Color? chipColor;

  const _ChipSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.chipColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final isSelected = selected.contains(option);
              final color = chipColor ?? AppColors.accent;
              return FilterChip(
                label: Text(option),
                selected: isSelected,
                onSelected: (_) => onToggle(option),
                showCheckmark: false,
                backgroundColor: AppColors.surface,
                selectedColor: color.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: isSelected ? color : AppColors.inkSoft,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
                side: BorderSide(color: isSelected ? color : AppColors.moduleBorder),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
