// lib/utils/web_download_web.dart
// Web-only implementation using dart:html for CSV blob download.

import 'dart:html' as html;

void downloadCsvBytes(List<int> bytes, String filename) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
