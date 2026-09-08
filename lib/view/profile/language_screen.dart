import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../viewmodel/profile_viewmodel/language_vm.dart';
import './widgets/primary_button.dart';

/// UC402 A4 (Manage Preferred Language, C2). Selecting an option updates
/// the on-screen radio state immediately (a "live preview" in the sense
/// the spec means — this screen doesn't attempt to re-skin its OWN UI into
/// the chosen language, since Module 5's translation pipeline (REQ_201_2–5)
/// is a separate, not-yet-built piece); nothing is persisted until Save.
///
/// Added 8 Sep at Foo's request ("add a edit like at preferences screen at
/// the languages too"): the radio list is now read-only until Edit is
/// tapped, matching Preferences/Personal Info's `_editing` gate exactly
/// (AppBar Edit button, dimmed+ignored content, bottom Save/Cancel row).
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LanguageVm(),
      child: const _LanguageView(),
    );
  }
}

class _LanguageView extends StatefulWidget {
  const _LanguageView();

  @override
  State<_LanguageView> createState() => _LanguageViewState();
}

class _LanguageViewState extends State<_LanguageView> {
  bool _editing = false;

  Future<void> _save(LanguageVm vm) async {
    final ok = await vm.save();
    if (ok && mounted) {
      // Applies the newly-saved language app-wide immediately (see
      // `LocaleVm`) — same pattern as `PreferencesVm.save()` refreshing
      // `AccessibilityVm` for REQ_503_6.
      await context.read<LocaleVm>().refresh();
      if (!mounted) return;
      setState(() => _editing = false);
      // BUG FIX ("the languages change notification will keep spaming if
      // the user keep taping", 8 Sep): the app has exactly one, app-wide
      // `ScaffoldMessenger` (there's no per-screen one), so repeated
      // Save/Cancel taps used to queue up a growing backlog of SnackBars
      // that kept popping up one after another on WHATEVER screen the
      // tourist had since navigated to. Clearing any still-queued
      // SnackBar before showing this one means at most one is ever
      // pending at a time.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(ProfileMessages.m2UpdatedSuccessfully)));
    }
  }

  void _cancel(LanguageVm vm) {
    vm.cancel();
    setState(() => _editing = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(ProfileMessages.m5ChangesDiscarded)));
    // BUG FIX ("the cancel button will also let user back to profile
    // pages, same to preferences and the personal infomation pages", 8
    // Sep): Cancel now backs all the way out to Profile Home, matching
    // Preferences/Personal Info's Cancel button, instead of just staying
    // on this screen with editing turned off.
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LanguageVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t('ui.language')),
        actions: [
          if (!_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: Text(AppLocalizations.t('ui.edit')),
            ),
        ],
      ),
      body: SafeArea(
        child: vm.isLoading && vm.previewLanguageCode == null
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
                            ...Module5Constants.supportedLanguages.values.map((lang) {
                              final selected = vm.previewLanguageCode == lang.code;
                              return Card(
                                color: selected ? AppColors.accentSoft : AppColors.surface,
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                      color: selected ? AppColors.accent : AppColors.moduleBorder),
                                ),
                                child: RadioListTile<String>(
                                  value: lang.code,
                                  groupValue: vm.previewLanguageCode,
                                  onChanged: (code) => vm.preview(code!),
                                  activeColor: AppColors.accent,
                                  title: Text(lang.nativeName,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(lang.englishName),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    if (vm.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(vm.errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
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
                      onPressed: () => _cancel(vm),
                      child: Text(AppLocalizations.t('ui.cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: AppLocalizations.t('ui.save'),
                      isLoading: vm.isSaving,
                      onPressed: () => _save(vm),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
