import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mandatory-update policy, read from Firebase Remote Config. Only admins can
/// change it (Firebase Console → Remote Config); the app never writes it.
///
/// Keys (create all of them in the Firebase Console):
///
/// | key                   | type    | meaning                                  |
/// |-----------------------|---------|------------------------------------------|
/// | `min_version_code`    | Number  | lowest build number allowed to run       |
/// | `latest_version_code` | Number  | newest published build (shown only)      |
/// | `force_update`        | Boolean | master switch for [min_version_code]     |
/// | `update_message`      | String  | text on the update screen                |
/// | `playstore_url`       | String  | store page for Play installs             |
/// | `apk_url`             | String  | direct APK link for sideloaded installs  |
/// | `maintenance_mode`    | Boolean | blocks every version while true          |
/// | `maintenance_message` | String  | text on the maintenance screen           |
///
/// Version *codes* (the `+N` build number in pubspec.yaml, `versionCode` on
/// Android) are compared as integers. Version names like "1.10.0" are never
/// compared.
@immutable
class ForceUpdatePolicy {
  const ForceUpdatePolicy({
    this.minVersionCode = 0,
    this.latestVersionCode = 0,
    this.forceUpdate = false,
    this.updateMessage = '',
    this.playStoreUrl = '',
    this.apkUrl = '',
    this.maintenanceMode = false,
    this.maintenanceMessage = '',
  });

  static const keyMinVersionCode = 'min_version_code';
  static const keyLatestVersionCode = 'latest_version_code';
  static const keyForceUpdate = 'force_update';
  static const keyUpdateMessage = 'update_message';
  static const keyPlayStoreUrl = 'playstore_url';
  static const keyApkUrl = 'apk_url';
  static const keyMaintenanceMode = 'maintenance_mode';
  static const keyMaintenanceMessage = 'maintenance_message';

  /// Values used before the first successful fetch: nothing is blocked.
  static const Map<String, Object> defaults = {
    keyMinVersionCode: 0,
    keyLatestVersionCode: 0,
    keyForceUpdate: false,
    keyUpdateMessage: '',
    keyPlayStoreUrl: '',
    keyApkUrl: '',
    keyMaintenanceMode: false,
    keyMaintenanceMessage: '',
  };

  final int minVersionCode;
  final int latestVersionCode;
  final bool forceUpdate;
  final String updateMessage;
  final String playStoreUrl;
  final String apkUrl;
  final bool maintenanceMode;
  final String maintenanceMessage;

  factory ForceUpdatePolicy.fromRemoteConfig(FirebaseRemoteConfig rc) {
    return ForceUpdatePolicy(
      minVersionCode: rc.getInt(keyMinVersionCode),
      latestVersionCode: rc.getInt(keyLatestVersionCode),
      forceUpdate: rc.getBool(keyForceUpdate),
      updateMessage: rc.getString(keyUpdateMessage).trim(),
      playStoreUrl: rc.getString(keyPlayStoreUrl).trim(),
      apkUrl: rc.getString(keyApkUrl).trim(),
      maintenanceMode: rc.getBool(keyMaintenanceMode),
      maintenanceMessage: rc.getString(keyMaintenanceMessage).trim(),
    );
  }

  Map<String, Object> toJson() => {
        keyMinVersionCode: minVersionCode,
        keyLatestVersionCode: latestVersionCode,
        keyForceUpdate: forceUpdate,
        keyUpdateMessage: updateMessage,
        keyPlayStoreUrl: playStoreUrl,
        keyApkUrl: apkUrl,
        keyMaintenanceMode: maintenanceMode,
        keyMaintenanceMessage: maintenanceMessage,
      };

  factory ForceUpdatePolicy.fromJson(Map<String, Object?> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    bool asBool(Object? v) => v == true || v == 'true';
    String asString(Object? v) => v is String ? v : '';
    return ForceUpdatePolicy(
      minVersionCode: asInt(json[keyMinVersionCode]),
      latestVersionCode: asInt(json[keyLatestVersionCode]),
      forceUpdate: asBool(json[keyForceUpdate]),
      updateMessage: asString(json[keyUpdateMessage]),
      playStoreUrl: asString(json[keyPlayStoreUrl]),
      apkUrl: asString(json[keyApkUrl]),
      maintenanceMode: asBool(json[keyMaintenanceMode]),
      maintenanceMessage: asString(json[keyMaintenanceMessage]),
    );
  }
}

