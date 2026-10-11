/// Phone numbers as people in Sierra Leone type them: `079150079`,
/// `079 150 079`, `+23279150079` or `23279150079`.
///
/// [normalizePhone] returns the international form used for `tel:` and
/// WhatsApp links (`+23279150079`), or null when [input] doesn't look like a
/// phone number. Spaces, dashes, dots and brackets are ignored; a leading `0`
/// means Sierra Leone (+232). Other countries' numbers are accepted when
/// typed with `+` or `00`.
String? normalizePhone(String input) {
  var digits = input.trim().replaceAll(RegExp(r'[\s\-.()]'), '');
  if (digits.isEmpty) return null;
  var international = false;
  if (digits.startsWith('+')) {
    international = true;
    digits = digits.substring(1);
  } else if (digits.startsWith('00')) {
    international = true;
    digits = digits.substring(2);
  }
  if (!RegExp(r'^[0-9]+$').hasMatch(digits)) return null;

  // Sierra Leone: 0 + 8 digits locally, 232 + 8 digits internationally.
  if (!international && digits.startsWith('0') && digits.length == 9) {
    return '+232${digits.substring(1)}';
  }
  if (digits.startsWith('232')) {
    return digits.length == 11 ? '+$digits' : null;
  }
  // An 8-digit number without the leading 0.
  if (!international && digits.length == 8) return '+232$digits';
  if (international && digits.length >= 8 && digits.length <= 15) {
    return '+$digits';
  }
  return null;
}

/// Form validator: [required] numbers must be present; any number given must
/// look like a phone number.
String? phoneProblem(String? value, {bool required = false}) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return required ? 'Required' : null;
  return normalizePhone(v) == null
      ? 'Enter a phone number, e.g. 079 150 079 or +232 79 150 079'
      : null;
}
