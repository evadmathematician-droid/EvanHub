import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'firebase_options.dart';
import 'services/delete_guard_store.dart';
import 'services/pending_event_store.dart';

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

  // Local storage: offline event posts and the delete-password lockout. If it
  // can't open, the app still runs — posting just needs the internet and the
  // lockout lasts only until the app closes.
  try {
    await Hive.initFlutter();
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
