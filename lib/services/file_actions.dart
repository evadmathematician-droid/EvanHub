import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Opening, saving, sharing and printing files the app creates or downloads.
/// On the web there is no file system or "open with", so opening and saving
/// both download the file.
class FileActions {
  FileActions._();

  /// Downloads [url] (e.g. a Cloudinary document).
  static Future<Uint8List> download(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException('Download failed (HTTP ${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  /// Opens the file in the phone's app for its type (PDF viewer, Word,
  /// Excel …). Throws with a readable message when no app can open it.
  static Future<void> open(String fileName, Uint8List bytes) async {
    if (kIsWeb) {
      await save(fileName, bytes);
      return;
    }
    final file = await _writeTemp(fileName, bytes);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw FileActionException(result.type == ResultType.noAppToOpen
          ? 'No app on this phone can open ${_extension(fileName)} files. '
              'Use Save or Share instead.'
          : 'Could not open the file (${result.message}).');
    }
  }

  /// Lets the user pick where to save the file (e.g. Downloads). Returns
  /// false when they cancel.
  static Future<bool> save(String fileName, Uint8List bytes,
      {String mimeType = 'application/octet-stream'}) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: 'Save $fileName',
    );
    return saved != null || kIsWeb;
  }

  /// Opens the share sheet (WhatsApp, email, Drive …).
  static Future<void> share(String fileName, Uint8List bytes,
      {String? mimeType, String? text}) async {
    final XFile file;
    if (kIsWeb) {
      file = XFile.fromData(bytes, name: fileName, mimeType: mimeType);
    } else {
      final temp = await _writeTemp(fileName, bytes);
      file = XFile(temp.path, name: fileName, mimeType: mimeType);
    }
    await SharePlus.instance.share(ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      subject: fileName,
      text: text,
    ));
  }

  /// Shows the system print dialog for a PDF (it can also save as PDF).
  static Future<void> printPdf(String fileName, Uint8List pdfBytes) =>
      Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName);

  static Future<File> _writeTemp(String fileName, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    return file.writeAsBytes(bytes, flush: true);
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? 'these' : fileName.substring(dot).toUpperCase();
  }
}

/// A file problem to show the user as-is.
class FileActionException implements Exception {
  const FileActionException(this.message);

  final String message;

  @override
  String toString() => message;
}
