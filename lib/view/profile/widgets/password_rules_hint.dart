import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/profile/validators.dart';

/// Live password-rule checklist shown under every "New Password" field —
/// added 2 Sep at Foo's request ("each time user key in the password
/// field will let user know the error in their password"): updates on
/// every keystroke via the field's `onChanged`, rather than only surfacing
/// a rule violation after Save/Submit is pressed and rejected.
///
/// Mirrors [Validators.isValidPassword]'s exact two rules (C2 / REQ_504_5 /
/// REQ_503_19 — min 8 chars, at least one letter, at least one number) —
/// deliberately doesn't invent any stricter rule that isn't also enforced
/// where the password is actually validated.
class PasswordRulesHint extends StatelessWidget {
  final String password;

  const PasswordRulesHint({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    // Nothing typed yet — no rules to react to. Showing three grey "unmet"
    // rows on an empty, untouched field reads as a wall of errors before
    // the tourist has done anything; better to wait for the first keystroke.
    if (password.isEmpty) return const SizedBox.shrink();

    final hasLength = password.length >= 8;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _RuleRow(met: hasLength, label: 'At least 8 characters'),
          _RuleRow(met: hasLetter, label: 'Contains a letter'),
          _RuleRow(met: hasNumber, label: 'Contains a number'),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final bool met;
  final String label;

  const _RuleRow({required this.met, required this.label});

  static const _metColor = Color(0xFF2E7D4F);

  @override
  Widget build(BuildContext context) {
    final color = met ? _metColor : AppColors.inkFaint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(met ? Icons.check_circle : Icons.circle_outlined, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

/// Small helper the confirm-password field can use alongside
/// [PasswordRulesHint] — a one-line "passwords match/don't match yet"
/// indicator, same live-as-you-type spirit. Only appears once the tourist
/// has typed something into the confirmation field.
class PasswordMatchHint extends StatelessWidget {
  final String password;
  final String confirmation;

  const PasswordMatchHint({super.key, required this.password, required this.confirmation});

  @override
  Widget build(BuildContext context) {
    if (confirmation.isEmpty) return const SizedBox.shrink();
    final matches = Validators.passwordsMatch(password, confirmation);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            matches ? Icons.check_circle : Icons.error_outline,
            size: 13,
            color: matches ? const Color(0xFF2E7D4F) : AppColors.error,
          ),
          const SizedBox(width: 6),
          Text(
            matches ? 'Passwords match' : "Passwords don't match yet",
            style: TextStyle(fontSize: 12, color: matches ? const Color(0xFF2E7D4F) : AppColors.error),
          ),
        ],
      ),
    );
  }
}
