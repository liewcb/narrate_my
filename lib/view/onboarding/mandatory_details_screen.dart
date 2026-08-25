import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../viewmodel/profile_viewmodel/mandatory_details_vm.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import 'initial_preferences_screen.dart';

/// Added at Foo's request — NOT part of the written spec. Shown exactly
/// once, immediately after registration succeeds (phone, username, or
/// Google — see `OtpScreen._submit` and `RegisterScreen._handleGoogle`),
/// BEFORE the still-skippable "Personalize your journey" preferences
/// onboarding. Deliberately non-skippable: no Skip action, no back button,
/// and `PopScope` blocks the system back gesture too — a tourist cannot
/// reach the main app without providing a name and date of birth once.
class MandatoryDetailsScreen extends StatelessWidget {
  const MandatoryDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MandatoryDetailsVm(),
      child: PopScope(
        canPop: false,
        child: const _MandatoryDetailsView(),
      ),
    );
  }
}

class _MandatoryDetailsView extends StatefulWidget {
  const _MandatoryDetailsView();

  @override
  State<_MandatoryDetailsView> createState() => _MandatoryDetailsViewState();
}

class _MandatoryDetailsViewState extends State<_MandatoryDetailsView> {
  final _nameController = TextEditingController();
  DateTime? _dob;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Date of Birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _continue(MandatoryDetailsVm vm) async {
    final ok = await vm.save(fullName: _nameController.text, dateOfBirth: _dob);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const InitialPreferencesScreen()),
      );
    }
  }

  String _formatDob(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MandatoryDetailsVm>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tell Us About You'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "One last step — this helps us personalize your NarrateMy experience.",
                style: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              UnderlineField(
                label: 'Full Name',
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth',
                    border: UnderlineInputBorder(),
                  ),
                  child: Text(
                    _dob == null ? 'Select date' : _formatDob(_dob!),
                    style: TextStyle(
                      fontSize: 15.5,
                      color: _dob == null ? AppColors.inkFaint : AppColors.ink,
                    ),
                  ),
                ),
              ),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  vm.errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13.5),
                ),
              ],
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Continue',
                isLoading: vm.isSaving,
                onPressed: () => _continue(vm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
