import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile_business_logic/messages/profile_messages.dart';
import '../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../../viewmodel/profile_viewmodel/personal_info_vm.dart';
import '../auth/otp_screen.dart';
import '../widgets/phone_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import 'change_password_screen.dart';

/// UC402 A2 (Manage Personal Information). Full Name/Bio are the section's
/// own atomic Save/Cancel (REQ_503_11); phone number change (A9) and
/// password change (A16) are their own confirmation-gated sub-flows,
/// reachable from here but not bundled into this section's Save.
class PersonalInfoScreen extends StatelessWidget {
  const PersonalInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PersonalInfoVm(),
      child: const _PersonalInfoView(),
    );
  }
}

class _PersonalInfoView extends StatefulWidget {
  const _PersonalInfoView();

  @override
  State<_PersonalInfoView> createState() => _PersonalInfoViewState();
}

class _PersonalInfoViewState extends State<_PersonalInfoView> {
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _newPhoneController = TextEditingController();
  String _newPhoneE164 = '';
  bool _synced = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _newPhoneController.dispose();
    super.dispose();
  }

  void _syncControllers(PersonalInfoVm vm) {
    if (_synced || vm.profile == null) return;
    _fullNameController.text = vm.profile!.fullName ?? '';
    _bioController.text = vm.profile!.bio ?? '';
    _synced = true;
  }

  Future<void> _save(PersonalInfoVm vm) async {
    final ok = await vm.save(fullName: _fullNameController.text, bio: _bioController.text);
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ProfileMessages.m2UpdatedSuccessfully)));
    }
  }

  void _cancel(PersonalInfoVm vm) {
    _fullNameController.text = vm.profile?.fullName ?? '';
    _bioController.text = vm.profile?.bio ?? '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.discardedMessage)));
  }

  Future<void> _changePhone(PersonalInfoVm vm) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // AnimatedBuilder, not a plain builder: `vm` is a ChangeNotifier
      // (Listenable) and this sheet is outside the screen's own
      // context.watch<PersonalInfoVm>() — without this, isSaving/
      // errorMessage updates from sendPhoneChangeOtp() would never repaint
      // the sheet (a bare `builder:` widget tree is built once and doesn't
      // subscribe to notifyListeners on its own).
      builder: (sheetContext) => AnimatedBuilder(
        animation: vm,
        builder: (context, _) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change Phone Number',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              PhoneField(
                localNumberController: _newPhoneController,
                onChanged: (e164) => _newPhoneE164 = e164,
              ),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Send OTP',
                isLoading: vm.isSaving,
                onPressed: () async {
                  final ok = await vm.sendPhoneChangeOtp(_newPhoneE164);
                  if (ok && sheetContext.mounted) Navigator.of(sheetContext).pop(true);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true && mounted) {
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OtpScreen(flow: OtpFlow.changePhone, e164Phone: _newPhoneE164),
        ),
      );
      if (verified == true) {
        await vm.load();
        _synced = false;
        if (mounted) _syncControllers(vm);
      }
    }
  }

  Future<void> _linkGoogle(PersonalInfoVm vm) async {
    final ok = await vm.linkGoogleAccount();
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ProfileMessages.m12GoogleLinkedSuccessfully)));
    }
  }

  Future<void> _unlinkGoogle(PersonalInfoVm vm) async {
    // A20 step 3 (M19): confirm before unlinking.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlink Google Account'),
        content: const Text(ProfileMessages.m19ConfirmUnlinkGoogle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unlink', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // A21's "no other login method" guard, and any other failure, surfaces
    // as vm.errorMessage — shown via the section's normal error banner
    // below, same as every other action on this screen.
    final ok = await vm.unlinkGoogleAccount();
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ProfileMessages.m20GoogleUnlinked)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PersonalInfoVm>();
    _syncControllers(vm);
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Info')),
      body: SafeArea(
        child: vm.isLoading && vm.profile == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // C3: username is fixed at registration.
                    if (vm.profile?.username != null) ...[
                      Text('USERNAME', style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint)),
                      const SizedBox(height: 4),
                      Text(vm.profile!.username!,
                          style: const TextStyle(fontSize: 15.5, color: AppColors.inkFaint)),
                      const SizedBox(height: 20),
                    ],
                    UnderlineField(
                      label: 'Full Name',
                      controller: _fullNameController,
                      errorText: vm.fieldError == 'fullName' ? vm.errorMessage : null,
                    ),
                    const SizedBox(height: 16),
                    UnderlineField(
                      label: 'Bio',
                      controller: _bioController,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.phone_outlined, color: AppColors.ink),
                      title: const Text('Phone Number'),
                      subtitle: Text(vm.profile?.phone ?? 'Not set'),
                      trailing: TextButton(
                        onPressed: () => _changePhone(vm),
                        child: Text(vm.profile?.phone == null ? 'Add' : 'Change'),
                      ),
                    ),
                    if (vm.profile?.hasPassword == true)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline, color: AppColors.ink),
                        title: const Text('Password'),
                        trailing: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                          ),
                          child: const Text('Change'),
                        ),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle_outlined, color: AppColors.ink),
                      title: const Text('Google Account'),
                      subtitle: Text(vm.profile?.hasGoogleLinked == true ? 'Linked' : 'Not linked'),
                      trailing: TextButton(
                        onPressed: () => vm.profile?.hasGoogleLinked == true
                            ? _unlinkGoogle(vm)
                            : _linkGoogle(vm),
                        child: Text(vm.profile?.hasGoogleLinked == true ? 'Unlink' : 'Link'),
                      ),
                    ),
                    if (vm.errorMessage != null && vm.fieldError == null) ...[
                      const SizedBox(height: 8),
                      Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                    const SizedBox(height: 28),
                    PrimaryButton(
                      label: 'Save',
                      isLoading: vm.isSaving,
                      onPressed: () => _save(vm),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: () => _cancel(vm), child: const Text('Cancel')),
                  ],
                ),
              ),
      ),
    );
  }
}
