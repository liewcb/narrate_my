import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../../../viewmodel/profile_viewmodel/register_vm.dart';
import '../onboarding/mandatory_details_screen.dart';
import '../widgets/phone_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import 'login_screen.dart';
import 'otp_screen.dart';

/// UC400 Register Account. Google (A1) up top, then a Phone/Username tab
/// switch for A2 vs A3 — matches the design canvas's Register screens.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RegisterVm(),
      child: const _RegisterView(),
    );
  }
}

class _RegisterView extends StatefulWidget {
  const _RegisterView();

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);

  // Phone tab
  final _phoneController = TextEditingController();
  String _phoneE164 = '';

  // Username tab
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernamePhoneController = TextEditingController();
  String _usernamePhoneE164 = '';

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernamePhoneController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogle(RegisterVm vm) async {
    final profile = await vm.registerWithGoogle();
    if (profile == null || !mounted) return;
    // UC400 A1/A6: `registerOrSignInWithGoogle()` signs into an EXISTING
    // account if that Google identity is already registered — so this one
    // call covers both "brand-new registration" and "already have an
    // account, just log me in." The only way to tell them apart here is
    // whether the Mandatory Details step (added at Foo's request) has ever
    // been completed: a genuinely new account's profile row was just
    // created bare by the `handle_new_user` trigger, so `fullName`/
    // `dateOfBirth` are still null.
    final destination = profile.hasCompletedMandatoryDetails
        ? const AppRoutes()
        : const MandatoryDetailsScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  Future<void> _handlePhoneSubmit(RegisterVm vm) async {
    final ok = await vm.sendPhoneOtp(_phoneE164);
    if (ok && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(flow: OtpFlow.registerPhone, e164Phone: _phoneE164),
        ),
      );
    }
  }

  Future<void> _handleUsernameSubmit(RegisterVm vm) async {
    final ok = await vm.sendUsernameOtp(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmController.text,
      e164Phone: _usernamePhoneE164,
    );
    if (ok && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            flow: OtpFlow.registerUsername,
            e164Phone: _usernamePhoneE164,
            pendingUsername: _usernameController.text.trim(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RegisterVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t('ui.createAccount')),
        actions: [
          if (Navigator.canPop(context))
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset('assets/images/branding/logo.png', height: 96),
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'Continue with Google',
                isLoading: vm.isLoading,
                onPressed: () => _handleGoogle(vm),
              ),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: AppColors.inkFaint)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.inkFaint,
                indicatorColor: AppColors.accent,
                tabs: const [Tab(text: 'Phone'), Tab(text: 'Username')],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 340,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _PhoneTab(
                      controller: _phoneController,
                      errorText: vm.fieldError == 'phone' ? vm.errorMessage : null,
                      onChanged: (e164) => _phoneE164 = e164,
                      isLoading: vm.isLoading,
                      onSubmit: () => _handlePhoneSubmit(vm),
                    ),
                    _UsernameTab(
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      confirmController: _confirmController,
                      phoneController: _usernamePhoneController,
                      errorMessage: vm.errorMessage,
                      onPhoneChanged: (e164) => _usernamePhoneE164 = e164,
                      isLoading: vm.isLoading,
                      onSubmit: () => _handleUsernameSubmit(vm),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(AppLocalizations.t('ui.alreadyHaveAccount')),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: Text(AppLocalizations.t('ui.login')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneTab extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _PhoneTab({
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneField(
          localNumberController: controller,
          errorText: errorText,
          onChanged: onChanged,
        ),
        const Spacer(),
        PrimaryButton(
            label: AppLocalizations.t('ui.sendOtp'), isLoading: isLoading, onPressed: onSubmit),
      ],
    );
  }
}

class _UsernameTab extends StatelessWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final TextEditingController phoneController;
  final String? errorMessage;
  final ValueChanged<String> onPhoneChanged;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _UsernameTab({
    required this.usernameController,
    required this.passwordController,
    required this.confirmController,
    required this.phoneController,
    required this.errorMessage,
    required this.onPhoneChanged,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UnderlineField(label: AppLocalizations.t('ui.username'), controller: usernameController),
          const SizedBox(height: 16),
          UnderlineField(
            label: AppLocalizations.t('ui.password'),
            controller: passwordController,
            obscureText: true,
          ),
          const SizedBox(height: 16),
          UnderlineField(
            label: 'Confirm Password',
            controller: confirmController,
            obscureText: true,
          ),
          const SizedBox(height: 16),
          PhoneField(localNumberController: phoneController, onChanged: onPhoneChanged),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
              label: AppLocalizations.t('ui.createAccount'), isLoading: isLoading, onPressed: onSubmit),
        ],
      ),
    );
  }
}
