import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/event_sync_service.dart';
import '../services/pending_event_store.dart';
import '../state/auth_controller.dart';
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
  }

  @override
  void dispose() {
    _uploadedSub?.cancel();
    _eventSync?.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: _auth,
      child: MaterialApp.router(
        title: 'EvanHub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        scaffoldMessengerKey: _messengerKey,
        routerConfig: _router,
      ),
    );
  }
}
