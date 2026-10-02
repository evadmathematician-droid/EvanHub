import 'package:evangelistglobal/force_update/force_update_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideForceUpdate', () {
    const required5 = ForceUpdatePolicy(minVersionCode: 5, forceUpdate: true);

    test('older build is blocked when force_update is on', () {
      expect(
        decideForceUpdate(installedVersionCode: 4, policy: required5),
        ForceUpdateStatus.updateRequired,
      );
    });

    test('equal and newer builds are allowed', () {
      expect(decideForceUpdate(installedVersionCode: 5, policy: required5),
          ForceUpdateStatus.allowed);
      expect(decideForceUpdate(installedVersionCode: 12, policy: required5),
          ForceUpdateStatus.allowed);
    });

    test('compares integers, not text (10 is newer than 9)', () {
      const required10 =
          ForceUpdatePolicy(minVersionCode: 10, forceUpdate: true);
      expect(decideForceUpdate(installedVersionCode: 9, policy: required10),
          ForceUpdateStatus.updateRequired);
      expect(decideForceUpdate(installedVersionCode: 10, policy: required10),
          ForceUpdateStatus.allowed);
    });

    test('force_update off never blocks', () {
      const off = ForceUpdatePolicy(minVersionCode: 99);
      expect(decideForceUpdate(installedVersionCode: 1, policy: off),
          ForceUpdateStatus.allowed);
    });

    test('defaults (no policy fetched yet) never block', () {
      expect(
        decideForceUpdate(
            installedVersionCode: 1, policy: const ForceUpdatePolicy()),
        ForceUpdateStatus.allowed,
      );
    });

    test('unknown installed version is not locked out', () {
      expect(decideForceUpdate(installedVersionCode: 0, policy: required5),
          ForceUpdateStatus.allowed);
    });

    test('maintenance blocks every build', () {
      const maintenance = ForceUpdatePolicy(maintenanceMode: true);
      expect(decideForceUpdate(installedVersionCode: 999, policy: maintenance),
          ForceUpdateStatus.maintenance);
    });
  });

  group('ForceUpdatePolicy saved copy', () {
    test('round-trips through the saved string form', () {
      const policy = ForceUpdatePolicy(
        minVersionCode: 7,
        latestVersionCode: 9,
        forceUpdate: true,
        updateMessage: 'Please update',
        playStoreUrl: 'https://play.google.com/store/apps/details?id=x',
        apkUrl: 'https://example.com/app.apk?a=1&b=2',
        maintenanceMode: false,
        maintenanceMessage: '',
      );
      // Same encoding as ForceUpdateManager._save / _saved: values are
      // stored as text.
      final asText = {
        for (final e in policy.toJson().entries) e.key: '${e.value}',
      };
      final back = ForceUpdatePolicy.fromJson(asText);
      expect(back.minVersionCode, 7);
      expect(back.latestVersionCode, 9);
      expect(back.forceUpdate, isTrue);
      expect(back.updateMessage, 'Please update');
      expect(back.apkUrl, 'https://example.com/app.apk?a=1&b=2');
      expect(back.maintenanceMode, isFalse);
    });

    test('bad saved values fall back to non-blocking defaults', () {
      final back = ForceUpdatePolicy.fromJson(
          {'min_version_code': 'abc', 'force_update': 'maybe'});
      expect(back.minVersionCode, 0);
      expect(back.forceUpdate, isFalse);
    });
  });
}
