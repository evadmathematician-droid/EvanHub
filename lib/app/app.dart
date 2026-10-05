import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../force_update/force_update_gate.dart';
import '../services/event_sync_service.dart';
import '../services/pending_event_store.dart';
import '../services/upload_queue.dart';
import '../services/upload_sync_service.dart';
import '../state/auth_controller.dart';
import '../state/sync_monitor.dart';
import '../theme/app_theme.dart';
import 'router.dart';

class EvangelistGlobalApp extends StatefulWidget {
  const EvangelistGlobalApp({super.key});

  @override
  State<EvangelistGlobalApp> createState() => _EvangelistGlobalAppState();
}

class _EvangelistGlobalAppState extends State<EvangelistGlobalApp> {
  late final AuthController _auth;
  late final GoRouter _router;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  EventSyncService? _eventSync;
  UploadSyncService? _uploadSync;
  SyncMonitor? _syncMonitor;
  StreamSubscription<int>? _uploadedSub;

  @override
  void initState() {
    super.initState();
    _auth = AuthController();
    _router = buildRouter(_auth);

    final store = PendingEventStore.instance;
    if (store != null) {
      _eventSync = EventSyncService(_auth, store)..start();
      _uploadedSub = _eventSync!.uploaded.listen((count) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('$count pending post(s) uploaded.')),
        );
      });
    }

    // Offline-first (phones only): queued photos and the sync banner.
    final uploads = UploadQueue.instance;
    if (uploads != null) {
      _uploadSync = UploadSyncService(_auth, uploads)..start();
    }
    if (!kIsWeb) _syncMonitor = SyncMonitor(_auth)..start();
  }

  @override
  void dispose() {
    _uploadedSub?.cancel();
    _eventSync?.dispose();
    _uploadSync?.dispose();
    _syncMonitor?.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: _auth),
        // Null on web, where the sync banner is not shown.
        ChangeNotifierProvider<SyncMonitor?>.value(value: _syncMonitor),
      ],
      child: MaterialApp.router(
        title: 'EvanHub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        scaffoldMessengerKey: _messengerKey,
        routerConfig: _router,
        // Mandatory-update check runs before any app screen is built; an
        // outdated build only ever sees the update screen.
        builder: (context, child) => ForceUpdateGate(
          logo: const ResizeImage(AssetImage('assets/icon/app_icon.png'),
              width: 288),
          child: child!,
        ),
      ),
    );
  }
}
