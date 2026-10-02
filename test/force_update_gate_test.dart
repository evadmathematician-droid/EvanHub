import 'package:evangelistglobal/force_update/force_update_gate.dart';
import 'package:evangelistglobal/force_update/force_update_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns a fixed result instead of calling Firebase / the platform.
class _FakeManager extends ForceUpdateManager {
  _FakeManager(this.status);

  ForceUpdateStatus status;
  int updateCalls = 0;

  @override
  Future<ForceUpdateResult> check() async => ForceUpdateResult(
        status: status,
        installedVersionCode: 3,
        installedVersionName: '1.0.0',
        policy: const ForceUpdatePolicy(
          minVersionCode: 5,
          forceUpdate: true,
          updateMessage: 'Please update now',
        ),
        fromNetwork: true,
      );

  @override
  Stream<void> onPolicyChanged() => const Stream.empty();

  @override
  Future<bool> startUpdate(ForceUpdatePolicy policy) async {
    updateCalls++;
    return true;
  }
}

Widget _app(_FakeManager manager) => MaterialApp(
      builder: (context, child) => ForceUpdateGate(
        manager: manager,
        enforce: true,
        child: child!,
      ),
      home: const Scaffold(body: Text('APP HOME')),
    );

void main() {
  testWidgets('outdated build sees only the update screen', (tester) async {
    final manager = _FakeManager(ForceUpdateStatus.updateRequired);
    await tester.pumpWidget(_app(manager));
    await tester.pumpAndSettle();

    expect(find.text('APP HOME'), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Please update now'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.textContaining('1.0.0 (3)', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('build 5 or newer', findRichText: true),
        findsOneWidget);
    // One button only: no Later / Skip / Close.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(CloseButton), findsNothing);
    expect(find.byType(BackButton), findsNothing);

    // System Back is swallowed and the block stays.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('APP HOME'), findsNothing);

    // Update Now starts the update, then checks again: still outdated.
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(manager.updateCalls, 1);
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('supported build sees the app', (tester) async {
    await tester.pumpWidget(_app(_FakeManager(ForceUpdateStatus.allowed)));
    await tester.pumpAndSettle();
    expect(find.text('APP HOME'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('becomes usable once a resume check finds a supported build',
      (tester) async {
    final manager = _FakeManager(ForceUpdateStatus.updateRequired);
    await tester.pumpWidget(_app(manager));
    await tester.pumpAndSettle();
    expect(find.text('APP HOME'), findsNothing);

    manager.status = ForceUpdateStatus.allowed;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('APP HOME'), findsOneWidget);
  });

  testWidgets('maintenance mode blocks with a Try again button',
      (tester) async {
    await tester.pumpWidget(_app(_FakeManager(ForceUpdateStatus.maintenance)));
    await tester.pumpAndSettle();
    expect(find.text('APP HOME'), findsNothing);
    expect(find.text('Under maintenance'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
