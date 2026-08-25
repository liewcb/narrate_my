import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The uppercase-label, underline-only text field used across every auth
/// form in the design canvas (Username, Password, Full Name, etc.) —
/// styling comes almost entirely from `AppTheme.light.inputDecorationTheme`;
/// this just fixes the label casing/letter-spacing and the error-text
/// wiring in one place.
///
/// Password fields (`obscureText: true`) automatically get a show/hide eye
/// toggle as their suffix icon — every password field in the app goes
/// through this widget, so this one change covers Register, Login, Reset
/// Password, and Change Password at once. A caller-supplied [suffixIcon]
/// still wins if one is explicitly passed alongside `obscureText: true`
/// (none currently are).
class UnderlineField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? errorText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final TextCapitalization textCapitalization;

  const UnderlineField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.errorText,
    this.suffixIcon,
    this.onChanged,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<UnderlineField> createState() => _UnderlineFieldState();
}

class _UnderlineFieldState extends State<UnderlineField> {
  // Starts obscured whenever the field was asked to be a password field;
  // the eye toggle below flips this per-field, independent of any other
  // password field on the same screen.
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final effectiveSuffix = widget.suffixIcon ??
        (widget.obscureText
            ? IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.inkFaint,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
                tooltip: _obscured ? 'Show password' : 'Hide password',
              )
            : null);

    return TextField(
      controller: widget.controller,
      obscureText: widget.obscureText ? _obscured : false,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      textCapitalization: widget.textCapitalization,
      style: const TextStyle(fontSize: 15.5, color: AppColors.ink),
      decoration: InputDecoration(
        labelText: widget.label.toUpperCase(),
        hintText: widget.hint,
        errorText: widget.errorText,
        suffixIcon: effectiveSuffix,
      ),
    );
  }
}
