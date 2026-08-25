import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The filled terracotta CTA button used throughout the auth flow (design
/// canvas: "Register", "Log In", "Verify OTP", "Reset Password", etc.).
/// Wraps [ElevatedButton] purely to add a built-in loading spinner so every
/// screen doesn't reimplement the same `isLoading ? spinner : Text` swap.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.bg,
              ),
            )
          : Text(label),
    );
  }
}

/// The outline-style secondary button (design canvas: "Continue with
/// Google") — a light surface, bordered, with room for a leading icon.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.ink),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 10)],
                Text(label),
              ],
            ),
    );
  }
}
