import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'core/offline_write.dart';
import 'firebase_options.dart';
import 'services/delete_guard_store.dart';
import 'services/pending_event_store.dart';
import 'services/session_cache.dart';
import 'services/upload_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In release builds a widget that fails to build shows a small neutral box
  // instead of Flutter's grey/red error box. The error is still reported (it
  // prints in the console), and debug builds keep the full red error so
  // problems are never hidden during development.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const _NeutralErrorBox();
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Offline-first (phones only): the database keeps a copy of everything the
  // app has read on disk, answers listeners from it with no internet, and
  // queues writes until the connection returns. Must run before anything
  // else uses the database. Web stays online-only.
  if (!kIsWeb) {
    try {
      FirebaseDatabase.instance
        ..setPersistenceEnabled(true)
        ..setPersistenceCacheSizeBytes(50 * 1024 * 1024);
    } catch (e) {
      debugPrint('Database persistence unavailable: $e');
    }
  }

  // Local storage: the saved session (opens the app offline), the count of
  // changes waiting to sync, photos waiting to upload, offline event posts
  // and the delete-password lockout. If it can't open, the app still runs —
  // it just needs the internet to open, post, upload and keep the lockout.
  try {
    await Hive.initFlutter();
    await SessionCache.init();
    await PendingWrites.init();
    await UploadQueue.init();
    await PendingEventStore.init();
    await DeleteGuardStore.init();
  } catch (e) {
    debugPrint('Local storage unavailable: $e');
  }

  runApp(const EvangelistGlobalApp());
}

/// Release-mode stand-in for a widget that failed to build. Uses no Material
/// or Directionality ancestors, since it can appear anywhere in the tree.
class _NeutralErrorBox extends StatelessWidget {
  const _NeutralErrorBox();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE2E5EA),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFF9AA1AC),
          size: 28,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}
