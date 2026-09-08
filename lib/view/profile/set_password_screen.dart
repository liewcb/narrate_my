import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../viewmodel/profile_viewmodel/set_password_vm.dart';
import './widgets/password_rules_hint.dart';
import './widgets/primary_button.dart';
import './widgets/underline_field.dart';

/// Added at Foo's request — NOT in the written spec ("so shall i follow
/// the normal apps, do add the user can add username and password
/// afterward??", 8 Sep). Reached from Personal Info's Password row when
/// `profile.hasPassword == false` — lets a phone-OTP-only or Google-only
/// account add a username + password as an ADDITIONAL login method,
/// without touching the login method(s) it already has. Pops `true` on
/// success so the caller knows to refresh the profile.
class SetPasswordScreen extends StatelessWidget {
  const SetPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SetPasswordVm(),
      child: const _SetPasswordView(),
    );
  }
}

class _SetPasswordView extends StatefulWidget {
  const _SetPasswordView();

  @override
  State<_SetPasswordView> createState() => _SetPasswordViewState();
}

class _SetPasswordViewState extends State<_SetPasswordView> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Live password-strength/match feedback, same as Register's Username
    // tab — see register_screen.dart's identical listeners.
    _passwordController.addListener(_onPasswordFieldsChanged);
    _confirmController.addListener(_onPasswordFieldsChanged);
  }

  void _onPasswordFieldsChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordFieldsChanged);
    _confirmController.removeListener(_onPasswordFieldsChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit(SetPasswordVm vm) async {
    final profile = await vm.submit(
      username: _usernameController.text,
      password: _passwordController.text,
      confirmPassword: _confirmController.text,
    );
    if (profile != null && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(ProfileMessages.m26UsernamePasswordSet)));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SetPasswordVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.setUsernameAndPassword'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppLocalizations.t('ui.setUsernameAndPasswordHint'),
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 20),
              UnderlineField(
                label: AppLocalizations.t('ui.username'),
                controller: _usernameController,
                errorText: vm.fieldError == 'username' ? vm.errorMessage : null,
              ),
              const SizedBox(height: 16),
              UnderlineField(
                label: AppLocalizations.t('ui.newPassword'),
                controller: _passwordController,
                obscureText: true,
              ),
              PasswordRulesHint(password: _passwordController.text),
              const SizedBox(height: 16),
              UnderlineField(
                label: AppLocalizations.t('ui.confirmNewPassword'),
                controller: _confirmController,
                obscureText: true,
              ),
              PasswordMatchHint(
                password: _passwordController.text,
                confirmation: _confirmController.text,
              ),
              if (vm.fieldError == 'password' && vm.errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(vm.errorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: AppLocalizations.t('ui.save'),
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
