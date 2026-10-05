import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/offline_write.dart';
import '../services/pending_event_store.dart';
import '../services/upload_queue.dart';
import '../state/auth_controller.dart';
import '../state/sync_monitor.dart';

/// Every sign-out button goes through here. Signing out clears everything
/// waiting on this phone (see [AuthController.signOut]), so when there is
/// anything unsynced the user is warned first and can cancel. Offline, they
/// are also told that signing in again needs the internet.
Future<void> confirmSignOut(BuildContext context) async {
  final auth = context.read<AuthController>();
  if (kIsWeb) return auth.signOut();

  final unsynced = unsyncedCount(auth);
  final online = context.read<SyncMonitor?>()?.online ?? true;
  if (unsynced == 0 && online) return auth.signOut();

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(unsynced > 0 ? 'Unsynced changes' : 'You are offline'),
      content: Text([
        if (unsynced > 0)
          'You have $unsynced unsynced '
              '${unsynced == 1 ? 'change' : 'changes'}. Connect to the '
              'internet first or ${unsynced == 1 ? 'it' : 'they'} will be '
              'lost.',
        if (!online) 'Signing in again will need the internet.',
      ].join('\n\n')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: unsynced > 0
              ? TextButton.styleFrom(foregroundColor: Colors.red.shade700)
              : null,
          child: Text(unsynced > 0 ? 'Sign out anyway' : 'Sign out'),
        ),
      ],
    ),
  );
  if (ok == true) await auth.signOut();
}

/// Changes, photos and event posts on this phone that have not reached the
/// server yet for the signed-in user's school.
int unsyncedCount(AuthController auth) {
  final schoolId = auth.schoolId;
  final uid = auth.appUser?.uid;
  final events = schoolId == null
      ? 0
      : (PendingEventStore.instance?.forSchool(schoolId) ?? const [])
          .where((e) => e.authorUid == uid)
          .length;
  return PendingWrites.instance.count +
      (UploadQueue.instance?.countFor(schoolId) ?? 0) +
      events;
}
