import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// An image picked while offline, waiting to go to Cloudinary. When it is
/// uploaded, its URL is written to the school's database at
/// `{collection}/{recordId}/{field}` — e.g. `students/{id}/photoUrl` — or,
/// with no [recordId], `{collection}/{field}` (the school stamp:
/// `profile/stampUrl`).
class PendingUpload {
  const PendingUpload({
    required this.schoolId,
    required this.collection,
    required this.recordId,
    required this.fileName,
    required this.localPath,
    required this.createdAt,
    this.field = 'photoUrl',
  });

  final String schoolId;

  /// `students`, `teachers` or `profile`.
  final String collection;

  /// Empty for a school-level image (`profile`).
  final String recordId;

  /// The database field that receives the URL.
  final String field;
  final String fileName;
  final String localPath;
  final DateTime createdAt;

  /// One entry per target: a newer image replaces one still waiting.
  String get key => keyFor(collection, recordId, field);

  static String keyFor(String collection, String recordId, String field) =>
      recordId.isEmpty ? '$collection/$field' : '$collection/$recordId';

  factory PendingUpload.fromMap(Map<dynamic, dynamic> m) => PendingUpload(
        schoolId: (m['schoolId'] ?? '') as String,
        collection: (m['collection'] ?? '') as String,
        recordId: (m['recordId'] ?? '') as String,
        // Entries queued before stamps existed were all photos.
        field: (m['field'] ?? 'photoUrl') as String,
        fileName: (m['fileName'] ?? '') as String,
        localPath: (m['localPath'] ?? '') as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((m['createdAt'] ?? 0) as int),
      );

  Map<String, Object> toMap() => {
        'schoolId': schoolId,
        'collection': collection,
        'recordId': recordId,
        'field': field,
        'fileName': fileName,
        'localPath': localPath,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

/// Images waiting to upload (a Hive box) — student and teacher photos and the
/// school stamp — with a copy of each image in the app's documents directory
/// so it survives restarts. Phones only; web uploads directly as before.
class UploadQueue {
  UploadQueue._(this._box);

  static const _boxName = 'pending_uploads';
  static UploadQueue? _instance;

  /// Null until [init] has run (and always on web).
  static UploadQueue? get instance => _instance;

  final Box<Map> _box;

  /// Opens the box. Call once from `main()` after `Hive.initFlutter()`.
  static Future<void> init() async {
    if (kIsWeb || _instance != null) return;
    _instance = UploadQueue._(await Hive.openBox<Map>(_boxName));
  }

  /// Notifies whenever an image is queued or uploaded.
  ValueListenable<Box<Map>> listenable() => _box.listenable();

  List<PendingUpload> forSchool(String schoolId) => _box.values
      .map(PendingUpload.fromMap)
      .where((u) => u.schoolId == schoolId)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  int countFor(String? schoolId) =>
      schoolId == null ? 0 : forSchool(schoolId).length;

  /// The waiting photo file for the student or teacher [recordId], shown
  /// until it is uploaded.
  String? localPhoto(String recordId) {
    if (recordId.isEmpty) return null;
    for (final m in _box.values) {
      final u = PendingUpload.fromMap(m);
      if (u.recordId == recordId &&
          u.field == 'photoUrl' &&
          File(u.localPath).existsSync()) {
        return u.localPath;
      }
    }
    return null;
  }

  /// The waiting school-level image (e.g. `profile` / `stampUrl`) for
  /// [schoolId], or null.
  String? localSchoolImage(String schoolId, String collection, String field) {
    final m = _box.get(PendingUpload.keyFor(collection, '', field));
    if (m == null) return null;
    final u = PendingUpload.fromMap(m);
    return u.schoolId == schoolId && File(u.localPath).existsSync()
        ? u.localPath
        : null;
  }

  /// Queues [bytes] for `{collection}/{recordId}/{field}` (or
  /// `{collection}/{field}` when [recordId] is empty), replacing any image
  /// for that target still waiting.
  Future<void> addPhoto({
    required String schoolId,
    required String collection,
    required String recordId,
    required Uint8List bytes,
    required String fileName,
    String field = 'photoUrl',
  }) async {
    final now = DateTime.now();
    final dir = await _fileDir();
    final name = recordId.isEmpty ? field : recordId;
    // A new file name each time, so the image cache never shows an older one.
    final file = File('${dir.path}${Platform.pathSeparator}'
        '${collection}_${name}_${now.millisecondsSinceEpoch}${_ext(fileName)}');
    await file.writeAsBytes(bytes, flush: true);

    final upload = PendingUpload(
      schoolId: schoolId,
      collection: collection,
      recordId: recordId,
      field: field,
      fileName: fileName,
      localPath: file.path,
      createdAt: now,
    );
    final old = _box.get(upload.key);
    await _box.put(upload.key, upload.toMap());
    if (old != null) await _deleteFile(PendingUpload.fromMap(old).localPath);
  }

  /// Removes the entry and its file (after uploading, or when the record was
  /// deleted). Leaves a newer image for the same target alone.
  Future<void> remove(PendingUpload upload) async {
    final current = _box.get(upload.key);
    if (current != null &&
        PendingUpload.fromMap(current).localPath == upload.localPath) {
      await _box.delete(upload.key);
    }
    await _deleteFile(upload.localPath);
  }

  /// Drops the image waiting for a target, if any (a newer one was uploaded
  /// directly, or the image was removed).
  Future<void> cancel(String collection, String recordId,
      {String field = 'photoUrl'}) async {
    final current = _box.get(PendingUpload.keyFor(collection, recordId, field));
    if (current != null) await remove(PendingUpload.fromMap(current));
  }

  /// Every waiting image, for every school (sign-out).
  Future<void> clearAll() async {
    for (final m in _box.values.toList()) {
      await _deleteFile(PendingUpload.fromMap(m).localPath);
    }
    await _box.clear();
  }

  static Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Could not delete pending image $path: $e');
    }
  }

  static Future<Directory> _fileDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${docs.path}${Platform.pathSeparator}pending_uploads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '.jpg';
    return name.substring(dot).toLowerCase();
  }
}
