/// Inserts a Cloudinary delivery transformation (resize + auto quality/format)
/// after `/upload/` so lists and banners request a smaller image than the
/// full-resolution original. Non-Cloudinary URLs are returned unchanged.
///
/// `c_limit` only shrinks images wider than [width] and never crops. Any
/// transformation already in the URL (e.g. `c_fill,g_auto,h_400`, which cuts
/// the picture) is removed first, so the whole image is always delivered.
String cloudinaryResized(String url, {required int width}) {
  const marker = '/upload/';
  final at = url.indexOf(marker);
  if (at == -1) return url;
  final split = at + marker.length;
  return '${url.substring(0, split)}w_$width,c_limit,q_auto,f_auto/'
      '${_withoutTransformations(url.substring(split))}';
}

/// A transformation segment: comma-separated `key_value` parts such as
/// `c_fill,w_300,g_auto`. (Version `v123…` and folder names don't match.)
final _transformation = RegExp(r'^[a-z]{1,3}_[^/,]+(,[a-z]{1,3}_[^/,]+)*$');

String _withoutTransformations(String path) {
  final parts = path.split('/');
  var i = 0;
  while (i < parts.length - 1 && _transformation.hasMatch(parts[i])) {
    i++;
  }
  return parts.sublist(i).join('/');
}
