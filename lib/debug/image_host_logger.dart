import 'package:flutter/foundation.dart';

final Set<String> _loggedHosts = <String>{};

void logImageHost(String url) {
  if (!kDebugMode) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final host = uri.host;
  final scheme = uri.scheme;
  final looksThumb = uri.path.contains('thumb') || uri.path.contains('thumbnail') || uri.path.contains('small');
  final msg = 'IMG host: $scheme://$host  path=${uri.path}  thumbLike=$looksThumb';
  if (_loggedHosts.add('$scheme://$host')) {
    // first time we see this scheme+host, print it boldly
    debugPrint('=== $msg (NEW) ===');
  } else {
    debugPrint(msg);
  }
}
