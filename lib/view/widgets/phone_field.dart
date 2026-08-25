import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

class CountryCode {
  final String dialCode; // e.g. "+60"
  final String flagEmoji;
  final String name;
  const CountryCode(this.dialCode, this.flagEmoji, this.name);
}

/// A short, practical list — not exhaustive. Malaysia first since
/// NarrateMy is a Malaysia-focused heritage-tourism app (Batu Caves is the
/// design canvas's own hero image); the rest cover the app's likely
/// tourist origins. Add more here if the team needs them later.
const kDefaultCountry = CountryCode('+60', '🇲🇾', 'Malaysia');

const List<CountryCode> kCountryCodes = [
  kDefaultCountry,
  CountryCode('+65', '🇸🇬', 'Singapore'),
  CountryCode('+62', '🇮🇩', 'Indonesia'),
  CountryCode('+66', '🇹🇭', 'Thailand'),
  CountryCode('+86', '🇨🇳', 'China'),
  CountryCode('+91', '🇮🇳', 'India'),
  CountryCode('+44', '🇬🇧', 'United Kingdom'),
  CountryCode('+1', '🇺🇸', 'United States'),
];

/// Country-code chip + local-number field, matching the design canvas's
/// phone input. Exposes the fully concatenated E.164 string via
/// [onChanged] and [e164Value] — screens should never need to do the
/// concatenation themselves.
class PhoneField extends StatefulWidget {
  final TextEditingController localNumberController;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final CountryCode initialCountry;

  const PhoneField({
    super.key,
    required this.localNumberController,
    this.onChanged,
    this.errorText,
    this.initialCountry = kDefaultCountry,
  });

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late CountryCode _country = widget.initialCountry;

  String get e164Value =>
      '${_country.dialCode}${widget.localNumberController.text.trim()}';

  void _notify() => widget.onChanged?.call(e164Value);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 13),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CountryCode>(
              value: _country,
              items: kCountryCodes
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text('${c.flagEmoji} ${c.dialCode}',
                            style: const TextStyle(fontSize: 14.5)),
                      ))
                  .toList(),
              onChanged: (c) {
                if (c == null) return;
                setState(() => _country = c);
                _notify();
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: widget.localNumberController,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 15.5, color: AppColors.ink),
            decoration: InputDecoration(
              labelText: 'PHONE NUMBER',
              hintText: '123456789',
              errorText: widget.errorText,
            ),
            onChanged: (_) => _notify(),
          ),
        ),
      ],
    );
  }
}
