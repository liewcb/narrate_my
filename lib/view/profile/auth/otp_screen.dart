import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/profile/messages/login_messages.dart';
import '../../../model/business_logic/profile/messages/password_reset_messages.dart';
import '../../../model/business_logic/profile/messages/profile_messages.dart';
import '../../../model/business_logic/profile/messages/register_messages.dart';
import '../../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../onboarding/mandatory_details_screen.dart';
import '../widgets/hcaptcha_widget.dart';
import '../widgets/otp_box_row.dart';
import '../widgets/primary_button.dart';
import 'reset_password_screen.dart';

/// Shared OTP-verification screen for UC400 A2/A3, UC401 A2, and the
/// middle step of UC403 — which flow it's serving (and what happens after
/// a successful verify) is entirely driven by [flow].
class OtpScreen extends StatelessWidget {
  final OtpFlow flow;
  final String e164Phone;
  final String? pendingUsername;

  const OtpScreen({
    super.key,
    required this.flow,
    required this.e164Phone,
    this.pendingUsername,
  });

  String get _sentMessage => switch (flow) {
        OtpFlow.registerPhone || OtpFlow.registerUsername => RegisterMessages.m2OtpSent,
        OtpFlow.loginPhone => LoginMessages.m2OtpSent,
        OtpFlow.resetPassword => PasswordResetMessages.m2OtpSent,
        OtpFlow.changePhone => ProfileMessages.m11OtpSent,
      };

  @override
  Widget build(BuildContext context) {
    // Watched here (not just inside `_OtpView`) so `_sentMessage` — read
    // once, above, from the message-catalog getters — recomputes if the
    // language changes while this screen is still being built.
    context.watch<LocaleVm>();
    return ChangeNotifierProvider(
      create: (_) => OtpVm(
        flow: flow,
        e164Phone: e164Phone,
        pendingUsername: pendingUsername,
      ),
      child: _OtpView(sentMessage: _sentMessage),
    );
  }
}

class _OtpView extends StatefulWidget {
  final String sentMessage;
  const _OtpView({required this.sentMessage});

  @override
  State<_OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<_OtpView> {
  final _boxKey = GlobalKey<OtpBoxRowState>();
  String _code = '';

  Future<void> _submit(OtpVm vm) async {
    if (_code.length != 6) return;
    try {
      final profile = await vm.verify(_code);
      if (!mounted) return;
      if (vm.flow == OtpFlow.resetPassword) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResetPasswordScreen(e164Phone: vm.e164Phone),
          ),
        );
      } else if (vm.flow == OtpFlow.changePhone) {
        // UC402 A9 step 9: return to Personal Info with the change applied
        // — the caller re-fetches the profile to pick up the new phone.
        Navigator.of(context).pop(true);
      } else if (vm.flow == OtpFlow.registerPhone || vm.flow == OtpFlow.registerUsername) {
        // A brand-new account gets the non-skippable Mandatory Details step
        // (name + DOB, added at Foo's request) first, which itself hands
        // off to the skippable "Personalize your journey" preferences
        // onboarding once that's done. Both clear the auth stack here so
        // there's no way back to OTP/Register.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MandatoryDetailsScreen()),
          (route) => false,
        );
      } else {
        // Login lands straight on the main shell, clearing the whole auth
        // stack behind it — onboarding only makes sense once, at signup.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppRoutes()),
          (route) => false,
        );
      }
      debugPrint('OTP verified for ${vm.flow}, profile=${profile?.id}');
    } catch (_) {
      _boxKey.currentState?.clear();
      setState(() => _code = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OtpVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.enterOtp'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                widget.sentMessage,
                style: const TextStyle(fontSize: 14.5, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                vm.e164Phone,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 32),
              OtpBoxRow(
                key: _boxKey,
                hasError: vm.errorMessage != null,
                onChanged: (code) => setState(() => _code = code),
                onCompleted: (code) {
                  setState(() => _code = code);
                  _submit(vm);
                },
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
                label: AppLocalizations.t('ui.verify'),
                isLoading: vm.isVerifying,
                onPressed: _code.length == 6 ? () => _submit(vm) : null,
              ),
              const SizedBox(height: 20),
              // REQ_501_12 / REQ_502_21: after 5 failed attempts, gate
              // BOTH re-entry and resend behind a solved CAPTCHA — re-entry
              // is already blocked by `vm.showCaptcha` disabling nothing on
              // the Verify button itself (the spec only gates *further*
              // attempts, and a 6th wrong entry just fails normally), so
              // this section's job is specifically the resend gate.
              if (vm.showCaptcha)
                Column(
                  children: [
                    const Text(
                      'Too many failed attempts. Complete the check below before '
                      'requesting another code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    HCaptchaWidget(
                      onVerified: (token) async {
                        final ok = await vm.verifyCaptcha(token);
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verified — you can request a new code now.')),
                          );
                        }
                      },
                      onError: () {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verification failed. Please try again.')),
                          );
                        }
                      },
                    ),
                  ],
                )
              else
                Center(
                  child: TextButton(
                    onPressed: vm.canResend && !vm.isResending ? () => vm.resend() : null,
                    child: Text(
                      vm.canResend
                          ? "Didn't get a code? Resend"
                          : 'Resend available in '
                              '${(vm.resendCooldownSeconds ~/ 60).toString().padLeft(2, '0')}:'
                              '${(vm.resendCooldownSeconds % 60).toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
