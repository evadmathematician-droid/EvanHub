import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// True when the phone can actually reach the internet, not just a Wi-Fi or
/// data network: resolves Cloudinary's API host with a short timeout.
///
/// Web cannot do DNS lookups, so it is always treated as online there.
Future<bool> hasInternet({
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (kIsWeb) return true;
  try {
    final result = await InternetAddress.lookup('api.cloudinary.com')
        .timeout(timeout);
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Whether [e] means "the network dropped" (as opposed to the server
/// rejecting the request), so the post should be kept for a later retry.
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is http.ClientException;

/// Message for a failed upload that has to happen online (school cover and
/// badge, documents, teacher documents): plain words when the network is the
/// reason, the error itself otherwise.
String uploadFailedMessage(Object e) => isNetworkError(e)
    ? 'Uploading files needs internet. Connect and try again.'
    : 'Upload failed: $e';