/// What the gate must show.
enum ForceUpdateStatus {
  /// Still checking (first launch only).
  checking,

  /// This build may be used.
  allowed,

  /// This build is below `min_version_code` while `force_update` is on.
  updateRequired,

  /// `maintenance_mode` is on: nobody may use the app right now.
  maintenance,
}

/// Result of one check.
@immutable
class ForceUpdateResult {
  const ForceUpdateResult({
    required this.status,
    required this.installedVersionCode,
    required this.installedVersionName,
    required this.policy,
    required this.fromNetwork,
  });

  final ForceUpdateStatus status;
  final int installedVersionCode;
  final String installedVersionName;
  final ForceUpdatePolicy policy;

  /// False when the policy came from the copy saved on the phone because the
  /// fetch failed (offline, timeout, throttled).
  final bool fromNetwork;
}

/// The decision itself, kept free of plugins so it can be unit-tested.
///
/// An unknown installed version code (0 or less, e.g. a build without a
/// number) is never blocked by [ForceUpdatePolicy.minVersionCode], because a
/// wrong lock-out is worse than a missed one.
ForceUpdateStatus decideForceUpdate({
  required int installedVersionCode,
  required ForceUpdatePolicy policy,
}) {
  if (policy.maintenanceMode) return ForceUpdateStatus.maintenance;
  if (policy.forceUpdate &&
      installedVersionCode > 0 &&
      installedVersionCode < policy.minVersionCode) {
    return ForceUpdateStatus.updateRequired;
  }
  return ForceUpdateStatus.allowed;
}

/// Checks the installed build against the Remote Config policy and performs
/// the update. Reusable: copy the `lib/force_update/` folder into another
/// project, add the four packages (firebase_remote_config, package_info_plus,
/// shared_preferences, in_app_update — plus url_launcher) and wrap the app
/// with `ForceUpdateGate`.
class ForceUpdateManager {
  ForceUpdateManager({
    FirebaseRemoteConfig? remoteConfig,
    this.fetchTimeout = const Duration(seconds: 10),
    this.minimumFetchInterval = const Duration(minutes: 15),
    this.prefsKey = 'force_update.policy.v1',
  }) : _rcOverride = remoteConfig;

  final FirebaseRemoteConfig? _rcOverride;

  /// How long one fetch may take before the saved policy is used instead.
  final Duration fetchTimeout;

  /// Remote Config throttles frequent fetches; within this interval the last
  /// fetched values are reused. Changes still arrive at once through
  /// [onPolicyChanged] (real-time updates) while the app is open.
  final Duration minimumFetchInterval;

  /// Where the last fetched policy is saved for offline checks.
  final String prefsKey;

  FirebaseRemoteConfig get _rc => _rcOverride ?? FirebaseRemoteConfig.instance;

  bool _configured = false;
  PackageInfo? _info;

  /// Installed build number (`versionCode` on Android). 0 if unknown.
  Future<int> installedVersionCode() async =>
      int.tryParse((await _packageInfo()).buildNumber) ?? 0;

  Future<PackageInfo> _packageInfo() async =>
      _info ??= await PackageInfo.fromPlatform();

