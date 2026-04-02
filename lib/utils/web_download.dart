// lib/utils/web_download.dart
// Conditional import — picks the web implementation on web, stub on native.
export 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';
