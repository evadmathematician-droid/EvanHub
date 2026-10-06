import 'package:evangelistglobal/services/student_photo_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thumbnail: 300 px JPEG, replacing any transformation in the URL', () {
    expect(
      StudentPhotoCache.thumbnailUrl(
          'https://res.cloudinary.com/demo/image/upload/c_fill,w_200/v12/schools/a/p.png'),
      'https://res.cloudinary.com/demo/image/upload/w_300,c_limit,q_auto,f_jpg/v12/schools/a/p.png',
    );
    expect(
      StudentPhotoCache.thumbnailUrl(
          'https://res.cloudinary.com/demo/image/upload/v12/p.jpg'),
      'https://res.cloudinary.com/demo/image/upload/w_300,c_limit,q_auto,f_jpg/v12/p.jpg',
    );
  });

  test('non-Cloudinary photos are used as they are', () {
    expect(StudentPhotoCache.thumbnailUrl('https://example.com/p.jpg'),
        'https://example.com/p.jpg');
  });
}