  Future<void> _configure() async {
    if (_configured) return;
    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: fetchTimeout,
      minimumFetchInterval: minimumFetchInterval,
    ));
    await _rc.setDefaults(ForceUpdatePolicy.defaults);
    _configured = true;
  }

  /// Fetches the policy (falling back to the saved copy when that fails) and
  /// decides whether this build may run.
  Future<ForceUpdateResult> check() async {
    final info = await _packageInfo();
    final code = int.tryParse(info.buildNumber) ?? 0;

    ForceUpdatePolicy policy;
    var fromNetwork = false;
    try {
      await _configure();
      // The SDK's own timeout covers the request; this one also covers a
      // plugin that never answers.
      await _rc.fetchAndActivate().timeout(fetchTimeout + const Duration(seconds: 2));
      policy = ForceUpdatePolicy.fromRemoteConfig(_rc);
      // Only a fetch that reached Firebase counts as fresh. Inside the
      // minimum fetch interval the SDK returns the last fetched values, which
      // are just as valid.
      fromNetwork = _rc.lastFetchStatus == RemoteConfigFetchStatus.success;
      if (fromNetwork) await _save(policy);
    } catch (e) {
      debugPrint('Force update: fetch failed, using saved policy: $e');
      policy = await _saved();
    }

    // A failed fetch can leave the SDK on its defaults; never let that undo a
    // saved block. The saved copy only ever came from Firebase.
    if (!fromNetwork) {
      final saved = await _saved();
      if (saved.minVersionCode > policy.minVersionCode ||
          (saved.forceUpdate && !policy.forceUpdate) ||
          (saved.maintenanceMode && !policy.maintenanceMode)) {
        policy = saved;
      }
    }

    return ForceUpdateResult(
      status: decideForceUpdate(installedVersionCode: code, policy: policy),
      installedVersionCode: code,
      installedVersionName: info.version,
      policy: policy,
      fromNetwork: fromNetwork,
    );
  }

  /// Fires when an admin publishes a Remote Config change while the app is
  /// open (real-time updates). The caller should run [check] again.
  Stream<void> onPolicyChanged() async* {
    try {
      await _configure();
    } catch (e) {
      debugPrint('Force update: real-time updates unavailable: $e');
      return;
    }
    yield* _rc.onConfigUpdated
        .asyncMap((_) => _rc.activate())
        .map((_) {})
        .handleError((Object e) =>
            debugPrint('Force update: real-time update error: $e'));
  }

  Future<void> _save(ForceUpdatePolicy policy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = policy.toJson();
      await prefs.setStringList(prefsKey, [
        for (final e in p.entries) '${e.key}=${e.value}',
      ]);
    } catch (e) {
      debugPrint('Force update: could not save policy: $e');
    }
  }

  Future<ForceUpdatePolicy> _saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(prefsKey);
      if (list == null) return const ForceUpdatePolicy();
      final json = <String, Object?>{};
      for (final line in list) {
        final at = line.indexOf('=');
        if (at > 0) json[line.substring(0, at)] = line.substring(at + 1);
      }
      return ForceUpdatePolicy.fromJson(json);
    } catch (e) {
      debugPrint('Force update: could not read saved policy: $e');
      return const ForceUpdatePolicy();
    }
  }

  /// True when the app was installed by the Google Play Store.
  Future<bool> installedFromPlay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return (await _packageInfo()).installerStore == 'com.android.vending';
  }

  /// "Update Now". Play installs get Google Play's full-screen (IMMEDIATE)
  /// update; if that is unavailable, fails or is cancelled — or the app was
  /// sideloaded — the store page or APK link opens instead.
  ///
  /// Returns false if nothing could be opened. Either way the gate checks
  /// the version again when the user comes back.
  Future<bool> startUpdate(ForceUpdatePolicy policy) async {
    final fromPlay = await installedFromPlay();
    if (fromPlay) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable &&
            info.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          if (result == AppUpdateResult.success) return true;
        }
      } catch (e) {
        debugPrint('Force update: in-app update failed: $e');
      }
    }

    final packageName = (await _packageInfo()).packageName;
    final storeFallback =
        'https://play.google.com/store/apps/details?id=$packageName';
    final candidates = fromPlay
        ? [policy.playStoreUrl, storeFallback]
        : [policy.apkUrl, policy.playStoreUrl, storeFallback];

    for (final url in candidates) {
      final uri = Uri.tryParse(url);
      if (url.isEmpty || uri == null || !uri.hasScheme) continue;
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('Force update: could not open $url: $e');
      }
    }
    return false;
  }
}
