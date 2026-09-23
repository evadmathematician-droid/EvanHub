import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// Shows an "Are you sure?" dialog. Returns true only when the user confirms.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
      ],
    ),
  );
  return ok == true;
}

/// Runs [delete] and reports the outcome in a SnackBar: [done] on success, a
/// plain-English message on failure. Returns true when the delete succeeded.
///
/// The messenger is captured up front, so the SnackBar still shows when the
/// caller pops its screen right after.
Future<bool> runDelete(
  BuildContext context,
  Future<void> Function() delete, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await delete();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } catch (e) {
    debugPrint('Delete failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    return false;
  }
}

/// Plain-English message for a failed save. The database rules re-check every
/// field and the admission-number / NIN indexes, so a rejection usually means
/// a value is out of range or the number was just taken by someone else.
String saveErrorMessage(Object e) {
  debugPrint('Save failed: $e');
  if (e is FirebaseException && e.code == 'permission-denied') {
    return 'The database rejected this save. The number may have just been '
        'taken by another record, or a field has a value that is not '
        'allowed. Check the form and try again.';
  }
  return 'Save failed. Check your connection and try again.';
}

String _friendly(Object e) {
  if (e is FirebaseException && e.code == 'permission-denied') {
    return "You don't have permission to delete this.";
  }
  return 'Could not delete. Check your connection and try again.';
}
