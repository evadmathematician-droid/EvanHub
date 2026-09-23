import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/announcement.dart';

class AnnouncementService {
  AnnouncementService(this._refs);

  final TenantRefs _refs;

  Stream<List<Announcement>> watchAll() {
    return watchList(_refs.announcements, Announcement.fromMap).map(
      (list) => list
        ..sort((a, b) => (b.createdAt ?? DateTime.now())
            .compareTo(a.createdAt ?? DateTime.now())),
    );
  }

  Future<String> create(Announcement announcement) async {
    final ref = _refs.announcements.push();
    await ref.set(announcement.toMap());
    return ref.key!;
  }

  Future<void> delete(String id) => _refs.announcements.child(id).remove();
}
