import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/core/image_url.dart';

void main() {
  const base = 'https://res.cloudinary.com/demo/image/upload/';
  const path = 'v1700000000/schools/abc/events/x.jpg';

  test('adds a non-cropping resize', () {
    expect(cloudinaryResized('$base$path', width: 900),
        '${base}w_900,c_limit,q_auto,f_auto/$path');
  });

  test('removes crop transformations already in the URL', () {
    expect(
        cloudinaryResized('${base}c_fill,g_auto,h_400,w_400/$path', width: 900),
        '${base}w_900,c_limit,q_auto,f_auto/$path');
    expect(cloudinaryResized('${base}c_crop,h_300/w_500/$path', width: 900),
        '${base}w_900,c_limit,q_auto,f_auto/$path');
  });

  test('keeps URLs without a version and non-Cloudinary URLs', () {
    expect(cloudinaryResized('${base}schools/abc/x.jpg', width: 900),
        '${base}w_900,c_limit,q_auto,f_auto/schools/abc/x.jpg');
    expect(cloudinaryResized('https://example.com/a.jpg', width: 900),
        'https://example.com/a.jpg');
  });
}
