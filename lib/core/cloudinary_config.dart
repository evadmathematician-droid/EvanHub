/// Cloudinary account settings for heavy files (school documents, logos).
///
/// Uploads use an UNSIGNED preset, so no API secret ever ships in the app. The
/// preset must be created in Cloudinary (Settings → Upload → Upload presets) with
/// signing mode set to "Unsigned".
class CloudinaryConfig {
  const CloudinaryConfig._();

  static const cloudName = 'yal4fg9h';
  static const uploadPreset = 'upload_preset';
}
