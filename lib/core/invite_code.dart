import 'dart:math';

import 'package:flutter/services.dart';

/// Invite codes: 8 characters from an alphabet without look-alikes (no 0, O,
/// 1 or I), stored as `K7PMX3QD` and shown as `K7PM-X3QD`. Must match the
/// pattern in `database.rules.json` (`^[A-HJ-NP-Z2-9]{8}$`).
class InviteCode {
  InviteCode._();

  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 8;
  static final _valid = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

  /// A new random code. [Random.secure] is a cryptographically secure source,
  /// and the alphabet has exactly 32 characters, so every character is
  /// equally likely.
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => alphabet.codeUnitAt(r.nextInt(32))),
    );
  }

  /// The stored form of what a person typed ("k7pm x3qd", "K7PM-X3QD" …), or
  /// null when it can't be a valid code.
  static String? normalize(String input) {
    final code = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return _valid.hasMatch(code) ? code : null;
  }

  /// `K7PMX3QD` → `K7PM-X3QD`.
  static String format(String code) => code.length == length
      ? '${code.substring(0, 4)}-${code.substring(4)}'
      : code;
}

/// Upper-cases input, drops anything but letters/digits and inserts the dash
/// after four characters, so a code can be typed or pasted in any form.
class InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final clipped =
        raw.length > InviteCode.length ? raw.substring(0, InviteCode.length) : raw;
    final text = clipped.length > 4
        ? '${clipped.substring(0, 4)}-${clipped.substring(4)}'
        : clipped;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
