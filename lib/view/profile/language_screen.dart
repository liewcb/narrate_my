import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../model/business_logic/uc402_messages.dart';
import '../../viewmodel/profile/language_vm.dart';

/// UC402 A4 (Manage Preferred Language, C2). Selecting an option updates
/// the on-screen radio state immediately (a "live preview" in the sense
/// the spec means — this screen doesn't attempt to re-skin its OWN UI into
/// the chosen language, since Module 5's translation pipeline (REQ_201_2–5)
/// is a separate, not-yet-built piece); nothing is persisted until Save.
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

class _LanguageView extends StatelessWidget {
  const _LanguageView();

  Future<void> _save(BuildContext context, LanguageVm vm) async {
    final ok = await vm.save();
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(Uc402Messages.m2UpdatedSuccessfully)));
    }
  }

  void _cancel(BuildContext context, LanguageVm vm) {
    vm.cancel();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(Uc402Messages.m5ChangesDiscarded)));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LanguageVm>();
    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: SafeArea(
        child: vm.isLoading && vm.previewLanguageCode == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
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
                          side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
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
                    if (vm.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Save',
                      isLoading: vm.isSaving,
                      onPressed: () => _save(context, vm),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _cancel(context, vm),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
