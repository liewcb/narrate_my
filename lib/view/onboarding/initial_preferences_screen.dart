import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/accessibility/accessibility_vm.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/attraction_tile.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/toggle_preference_tile.dart';
import '../../model/business_logic/preference_options.dart';
import '../../model/entities/preferences.dart';
import '../../viewmodel/profile/preferences_vm.dart';

/// "Personalize your journey" — the one-time onboarding screen shown right
/// after a tourist completes registration (see `OtpScreen._submit`, which
/// routes here instead of straight to [AppRoutes] for the two register
/// flows only; login skips this screen entirely).
///
/// This is UI-only convenience on top of UC402 A3 (Manage Preferences) — it
/// reuses the same [PreferencesVm]/`Preferences` entity and the same
/// `updatePreferences` save call the Preferences screen uses, it's just a
/// friendlier first-run entry point for the same data. "Category
/// Exclusions" is deliberately left out here (it reads as an advanced/edit
/// action, not a first-run one) — it's still reachable afterwards from
/// Profile > Preferences.
class InitialPreferencesScreen extends StatelessWidget {
  const InitialPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PreferencesVm(),
      child: const _InitialPreferencesView(),
    );
  }
}

class _InitialPreferencesView extends StatefulWidget {
  const _InitialPreferencesView();

  @override
  State<_InitialPreferencesView> createState() => _InitialPreferencesViewState();
}

class _InitialPreferencesViewState extends State<_InitialPreferencesView> {
  final Set<String> _attraction = {};
  final Set<String> _food = {};
  final Set<String> _dietary = {};
  final Set<String> _dietaryRestrictions = {};
  final Set<String> _accessibility = {};

  void _finish() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRoutes()),
      (route) => false,
    );
  }

  Future<void> _finishSetup(PreferencesVm vm) async {
    final existing = vm.preferences ?? const Preferences();
    final updated = existing.copyWith(
      attractionInterests: _attraction.toList(),
      foodCuisineInterests: _food.toList(),
      dietaryPreferences: _dietary.toList(),
      dietaryRestrictions: _dietaryRestrictions.toList(),
      accessibilityPreferences: _accessibility.toList(),
    );
    // Best-effort: even if the save fails (e.g. transient network error),
    // don't strand a brand-new tourist on an onboarding screen — they can
    // always set these later from Profile > Preferences.
    await vm.save(updated);
    // REQ_503_6: so a Visual Assistance pick applies its text-scale right
    // away, without waiting for the next login.
    if (mounted) await context.read<AccessibilityVm>().refresh();
    if (mounted) _finish();
  }

  void _toggle(Set<String> set, String value) => setState(() {
        if (set.contains(value)) {
          set.remove(value);
        } else {
          set.add(value);
        }
      });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PreferencesVm>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: vm.isSaving ? null : _finish,
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Personalize your journey',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              const Text(
                "Tell us what you're into so we can tailor recommendations — "
                'you can always change this later in Profile.',
                style: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 22),
              const _SectionLabel('What kind of attractions do you enjoy?'),
              const SizedBox(height: 10),
              AttractionTileGrid(
                options: kAttractionCategories,
                selected: _attraction,
                crossAxisCount: 2,
                onToggle: (v) => _toggle(_attraction, v),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Food & Cuisine Interests'),
              const SizedBox(height: 10),
              _ChipWrap(
                options: kFoodCuisineOptions,
                selected: _food,
                onToggle: (v) => _toggle(_food, v),
              ),
              const SizedBox(height: 22),
              const _SectionLabel('Dietary Preferences'),
              const SizedBox(height: 10),
              _ChipWrap(
                options: kDietaryOptions,
                selected: _dietary,
                onToggle: (v) => _toggle(_dietary, v),
              ),
              const SizedBox(height: 22),
              const _SectionLabel('Dietary Restrictions & Allergies'),
              const SizedBox(height: 10),
              _ChipWrap(
                options: kDietaryRestrictionOptions,
                selected: _dietaryRestrictions,
                onToggle: (v) => _toggle(_dietaryRestrictions, v),
              ),
              const SizedBox(height: 22),
              const _SectionLabel('Accessibility Preferences'),
              const SizedBox(height: 10),
              ...kAccessibilityOptions.map(
                (option) => TogglePreferenceTile(
                  title: option,
                  subtitle: kAccessibilityDescriptions[option],
                  emoji: kAccessibilityEmoji[option],
                  value: _accessibility.contains(option),
                  onChanged: (_) => _toggle(_accessibility, option),
                ),
              ),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Finish setup',
                isLoading: vm.isSaving,
                onPressed: () => _finishSetup(vm),
              ),
            ],
          ),
        ),
      ),
    );
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

class _ChipWrap extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _ChipWrap({required this.options, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (_) => onToggle(option),
          showCheckmark: false,
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.accent.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: isSelected ? AppColors.accent : AppColors.inkSoft,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
          side: BorderSide(color: isSelected ? AppColors.accent : AppColors.border),
        );
      }).toList(),
    );
  }
}
