import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/internet_check.dart';
import 'public_lookup_service.dart';

/// Why the school list could not be shown.
enum SchoolListProblem {
  offline('Lookup needs internet. Check your connection and try again.'),
  notSetUp('Lookup is not set up yet on the server. Please contact the '
      'app administrator.'),
  empty('No schools are registered yet.'),
  failed('Could not load the list of schools. Try again.');

  const SchoolListProblem(this.message);
  final String message;
}

/// The public school list for Look Up, loaded once and shared. The login
/// screen starts it in the background, so the list is usually ready by the
/// time Look Up opens. The last good list is kept on the device and shown
/// at once next time, while a fresh copy loads from the server.
class SchoolDirectory extends ChangeNotifier {
  SchoolDirectory._();

  static final instance = SchoolDirectory._();

  static const _cacheKey = 'lookup_public_schools_v2';

  List<PublicSchool>? _schools;
  bool _loading = false;
  SchoolListProblem? _problem;
  Future<void>? _running;
  bool _freshThisRun = false;

  /// The list to show (cached or fresh), or null when there is none yet.
  List<PublicSchool>? get schools => _schools;
  bool get loading => _loading;

  /// Set only when there is no list to show.
  SchoolListProblem? get problem => _problem;

  /// Loads from the server unless a fresh list was already loaded in this
  /// run. [force] reloads anyway (the Try Again button).
  Future<void> load({bool force = false}) {
    if (!force && _freshThisRun) return Future.value();
    return _running ??= _load().whenComplete(() => _running = null);
  }

  Future<void> _load() async {
    _loading = true;
    _problem = null;
    if (_schools == null) await _readCache();
    notifyListeners();

    SchoolListProblem? problem;
    try {
      if (!await hasInternet()) {
        problem = SchoolListProblem.offline;
      } else {
        final fresh = await PublicLookupService.loadSchools();
        _schools = fresh;
        _freshThisRun = true;
        if (fresh.isEmpty) problem = SchoolListProblem.empty;
        unawaited(_writeCache(fresh));
      }
    } on LookupOfflineException {
      problem = SchoolListProblem.offline;
    } on LookupNotSetUpException {
      problem = SchoolListProblem.notSetUp;
    } catch (e) {
      debugPrint('Lookup school list failed: $e');
      problem = SchoolListProblem.failed;
    }

    // A saved list still lets people choose a school; the search itself
    // reports a missing connection.
    final hasList = (_schools ?? const []).isNotEmpty;
    _problem = hasList && problem != SchoolListProblem.empty ? null : problem;
    _loading = false;
    notifyListeners();
  }

  Future<void> _readCache() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (raw == null) return;
      _schools = [
        for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          PublicSchool.fromMap('${m['id']}', m),
      ];
    } catch (e) {
      debugPrint('Saved school list unreadable: $e');
    }
  }

  Future<void> _writeCache(List<PublicSchool> schools) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _cacheKey,
        jsonEncode([
          for (final s in schools) {'id': s.id, ...s.toMap()},
        ]),
      );
    } catch (e) {
      debugPrint('School list not saved: $e');
    }
  }
}
