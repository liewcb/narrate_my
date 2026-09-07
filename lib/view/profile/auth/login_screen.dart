import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/profile/messages/register_messages.dart';
import '../../../model/business_logic/profile/validators.dart';
import '../../../viewmodel/profile_viewmodel/login_vm.dart';
import '../../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../onboarding/mandatory_details_screen.dart';
import '../widgets/phone_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import './forgot_password_screen.dart';
import './otp_screen.dart';
import './register_screen.dart';

/// UC401 Login Account. Google (A1) up top, then a Phone-OTP / Username &
/// Password tab switch for A2 vs A3.
class LoginScreen extends StatelessWidget {
  /// When true, a successful login pops `true` to the caller instead of
  /// replacing the app with a new shell. Shared actions such as Bookmark can
  /// then retry the pending operation automatically.
  final bool returnOnSuccess;

  const LoginScreen({super.key, this.returnOnSuccess = false});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginVm(),
      child: _LoginView(returnOnSuccess: returnOnSuccess),
    );
  }
}

class _LoginView extends StatefulWidget {
  final bool returnOnSuccess;

  const _LoginView({required this.returnOnSuccess});

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView>
    with SingleTickerProviderStateMixin {
  // No TabBarView below — the two tabs' forms are genuinely different
  // lengths (Username has an extra field + forgot-password link), and a
  // fixed-height TabBarView forced both to share one height, so the
  // taller tab needed its own nested scroll just to reach its own button
  // ("need to scroll to see create account button"). Driving the visible
  // tab off `_tabController.index` instead lets each tab's content size
  // itself naturally within the page's own scroll — this listener is what
  // makes that rebuild happen when the tab is tapped.
  late final _tabController = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  final _phoneController = TextEditingController();
  String _phoneE164 = '';

  /// Set by [_handlePhoneSubmit]'s local E.164 format/length check — kept
  /// separate from `vm.errorMessage` because this runs BEFORE any network
  /// call, so there's no point hitting Supabase for a string that isn't
  /// even a phone number yet. Cleared as soon as the tourist edits the
  /// field again.
  String? _phoneLocalError;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _completeLogin() {
    if (widget.returnOnSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRoutes()),
      (route) => false,
    );
  }

  Future<void> _handleGoogle(LoginVm vm) async {
    final profile = await vm.signInWithGoogle();
    if (profile != null && mounted) {
      // BUG FIX (6 Sep, Foo: "when user login using unregister account at
      // the login pages, it will also not redirect the user to the
      // initial pages, the system shall detect the user is new user or
      // not using gmail"): Supabase's Google sign-in auto-provisions a
      // brand-new account on first use — there's no separate "not
      // registered" error the way phone login has — so a first-time
      // Google sign-in from THIS screen used to `_completeLogin()`
      // straight into the app with an empty profile. Mirrors
      // register_screen.dart's `_handleGoogle`: a bare `fullName`/
      // `dateOfBirth` means the account is new, so route through
      // Mandatory Details first instead.
      if (!profile.hasCompletedMandatoryDetails) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MandatoryDetailsScreen()),
          (route) => false,
        );
        return;
      }
      _completeLogin();
    } else if (vm.errorMessage != null && mounted) {
      // Neither tab's error slot shows this (fieldError == 'google'), so
      // it needs its own surface.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage!)));
    }
  }

  Future<void> _handlePhoneSubmit(LoginVm vm) async {
    // Local format/length check first (E.164) — only once that passes do
    // we go anywhere near the network, let alone the does-this-account-
    // exist check on the server.
    if (!Validators.isValidPhone(_phoneE164)) {
      setState(() => _phoneLocalError = RegisterMessages.m5InvalidPhoneFormat);
      return;
    }
    final ok = await vm.sendPhoneOtp(_phoneE164);
    if (ok && mounted) {
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            flow: OtpFlow.loginPhone,
            e164Phone: _phoneE164,
            returnOnSuccess: widget.returnOnSuccess,
          ),
        ),
      );
      if (loggedIn == true && mounted && widget.returnOnSuccess) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _handleUsernameSubmit(LoginVm vm) async {
    final profile = await vm.loginWithUsernamePassword(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (profile != null && mounted) _completeLogin();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LoginVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t('ui.login')),
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
                child: Image.asset(
                  'assets/images/branding/logo.png',
                  height: 96,
                ),
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
                    child: Text(
                      'or',
                      style: TextStyle(color: AppColors.inkFaint),
                    ),
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
                tabs: const [
                  Tab(text: 'Phone'),
                  Tab(text: 'Username'),
                ],
              ),
              const SizedBox(height: 20),
              // Plain conditional, not TabBarView — see the comment on
              // `_tabController`'s init above for why.
              if (_tabController.index == 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PhoneField(
                      localNumberController: _phoneController,
                      // Local format error takes priority — it means we
                      // never even attempted the network call this VM
                      // error would otherwise be reporting on. Scoped to
                      // this tab only via `fieldError == 'phone'` —
                      // without that check, a Username-tab error would
                      // also render here (this was the original bug: both
                      // tabs shared one error slot with no way to tell
                      // which tab it belonged to).
                      errorText:
                          _phoneLocalError ?? (vm.fieldError == 'phone' ? vm.errorMessage : null),
                      onChanged: (e164) {
                        _phoneE164 = e164;
                        if (_phoneLocalError != null) setState(() => _phoneLocalError = null);
                      },
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: AppLocalizations.t('ui.sendOtp'),
                      isLoading: vm.isLoading,
                      onPressed: () => _handlePhoneSubmit(vm),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UnderlineField(
                      label: AppLocalizations.t('ui.username'),
                      controller: _usernameController,
                    ),
                    const SizedBox(height: 16),
                    UnderlineField(
                      label: AppLocalizations.t('ui.password'),
                      controller: _passwordController,
                      obscureText: true,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.t('ui.forgotPassword'),
                        ),
                      ),
                    ),
                    // Scoped to this tab only — see the Phone-tab comment
                    // above for why this check matters.
                    if (vm.fieldError == 'username' && vm.errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        vm.errorMessage!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: AppLocalizations.t('ui.login'),
                      isLoading: vm.isLoading,
                      onPressed: () => _handleUsernameSubmit(vm),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(AppLocalizations.t('ui.dontHaveAccount')),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text(AppLocalizations.t('ui.createAccount')),
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
