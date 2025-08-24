import 'dart:convert';
import 'package:http/http.dart' as http;

class TikTokMeta {
  final String authorName;
  final String? authorUrl;
  final String thumbnailUrl;
  final String title;

  TikTokMeta({
    required this.authorName,
    required this.thumbnailUrl,
    required this.title,
    this.authorUrl,
  });
}

class TikTokOEmbed {
  static final Map<String, TikTokMeta> _cache = {};

  static Future<TikTokMeta?> fetch(String videoUrl) async {
    if (_cache.containsKey(videoUrl)) return _cache[videoUrl];
    final uri = Uri.parse(
      'https://www.tiktok.com/oembed?url=${Uri.encodeComponent(videoUrl)}',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final data = json.decode(res.body) as Map<String, dynamic>;
    final meta = TikTokMeta(
      authorName: (data['author_name'] ?? '') as String,
      authorUrl: (data['author_url'] ?? '') as String?,
      thumbnailUrl: (data['thumbnail_url'] ?? '') as String,
      title: (data['title'] ?? '') as String,
    );
    _cache[videoUrl] = meta;
    return meta;
  }
}
