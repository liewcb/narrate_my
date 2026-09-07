import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// The row of 6 individual digit boxes used on the OTP screen. Reports the
/// full code back via [onCompleted] the instant all 6 digits are filled
/// (matching the design canvas's auto-advance-then-auto-submit feel), and
/// via [onChanged] on every keystroke so the screen can disable the Verify
/// button until it's full.
class OtpBoxRow extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;

  const OtpBoxRow({
    super.key,
    this.onChanged,
    this.onCompleted,
    this.hasError = false,
  });

  @override
  State<OtpBoxRow> createState() => OtpBoxRowState();
}

class OtpBoxRowState extends State<OtpBoxRow> {
  static const _length = 6;
  final _controllers = List.generate(_length, (_) => TextEditingController());

  // `onKeyEvent` is wired directly on the FocusNode itself (not via a
  // wrapping KeyboardListener) — see the note above `build()` for why.
  late final _focusNodes = List.generate(
    _length,
    (i) => FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          _handleBackspace(i);
        }
        return KeyEventResult.ignored;
      },
    ),
  );

  String get code => _controllers.map((c) => c.text).join();

  /// Clears every box and returns focus to the first one — used after a
  /// failed verify attempt so the tourist can immediately retype.
  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    widget.onChanged?.call('');
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _handleChange(int index, String value) {
    if (value.isNotEmpty) {
      if (index < _length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    widget.onChanged?.call(code);
    if (code.length == _length) {
      widget.onCompleted?.call(code);
    }
  }

  void _handleBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      widget.onChanged?.call(code);
    }
  }

  // No KeyboardListener wrapper — it used to wrap each TextField with the
  // SAME FocusNode also passed to that TextField. TextField's own
  // EditableText attaches its own Focus to that node internally, so the
  // node ended up attached at two different depths in the same branch of
  // the widget tree (KeyboardListener's Focus, then TextField's, both
  // pointed at one FocusNode). When Flutter's FocusManager tried to
  // reparent the focus tree from that, it found the node's computed parent
  // was really one of its own descendants — the exact "Tried to make a
  // child into a parent of itself" assertion (with focus_manager.dart in
  // the trace) seen on the OTP screen. Backspace handling is now wired
  // directly on the FocusNode's own `onKeyEvent` (see its constructor
  // above) instead of a wrapping widget, so there's only ever one Focus
  // attachment per node.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_length, (i) {
        return SizedBox(
          width: 44,
          height: 52,
          child: TextField(
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: EdgeInsets.zero,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: widget.hasError ? AppColors.error : AppColors.moduleBorder,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: widget.hasError ? AppColors.error : AppColors.accent,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (value) => _handleChange(i, value),
          ),
        );
      }),
    );
  }
}
