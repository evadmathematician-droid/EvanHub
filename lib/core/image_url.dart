/// Inserts a Cloudinary delivery transformation (resize + auto quality/format)
/// after `/upload/` so lists and banners request a smaller image than the
/// full-resolution original. Non-Cloudinary URLs are returned unchanged.
String cloudinaryResized(String url, {required int width}) {
  const marker = '/upload/';
  final at = url.indexOf(marker);
  if (at == -1) return url;
  final split = at + marker.length;
  return '${url.substring(0, split)}w_$width,c_limit,q_auto,f_auto/'
      '${url.substring(split)}';
}
