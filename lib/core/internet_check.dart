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
