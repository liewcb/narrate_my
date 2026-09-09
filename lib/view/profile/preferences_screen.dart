import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/accessibility/accessibility_vm.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../model/business_logic/profile/preference_options.dart';
import '../../model/entities/preferences.dart';
import '../../viewmodel/profile_viewmodel/preferences_vm.dart';
import './widgets/attraction_tile.dart';
import './widgets/primary_button.dart';
import './widgets/toggle_preference_tile.dart';

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
  bool _synced = false;

  // Added 6 Sep at Foo's request, matching Personal Info/Language: all
  // chips/toggles are read-only until Edit is tapped.
  bool _editing = false;

  void _syncFrom(Preferences p) {
    if (_synced) return;
    _attraction = p.attractionInterests.toSet();
    _food = p.foodCuisineInterests.toSet();
    _dietary = p.dietaryPreferences.toSet();
    _dietaryRestrictions = p.dietaryRestrictions.toSet();
    _accessibility = p.accessibilityPreferences.toSet();
    _synced = true;
  }

  Future<void> _save(PreferencesVm vm) async {
    // Category Exclusions removed from the UI 6 Sep at Foo's request —
    // preserve whatever was already stored rather than silently wiping it
    // (nothing on this screen edits it any more).
    final updated = Preferences(
      attractionInterests: _attraction.toList(),
      foodCuisineInterests: _food.toList(),
      dietaryPreferences: _dietary.toList(),
      dietaryRestrictions: _dietaryRestrictions.toList(),
      accessibilityPreferences: _accessibility.toList(),
      categoryExclusions: vm.preferences?.categoryExclusions ?? const [],
    );
    final ok = await vm.save(updated);
    if (ok && mounted) {
      // REQ_503_6: so a Visual Assistance toggle applies its text-scale
      // immediately, without waiting for the next login.
      await context.read<AccessibilityVm>().refresh();
      if (!mounted) return;
      setState(() => _editing = false);
      // BUG FIX ("the languages change notification will keep spaming if
      // the user keep taping", 8 Sep — same fix applied here for
      // consistency): the app has exactly one, app-wide
      // `ScaffoldMessenger`, so repeated Save/Cancel taps used to queue a
      // growing SnackBar backlog that kept popping up on whatever screen
      // the tourist had since navigated to. Clearing any still-queued
      // SnackBar first means at most one is ever pending at a time.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(ProfileMessages.m2UpdatedSuccessfully)));
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
      _editing = false;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(ProfileMessages.m5ChangesDiscarded)));
    // BUG FIX ("the cancel button will also let user back to profile
    // pages, same to preferences and the personal infomation pages", 8
    // Sep): Cancel now backs all the way out to Profile Home instead of
    // just staying on this screen with editing turned off.
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PreferencesVm>();
    context.watch<LocaleVm>();
    if (vm.preferences != null) _syncFrom(vm.preferences!);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t('ui.preferences')),
        actions: [
          if (!_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: Text(AppLocalizations.t('ui.edit')),
            ),
        ],
      ),
      body: SafeArea(
        child: vm.isLoading && vm.preferences == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IgnorePointer(
                      ignoring: !_editing,
                      child: Opacity(
                        opacity: _editing ? 1 : 0.6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionLabel(AppLocalizations.t('ui.attractionInterests')),
                            const SizedBox(height: 10),
                            // crossAxisCount matches the Initial Preferences
                            // (onboarding) screen's grid — same tile picture
                            // size/layout in both places, per Foo's request.
                            AttractionTileGrid(
                              options: kAttractionCategories,
                              selected: _attraction,
                              crossAxisCount: 2,
                              onToggle: (v) => setState(() => _toggle(_attraction, v)),
                            ),
                            const SizedBox(height: 22),
                            _ChipSection(
                              title: AppLocalizations.t('ui.foodCuisine'),
                              options: kFoodCuisineOptions,
                              selected: _food,
                              onToggle: (v) => setState(() => _toggle(_food, v)),
                            ),
                            _ChipSection(
                              title: AppLocalizations.t('ui.dietaryPreferences'),
                              options: kDietaryOptions,
                              selected: _dietary,
                              onToggle: (v) => setState(() => _toggleDietary(v)),
                            ),
                            _ChipSection(
                              title: AppLocalizations.t('ui.dietaryRestrictionsTitle'),
                              options: kDietaryRestrictionOptions,
                              selected: _dietaryRestrictions,
                              onToggle: (v) => setState(() => _toggle(_dietaryRestrictions, v)),
                            ),
                            _SectionLabel(AppLocalizations.t('ui.accessibilityPreferences')),
                            const SizedBox(height: 10),
                            ...kAccessibilityOptions.map(
                              (option) => TogglePreferenceTile(
                                title: optionLabel(option),
                                subtitle: accessibilityDescription(option),
                                emoji: kAccessibilityEmoji[option],
                                value: _accessibility.contains(option),
                                onChanged: (_) => setState(() => _toggle(_accessibility, option)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (vm.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                    // Save/Cancel moved out of this scroll view into a
                    // persistent bottom bar (6 Sep, Foo's request) — they
                    // used to sit after every section, so changing just the
                    // top Attraction Interests meant scrolling all the way
                    // down to reach them.
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _editing
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cancel(vm.preferences),
                      child: Text(AppLocalizations.t('ui.cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                        label: AppLocalizations.t('ui.save'),
                        isLoading: vm.isSaving,
                        onPressed: () => _save(vm)),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  void _toggle(Set<String> set, String value) {
    if (set.contains(value)) {
      set.remove(value);
    } else {
      set.add(value);
    }
  }

  /// Dietary Preferences' own toggle handler — Halal is a lifestyle choice
  /// that, in practice, always implies "no pork" as a hard restriction. This
  /// keeps the two sections consistent automatically instead of relying on
  /// the tourist to separately remember to also tick "No Pork" below.
  /// One-directional by design: un-ticking Halal does NOT remove "No Pork"
  /// again, since the tourist may have selected it for an unrelated reason
  /// and silently removing it would be a bigger surprise than leaving it.
  ///
  /// Added at Foo's request (9 Sep, "since the halal will lead to no pork,
  /// then the food and cuisine also can let to vegetarian"): the same idea
  /// applied to Food & Cuisine — choosing "Vegetarian" here pre-selects the
  /// matching "Vegetarian-Friendly" cuisine chip below, instead of leaving
  /// the tourist to separately notice and tick it themselves. Same
  /// one-directional rule as Halal/No Pork: un-ticking Vegetarian does NOT
  /// remove "Vegetarian-Friendly" again.
  void _toggleDietary(String value) {
    _toggle(_dietary, value);
    if (value == 'Halal' && _dietary.contains('Halal')) {
      _dietaryRestrictions.add('No Pork');
    }
    if (value == 'Vegetarian' && _dietary.contains('Vegetarian')) {
      _food.add('Vegetarian-Friendly');
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
                label: Text(optionLabel(option)),
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
