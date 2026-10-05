import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/pending_event.dart';

/// Events saved on this phone while offline (a Hive box), plus a copy of each
/// image in the app's documents directory — gallery and cache paths can
/// disappear before the phone is back online.
///
/// Entries for every school and user on this phone live in one box; callers
/// filter by `schoolId` (and the sync by `authorUid`).
class PendingEventStore {
  PendingEventStore._(this._box);

  static const _boxName = 'pending_events';
  static PendingEventStore? _instance;

  /// Null until [init] has run (and always on web, which posts directly).
  static PendingEventStore? get instance => _instance;

  final Box<Map> _box;

  /// Opens the box. Call once from `main()` after `Hive.initFlutter()`.
  static Future<void> init() async {
    if (kIsWeb || _instance != null) return;
    _instance = PendingEventStore._(await Hive.openBox<Map>(_boxName));
  }

  /// Notifies whenever a pending event is added or removed.
  ValueListenable<Box<Map>> listenable() => _box.listenable();

  /// Every pending event on this phone, oldest first (upload order).
  List<PendingEvent> all() {
    final list = _box.values.map(PendingEvent.fromMap).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Pending events for one school, newest first (display order).
  List<PendingEvent> forSchool(String schoolId) =>
      all().where((e) => e.schoolId == schoolId).toList().reversed.toList();

  /// Saves a post, copying [imageBytes] into the documents directory.
  Future<PendingEvent> save({
    required String id,
    required String schoolId,
    required String title,
    required String text,
    required String authorUid,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    var imagePath = '';
    if (imageBytes != null) {
      final dir = await _imageDir();
      final file = File('${dir.path}${Platform.pathSeparator}$id${_ext(imageName)}');
      await file.writeAsBytes(imageBytes, flush: true);
      imagePath = file.path;
    }
    final event = PendingEvent(
      id: id,
      schoolId: schoolId,
      title: title,
      text: text,
      authorUid: authorUid,
      createdAt: DateTime.now(),
      imagePath: imagePath,
      imageName: imageName ?? '',
    );
    await _box.put(id, event.toMap());
    return event;
  }

  /// The saved image, or null when there is none (or the file has gone).
  Future<Uint8List?> readImage(PendingEvent event) async {
    if (event.imagePath.isEmpty) return null;
    final file = File(event.imagePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Removes the entry and its image file. The sync calls this only after the
  /// database write has succeeded.
  Future<void> remove(PendingEvent event) async {
    await _box.delete(event.id);
    if (event.imagePath.isEmpty) return;
    try {
      final file = File(event.imagePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Could not delete pending image ${event.imagePath}: $e');
    }
  }

  /// Every pending post and its image, for every school (sign-out).
  Future<void> clearAll() async {
    for (final event in all()) {
      await remove(event);
    }
    await _box.clear();
  }

  static Future<Directory> _imageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${docs.path}${Platform.pathSeparator}pending_events');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _ext(String? name) {
    final dot = name?.lastIndexOf('.') ?? -1;
    if (name == null || dot == -1 || dot == name.length - 1) return '.jpg';
    return name.substring(dot).toLowerCase();
  }
}
