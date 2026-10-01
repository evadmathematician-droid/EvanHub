import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/cloudinary_config.dart';

/// Result of a successful Cloudinary upload.
class CloudinaryUpload {
  final String publicId;
  final String url;
  final int bytes;

  const CloudinaryUpload({
    required this.publicId,
    required this.url,
    required this.bytes,
  });
}

/// Unsigned uploads to Cloudinary (see [CloudinaryConfig]). Used for documents,
/// student/teacher photos and event images.
class CloudinaryService {
  CloudinaryService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// Uploads [bytes] into [folder]. When [publicId] is given, the asset gets
  /// that fixed name, so uploading the same item again (a retry) returns the
  /// existing asset instead of creating a duplicate.
  Future<CloudinaryUpload> upload({
    required Uint8List bytes,
    required String fileName,
    required String folder,
    String? publicId,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/auto/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
      ..fields['folder'] = folder;
    if (publicId != null) request.fields['public_id'] = publicId;
    request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName));

    final response = await http.Response.fromStream(await _http.send(request));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final message = (body['error'] as Map?)?['message'] ?? response.body;
      throw Exception('Cloudinary upload failed: $message');
    }
    return CloudinaryUpload(
      publicId: body['public_id'] as String? ?? '',
      url: body['secure_url'] as String? ?? '',
      bytes: (body['bytes'] as num?)?.toInt() ?? bytes.lengthInBytes,
    );
  }
}
