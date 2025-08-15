import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

Future<void> logImageUrlIssues(String url) async {
  final uri = Uri.tryParse(url);
  print('[ImageLog] URL: $url');
  if (uri == null) {
    print('[ImageLog] Invalid URI');
    return;
  }
  print('[ImageLog] Scheme: ${uri.scheme}');
  print('[ImageLog] Host: ${uri.host}');
  final lower = url.toLowerCase();
  print('[ImageLog] Contains thumb: ${lower.contains('thumb') || lower.contains('thumbnail')}');
  print('[ImageLog] Contains small: ${lower.contains('small')}');
  print('[ImageLog] Has w= param: ${uri.queryParameters.containsKey('w')}');
  print('[ImageLog] Has h= param: ${uri.queryParameters.containsKey('h')}');
  try {
    final req = await HttpClient().headUrl(uri).timeout(const Duration(seconds: 5));
    final resp = await req.close();
    print('[ImageLog] HEAD status: ${resp.statusCode}');
  } catch (e) {
    print('[ImageLog] HEAD request failed: $e');
  }
}
