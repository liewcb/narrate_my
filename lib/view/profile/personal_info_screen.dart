import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../../viewmodel/profile_viewmodel/personal_info_vm.dart';
import './auth/otp_screen.dart';
import './change_password_screen.dart';
import './set_password_screen.dart';
import './widgets/phone_field.dart';
import './widgets/primary_button.dart';
import './widgets/underline_field.dart';

/// UC402 A2 (Manage Personal Information). Full Name is the section's own
/// atomic Save/Cancel (REQ_503_11); phone number change (A9) and password
/// change (A16) are their own confirmation-gated sub-flows, reachable from
/// here but not bundled into this section's Save.
///
/// Bio removed 6 Sep at Foo's request — it wasn't used anywhere in the app.
///
/// The fields are read-only until Edit is tapped (matching Language
/// screen's `_editing` pattern) — added 6 Sep at Foo's request, to stop
/// accidental edits.
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

class _PersonalInfoViewState extends State<_PersonalInfoView>
    with WidgetsBindingObserver {
  final _fullNameController = TextEditingController();
  final _newPhoneController = TextEditingController();
  String _newPhoneE164 = '';
  bool _synced = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    // BUG FIX ("press login or register with google it will automaticlly
    // redirect user to google pages and if user back to the screen withou
    // choosing any account, it will keep loading", 8 Sep — the Google
    // LINK flow on this screen has the same problem as register/login's
    // Google sign-in): see didChangeAppLifecycleState below.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fullNameController.dispose();
    _newPhoneController.dispose();
    super.dispose();
  }

  /// See register_screen.dart's identical override for the full reasoning
  /// — the app resuming is the only observable signal that the Google
  /// account-chooser browser tab closed without picking an account.
  /// `isSaving` is shared by every action on this screen (Save Name,
  /// phone-change OTP send, Google link/unlink), but
  /// `cancelGoogleLink()`/`cancelPendingGoogleAuth()` is a no-op unless a
  /// Google flow is actually the one in flight, so checking the shared
  /// flag here is safe.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final vm = context.read<PersonalInfoVm>();
    if (!vm.isSaving) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && vm.isSaving) vm.cancelGoogleLink();
    });
  }

  void _syncControllers(PersonalInfoVm vm) {
    if (_synced || vm.profile == null) return;
    _fullNameController.text = vm.profile!.fullName ?? '';
    _synced = true;
  }

  Future<void> _save(PersonalInfoVm vm) async {
    final ok = await vm.save(fullName: _fullNameController.text);
    if (ok && mounted) {
      setState(() => _editing = false);
      // BUG FIX ("the languages change notification will keep spaming if
      // the user keep taping", 8 Sep — same fix applied here for
      // consistency): the app has exactly one, app-wide
      // `ScaffoldMessenger`, so repeated Save/Cancel taps used to queue a
      // growing SnackBar backlog that kept popping up on whatever screen
      // the tourist had since navigated to.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(ProfileMessages.m2UpdatedSuccessfully)));
    }
  }

  void _cancel(PersonalInfoVm vm) {
    _fullNameController.text = vm.profile?.fullName ?? '';
    setState(() => _editing = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(vm.discardedMessage)));
    // BUG FIX ("the cancel button will also let user back to profile
    // pages, same to preferences and the personal infomation pages", 8
    // Sep): Cancel now backs all the way out to Profile Home instead of
    // just staying on this screen with editing turned off.
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  Future<void> _changePhone(PersonalInfoVm vm) async {
    // Own error slot for this sub-flow (`vm.phoneChangeErrorMessage`) so a
    // Google-link/unlink failure elsewhere on this screen can never bleed
    // into this bottom sheet, and vice versa — was previously all sharing
    // `vm.errorMessage`.
    vm.clearPhoneChangeError();
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
              Text(AppLocalizations.t('ui.changePhoneNumber'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              PhoneField(
                localNumberController: _newPhoneController,
                onChanged: (e164) => _newPhoneE164 = e164,
              ),
              if (vm.phoneChangeErrorMessage != null) ...[
                const SizedBox(height: 10),
                Text(vm.phoneChangeErrorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: AppLocalizations.t('ui.sendOtp'),
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

  /// Added at Foo's request — NOT in the written spec ("so shall i follow
  /// the normal apps, do add the user can add username and password
  /// afterward??", 8 Sep). Only reachable when `vm.profile?.hasPassword`
  /// is false — see the Password row below.
  Future<void> _setPassword(PersonalInfoVm vm) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SetPasswordScreen()),
    );
    if (done == true && mounted) {
      await vm.load();
    }
  }

  Future<void> _linkGoogle(PersonalInfoVm vm) async {
    final ok = await vm.linkGoogleAccount();
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ProfileMessages.m12GoogleLinkedSuccessfully)));
    }
  }

  Future<void> _deleteAccount(PersonalInfoVm vm) async {
    // Moved here 6 Sep at Foo's request — separate screen from Logout, its
    // own "Danger Zone" section below, so it's never mistaken for it.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.t('ui.deleteAccount')),
        content: Text(ProfileMessages.m22ConfirmDeleteAccount),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.t('ui.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await vm.deleteAccount();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ProfileMessages.m23AccountDeleted)));
      // BUG FIX (6 Sep, Foo: "the message will show the account is not
      // active anymore but the account will not logout?? is this
      // correct??"): the auth-gate swap to `GuestProfileScreen` (same
      // mechanism as logout) DOES happen the instant the session clears —
      // but this screen was still pushed on top of it, so the swap
      // underneath was invisible until the tourist manually backed out.
      // Pop back to the root route so the now-logged-out Profile tab is
      // actually what's on screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (vm.deleteAccountErrorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(vm.deleteAccountErrorMessage!)));
    }
  }

  Future<void> _unlinkGoogle(PersonalInfoVm vm) async {
    // A20 step 3 (M19): confirm before unlinking.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.t('ui.unlinkGoogleAccount')),
        content: Text(ProfileMessages.m19ConfirmUnlinkGoogle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.t('ui.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.t('ui.unlink'), style: const TextStyle(color: AppColors.error)),
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
          .showSnackBar(SnackBar(content: Text(ProfileMessages.m20GoogleUnlinked)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PersonalInfoVm>();
    context.watch<LocaleVm>();
    _syncControllers(vm);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.t('ui.personalInfo')),
        actions: [
          if (!_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: Text(AppLocalizations.t('ui.edit')),
            ),
        ],
      ),
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
                    // Everything below — Full Name plus Phone/Password/
                    // Google — is gated behind `_editing` together, so
                    // there's no accidental tap on any of them without
                    // pressing Edit first (6 Sep, Foo's request: "phone
                    // changes and google link still able to tap even not
                    // press the edit").
                    IgnorePointer(
                      ignoring: !_editing,
                      child: Opacity(
                        opacity: _editing ? 1 : 0.6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            UnderlineField(
                              label: AppLocalizations.t('ui.fullName'),
                              controller: _fullNameController,
                              errorText: vm.fieldError == 'fullName' ? vm.errorMessage : null,
                            ),
                            const SizedBox(height: 24),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.phone_outlined, color: AppColors.ink),
                              title: Text(AppLocalizations.t('ui.phoneNumber')),
                              subtitle:
                                  Text(vm.profile?.phone ?? AppLocalizations.t('ui.notSet')),
                              trailing: TextButton(
                                onPressed: () => _changePhone(vm),
                                child: Text(vm.profile?.phone == null
                                    ? AppLocalizations.t('ui.add')
                                    : AppLocalizations.t('ui.change')),
                              ),
                            ),
                            // Added at Foo's request: an account with no
                            // password yet (phone-OTP-only or Google-only)
                            // now gets a "Set Username & Password" action
                            // here instead of the row disappearing
                            // entirely, so it can add password login as an
                            // additional method later.
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.lock_outline, color: AppColors.ink),
                              title: Text(AppLocalizations.t('ui.password')),
                              subtitle: vm.profile?.hasPassword == true
                                  ? null
                                  : Text(AppLocalizations.t('ui.notSet')),
                              trailing: TextButton(
                                onPressed: () => vm.profile?.hasPassword == true
                                    ? Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => const ChangePasswordScreen()),
                                      )
                                    : _setPassword(vm),
                                child: Text(vm.profile?.hasPassword == true
                                    ? AppLocalizations.t('ui.change')
                                    : AppLocalizations.t('ui.add')),
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.account_circle_outlined, color: AppColors.ink),
                              title: Text(AppLocalizations.t('ui.googleAccount')),
                              subtitle: Text(vm.profile?.hasGoogleLinked == true
                                  ? AppLocalizations.t('ui.linked')
                                  : AppLocalizations.t('ui.notLinked')),
                              trailing: TextButton(
                                onPressed: () => vm.profile?.hasGoogleLinked == true
                                    ? _unlinkGoogle(vm)
                                    : _linkGoogle(vm),
                                child: Text(vm.profile?.hasGoogleLinked == true
                                    ? AppLocalizations.t('ui.unlink')
                                    : AppLocalizations.t('ui.link')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Scoped to this screen's own actions only (fieldError
                    // null means it wasn't the Full Name save that failed) —
                    // and no longer shared with the phone-change bottom
                    // sheet, which now reads its own
                    // `vm.phoneChangeErrorMessage` instead.
                    if (vm.errorMessage != null && vm.fieldError == null) ...[
                      const SizedBox(height: 8),
                      Text(vm.errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                    if (_editing) ...[
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: AppLocalizations.t('ui.save'),
                        isLoading: vm.isSaving,
                        onPressed: () => _save(vm),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                          onPressed: () => _cancel(vm),
                          child: Text(AppLocalizations.t('ui.cancel'))),
                    ],
                    // Delete Account — its own section, far from
                    // Save/Cancel and not next to Logout (which stays on
                    // the Profile home screen). No "Danger Zone" label (6
                    // Sep, Foo's request) — just the divider for
                    // separation. Gated behind `_editing` like everything
                    // else above, so it can't be tapped by accident either.
                    const SizedBox(height: 36),
                    const Divider(),
                    const SizedBox(height: 12),
                    IgnorePointer(
                      ignoring: !_editing,
                      child: Opacity(
                        opacity: _editing ? 1 : 0.6,
                        child: OutlinedButton.icon(
                          onPressed: vm.isDeletingAccount ? null : () => _deleteAccount(vm),
                          icon: vm.isDeletingAccount
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.delete_outline, color: AppColors.error),
                          label: Text(AppLocalizations.t('ui.deleteAccount'),
                              style: const TextStyle(color: AppColors.error)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.error),
                          ),
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
