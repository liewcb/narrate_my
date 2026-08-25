import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile_business_logic/messages/profile_messages.dart';
import '../../viewmodel/profile_viewmodel/change_password_vm.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';

/// UC402 A16–A18 (C6).
class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChangePasswordVm(),
      child: const _ChangePasswordView(),
    );
  }
}

class _ChangePasswordView extends StatefulWidget {
  const _ChangePasswordView();

  @override
  State<_ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<_ChangePasswordView> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit(ChangePasswordVm vm) async {
    final ok = await vm.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
      confirmPassword: _confirmController.text,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ProfileMessages.m15PasswordChangedSuccessfully)));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChangePasswordVm>();
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnderlineField(
                label: 'Current Password',
                controller: _currentController,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              UnderlineField(label: 'New Password', controller: _newController, obscureText: true),
              const SizedBox(height: 16),
              UnderlineField(
                label: 'Confirm New Password',
                controller: _confirmController,
                obscureText: true,
              ),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13.5)),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Change Password',
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
