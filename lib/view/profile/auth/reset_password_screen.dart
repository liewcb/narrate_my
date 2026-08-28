import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/profile/messages/password_reset_messages.dart';
import '../../../model/repositories/adapters/profile_adapter.dart';
import '../../../viewmodel/profile_viewmodel/reset_password_vm.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import 'login_screen.dart';

/// UC403 Reset Password, Basic Flow steps 11–13. Reached only after the
/// OTP screen has verified phone ownership (`OtpFlow.resetPassword`) — the
/// authenticated session that step established is what [ResetPasswordVm]
/// applies the new password to.
///
/// Gotcha this screen has to guard against: Supabase's `verifyOTP` always
/// establishes a real authenticated session as a side effect — regardless
/// of whether the OTP was sent for a login or for a password reset. That
/// session is what makes the eventual `updateUser(password:)` call below
/// possible, but it also means that if the user backs out of THIS screen
/// without actually resetting their password, they're left silently
/// logged in. The `PopScope` below signs them back out on any way of
/// leaving this screen before a successful reset.
class ResetPasswordScreen extends StatelessWidget {
  final String e164Phone;

  const ResetPasswordScreen({super.key, required this.e164Phone});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResetPasswordVm(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await SupabaseProfileRepositoryAdapter().logout();
          if (context.mounted) Navigator.of(context).pop();
        },
        child: const _ResetPasswordView(),
      ),
    );
  }
}

class _ResetPasswordView extends StatefulWidget {
  const _ResetPasswordView();

  @override
  State<_ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<_ResetPasswordView> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit(ResetPasswordVm vm) async {
    final ok = await vm.resetPassword(
      newPassword: _passwordController.text,
      confirmPassword: _confirmController.text,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PasswordResetMessages.m3ResetSuccessfully)),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ResetPasswordVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.resetPassword'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Choose a new password for your account.',
                style: TextStyle(fontSize: 14.5, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              UnderlineField(
                label: AppLocalizations.t('ui.newPassword'),
                controller: _passwordController,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              UnderlineField(
                label: AppLocalizations.t('ui.confirmNewPassword'),
                controller: _confirmController,
                obscureText: true,
              ),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  vm.errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13.5),
                ),
              ],
              const SizedBox(height: 28),
              PrimaryButton(
                label: AppLocalizations.t('ui.resetPassword'),
                isLoading: vm.isLoading,
                onPressed: () => _submit(vm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
