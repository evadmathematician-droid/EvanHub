/// A school event saved on this phone while offline, waiting to be uploaded.
///
/// [id] is the Realtime Database push key generated on the phone, and is
/// reused as the event's key (and the Cloudinary public id) when it uploads, so
/// a retry never creates a second copy.
class PendingEvent {
  final String id;
  final String schoolId;
  final String title;
  final String text;
  final String authorUid;
  final DateTime createdAt;

  /// Copy of the image in the app's documents directory; '' when no image.
  final String imagePath;
  final String imageName;

  const PendingEvent({
    required this.id,
    required this.schoolId,
    required this.title,
    required this.text,
    required this.authorUid,
    required this.createdAt,
    this.imagePath = '',
    this.imageName = '',
  });

  factory PendingEvent.fromMap(Map<dynamic, dynamic> data) {
    String s(String key) => (data[key] ?? '') as String;
    return PendingEvent(
      id: s('id'),
      schoolId: s('schoolId'),
      title: s('title'),
      text: s('text'),
      authorUid: s('authorUid'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['createdAt'] as num?)?.toInt() ?? 0),
      imagePath: s('imagePath'),
      imageName: s('imageName'),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'schoolId': schoolId,
        'title': title,
        'text': text,
        'authorUid': authorUid,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'imagePath': imagePath,
        'imageName': imageName,
      };
}
