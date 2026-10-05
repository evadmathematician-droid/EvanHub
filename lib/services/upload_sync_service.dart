import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/internet_check.dart';
import '../core/offline_write.dart';
import '../core/tenant/tenant_refs.dart';
import '../state/auth_controller.dart';
import 'cloudinary_service.dart';
import 'upload_queue.dart';

/// Uploads photos queued offline ([UploadQueue]) and writes each one's URL
/// into its record.
///
/// Runs when the app starts, when the user signs in, when a photo is queued,
/// when the app returns to the foreground and whenever the network changes —
/// each time only after a real internet check. Only photos for the signed-in
/// user's school are sent. A photo whose record was deleted in the meantime
/// is dropped, so no half-empty record is ever created.
class UploadSyncService with WidgetsBindingObserver {
  UploadSyncService(this._auth, this._queue, {CloudinaryService? cloudinary})
      : _cloudinary = cloudinary ?? CloudinaryService();

  final AuthController _auth;
  final UploadQueue _queue;
  final CloudinaryService _cloudinary;

  static const _uploadTimeout = Duration(seconds: 60);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _running = false;
  String? _lastReadyUid;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) syncNow();
    });
    _queue.listenable().addListener(_onQueueChanged);
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _queue.listenable().removeListener(_onQueueChanged);
    _auth.removeListener(_onAuthChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  /// A photo was queued (or one finished; then there is nothing new to do
  /// and [syncNow] returns at once).
  void _onQueueChanged() => syncNow();

  /// Syncs once each time a user becomes ready (app start or sign-in).
  void _onAuthChanged() {
    final uid =
        _auth.status == AuthStatus.ready ? _auth.appUser?.uid : null;
    if (uid != null && uid != _lastReadyUid) syncNow();
    _lastReadyUid = uid;
  }

  /// Uploads every waiting photo for the current school. Returns how many
  /// were uploaded. A failed photo stays queued and the rest still run.
  Future<int> syncNow() async {
    if (_running) return 0;
    final schoolId = _auth.schoolId;
    if (_auth.status != AuthStatus.ready || schoolId == null) return 0;
    if (_queue.countFor(schoolId) == 0) return 0;

    _running = true;
    var done = 0;
    try {
      if (!await hasInternet()) return 0;
      final refs = TenantRefs(schoolId);
      for (final item in _queue.forSchool(schoolId)) {
        try {
          if (await _upload(refs, item)) done++;
        } catch (e) {
          debugPrint('Photo for ${item.key} not uploaded yet: $e');
        }
      }
    } finally {
      _running = false;
    }
    return done;
  }

  Future<bool> _upload(TenantRefs refs, PendingUpload item) async {
    // The record that receives the URL: a student / teacher, or the school
    // profile itself for the stamp.
    final collection = refs.school.child(item.collection);
    final record =
        item.recordId.isEmpty ? collection : collection.child(item.recordId);
    final file = File(item.localPath);
    if (!(await readOnce(record)).exists || !await file.exists()) {
      debugPrint('Image for ${item.key} dropped: record or file is gone.');
      await _queue.remove(item);
      return false;
    }

    final folder = switch (item.collection) {
      'teachers' => refs.teacherPhotoFolder,
      'profile' => refs.schoolProfileFolder,
      _ => refs.studentPhotoFolder,
    };
    final name = item.recordId.isEmpty ? item.field : item.recordId;
    final upload = await _cloudinary
        .upload(
          bytes: await file.readAsBytes(),
          fileName: item.fileName,
          folder: folder,
          // Fixed name per image: a retry after a dropped connection reuses
          // the asset instead of creating a duplicate.
          publicId: '${name}_${item.createdAt.millisecondsSinceEpoch}',
        )
        .timeout(_uploadTimeout);
    await commitWrite(record.child(item.field).set(upload.url));
    await _queue.remove(item);
    return true;
  }
}
