import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/profile/messages/register_messages.dart';
import '../../../model/business_logic/profile/validators.dart';
import '../../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../../../viewmodel/profile_viewmodel/register_vm.dart';
import '../onboarding/mandatory_details_screen.dart';
import '../widgets/password_rules_hint.dart';
import '../widgets/phone_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import './login_screen.dart';
import './otp_screen.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // No TabBarView below — same reasoning as login_screen.dart's
  // _tabController: the two tabs' forms are different lengths (Username
  // has two extra fields), and a fixed-height TabBarView forced both to
  // share one height, so the taller tab needed its own nested scroll just
  // to reach its own button. Driving the visible tab off
  // `_tabController.index` instead lets each tab's content size itself
  // naturally within the page's own scroll.
  late final _tabController = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  // Phone tab
  final _phoneController = TextEditingController();
  String _phoneE164 = '';

  /// Local E.164 format/length check, run before any network call — see
  /// login_screen.dart's identical field for the reasoning.
  String? _phoneLocalError;

  // Username tab
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernamePhoneController = TextEditingController();
  String _usernamePhoneE164 = '';
  String? _usernamePhoneLocalError;

  @override
  void initState() {
    super.initState();
    // Added 6 Sep at Foo's request (item 8: live password-strength
    // feedback) — PasswordRulesHint/PasswordMatchHint below need this tab
    // to rebuild on every keystroke, same as the two dedicated password
    // screens already do via their own StatefulWidget's setState.
    _passwordController.addListener(_onPasswordFieldsChanged);
    _confirmController.addListener(_onPasswordFieldsChanged);
    // BUG FIX ("press login or register with google it will automaticlly
    // redirect user to google pages and if user back to the screen withou
    // choosing any account, it will keep loading", 8 Sep): see
    // didChangeAppLifecycleState below.
    WidgetsBinding.instance.addObserver(this);
  }

  void _onPasswordFieldsChanged() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.removeListener(_onPasswordFieldsChanged);
    _confirmController.removeListener(_onPasswordFieldsChanged);
    _tabController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernamePhoneController.dispose();
    super.dispose();
  }

  /// The Google account-chooser opens in an external browser tab/window —
  /// there's no callback Supabase can fire when the tourist just closes it
  /// without picking an account. The app coming back to the foreground
  /// while still `isLoading` is the only observable signal that happened,
  /// so a short grace period after resume (in case a real sign-in is still
  /// completing) cancels the wait.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final vm = context.read<RegisterVm>();
    if (!vm.isLoading) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && vm.isLoading) vm.cancelGoogleSignIn();
    });
  }

  Future<void> _handleGoogle(RegisterVm vm) async {
    final profile = await vm.registerWithGoogle();
    if (profile == null) {
      // Neither tab's error slot shows a Google failure, so it needs its
      // own surface — previously this branch did nothing at all, silently
      // swallowing the error.
      if (vm.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage!)));
      }
      return;
    }
    if (!mounted) return;
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
    if (!Validators.isValidPhone(_phoneE164)) {
      setState(() => _phoneLocalError = RegisterMessages.m5InvalidPhoneFormat);
      return;
    }
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
    // BUG FIX (6 Sep, Foo: "the username part at the register still have
    // same issues"): this used to `return` right here whenever the phone
    // was invalid, which meant `vm.sendUsernameOtp` below — where the
    // username/password/confirm-password validation actually lives — was
    // never even called if the phone field was ALSO empty/invalid (which
    // it always is until it's filled in). The phone format is still
    // flagged locally below, but the call now always goes through so the
    // other three fields' errors surface regardless of the phone field's
    // state; navigation is still gated on the phone being valid too.
    final phoneValid = Validators.isValidPhone(_usernamePhoneE164);
    if (!phoneValid) {
      setState(() => _usernamePhoneLocalError = RegisterMessages.m5InvalidPhoneFormat);
    }
    final ok = await vm.sendUsernameOtp(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmController.text,
      e164Phone: _usernamePhoneE164,
    );
    if (ok && phoneValid && mounted) {
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
              // Plain conditional, not TabBarView — see the comment on
              // `_tabController`'s init above for why.
              if (_tabController.index == 0)
                _PhoneTab(
                  controller: _phoneController,
                  // Local format error takes priority — it means we never
                  // even attempted the network call this VM error would
                  // otherwise be reporting on.
                  errorText:
                      _phoneLocalError ?? (vm.fieldError == 'phone' ? vm.errorMessage : null),
                  onChanged: (e164) {
                    _phoneE164 = e164;
                    if (_phoneLocalError != null) setState(() => _phoneLocalError = null);
                  },
                  isLoading: vm.isLoading,
                  onSubmit: () => _handlePhoneSubmit(vm),
                )
              else
                _UsernameTab(
                  usernameController: _usernameController,
                  passwordController: _passwordController,
                  confirmController: _confirmController,
                  // Re-read fresh on every rebuild (driven by the
                  // listeners added in initState above) so the hints
                  // below update live as the tourist types.
                  currentPassword: _passwordController.text,
                  currentConfirmation: _confirmController.text,
                  phoneController: _usernamePhoneController,
                  phoneErrorText: _usernamePhoneLocalError,
                  onPhoneFieldChanged: () {
                    if (_usernamePhoneLocalError != null) {
                      setState(() => _usernamePhoneLocalError = null);
                    }
                  },
                  // Scoped to this tab only — a Phone-tab or Google error
                  // shouldn't also render here. Forced to 'username' by
                  // RegisterVm for every failure from this call (see its
                  // doc comment) so any error from this submit shows,
                  // regardless of which specific field caused it.
                  errorMessage: vm.fieldError == 'username' ? vm.errorMessage : null,
                  onPhoneChanged: (e164) => _usernamePhoneE164 = e164,
                  isLoading: vm.isLoading,
                  onSubmit: () => _handleUsernameSubmit(vm),
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
        // BUG FIX: this was `const Spacer()` — a `Spacer` needs a bounded
        // height to compute its flex, but this Column sits inside the
        // screen's `SingleChildScrollView` (unbounded height), so it threw
        // a layout exception on every build. That's why the Phone tab
        // (the Register screen's default tab) rendered blank — the error
        // happened before anything below it could lay out.
        const SizedBox(height: 20),
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
  final String currentPassword;
  final String currentConfirmation;
  final TextEditingController phoneController;
  final String? errorMessage;
  final String? phoneErrorText;
  final VoidCallback onPhoneFieldChanged;
  final ValueChanged<String> onPhoneChanged;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _UsernameTab({
    required this.usernameController,
    required this.passwordController,
    required this.confirmController,
    required this.currentPassword,
    required this.currentConfirmation,
    required this.phoneController,
    required this.errorMessage,
    required this.phoneErrorText,
    required this.onPhoneFieldChanged,
    required this.onPhoneChanged,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    // No inner SingleChildScrollView — this tab now sits directly in the
    // page's own scroll (see the caller's comment on `_tabController`'s
    // init), so it no longer needs its own nested scroll region.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UnderlineField(label: AppLocalizations.t('ui.username'), controller: usernameController),
        const SizedBox(height: 16),
        UnderlineField(
          label: AppLocalizations.t('ui.password'),
          controller: passwordController,
          obscureText: true,
        ),
        // Live strength feedback (6 Sep, Foo's request, item 8) — mirrors
        // Validators.isValidPassword exactly, same widget already used on
        // Change/Reset Password.
        PasswordRulesHint(password: currentPassword),
        const SizedBox(height: 16),
        UnderlineField(
          label: 'Confirm Password',
          controller: confirmController,
          obscureText: true,
        ),
        PasswordMatchHint(password: currentPassword, confirmation: currentConfirmation),
        const SizedBox(height: 16),
        PhoneField(
          localNumberController: phoneController,
          errorText: phoneErrorText,
          onChanged: (e164) {
            onPhoneChanged(e164);
            onPhoneFieldChanged();
          },
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
            label: AppLocalizations.t('ui.createAccount'), isLoading: isLoading, onPressed: onSubmit),
      ],
    );
  }
}
