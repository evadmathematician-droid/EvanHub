import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    _auth = AuthController();
    _router = buildRouter(_auth);
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: _auth,
      child: MaterialApp.router(
        title: 'Evangelist Global',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
