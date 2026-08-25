import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../../viewmodel/profile_viewmodel/reset_password_vm.dart';
import '../widgets/phone_field.dart';
import '../widgets/primary_button.dart';
import 'otp_screen.dart';

/// UC403 Reset Password, Basic Flow steps 1–6 (A1). Collects the phone
/// number, sends the OTP, and hands off to the shared [OtpScreen].
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResetPasswordVm(),
      child: const _ForgotPasswordView(),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final _phoneController = TextEditingController();
  String _phoneE164 = '';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit(ResetPasswordVm vm) async {
    final ok = await vm.sendResetOtp(_phoneE164);
    if (ok && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(flow: OtpFlow.resetPassword, e164Phone: _phoneE164),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ResetPasswordVm>();
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Enter your registered phone number to reset your password.',
                style: TextStyle(fontSize: 14.5, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              PhoneField(
                localNumberController: _phoneController,
                errorText: vm.errorMessage,
                onChanged: (e164) => _phoneE164 = e164,
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Send OTP',
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
