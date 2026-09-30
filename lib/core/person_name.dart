import 'package:flutter/services.dart';

/// Person names (students, teachers, guardians, admins) are saved in Title
/// Case: the first letter of each word upper case, the rest lower case, one
/// space between words and none at the ends. Each part of a hyphenated name
/// is capitalised too.
///
///   titleCaseName('aBU bAKARR  kamara') == 'Abu Bakarr Kamara'
///   titleCaseName(' sesay-KAMARA ')     == 'Sesay-Kamara'
String titleCaseName(String input) => _caseWords(
      input.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' '),
    );

/// True when [name] is already saved the way [titleCaseName] would save it.
bool isTitleCaseName(String name) => name == titleCaseName(name);

/// Validator for a middle name: optional, at most two words
/// (e.g. "Abu Bakarr").
String? middleNameProblem(String? value) {
  final words =
      (value ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.length > 2 ? 'Up to two words' : null;
}

/// Upper-cases the first letter of each word and lower-cases the rest,
/// changing nothing else. Keeps the length the same so a text field's cursor
/// stays where it was.
String _caseWords(String s) {
  final out = StringBuffer();
  var wordStart = true;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch.trim().isEmpty || ch == '-') {
      out.write(ch);
      wordStart = true;
      continue;
    }
    final cased = wordStart ? ch.toUpperCase() : ch.toLowerCase();
    // A few letters change length when cased (ß → SS); leave those alone.
    out.write(cased.length == ch.length ? cased : ch);
    wordStart = false;
  }
  return out.toString();
}

/// Shows names in Title Case as the user types. Spaces are left alone while
/// typing (so the user can type the next word); [titleCaseName] tidies them
/// when the record is saved.
class NameCaseFormatter extends TextInputFormatter {
  const NameCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _caseWords(newValue.text);
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }
}

/// Input formatters for every person-name field.
const nameInputFormatters = <TextInputFormatter>[NameCaseFormatter()];
