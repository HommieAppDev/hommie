import 'dart:convert';
import 'package:http/http.dart' as http;

class PhotoService {
  static const String _apiKey = '6e8eba1931mshec1dfe69d2531e8p1d27f1jsne9fc93163395';
  static const String _apiHost = 'realtor-search.p.rapidapi.com';

  static Future<List<String>> fetchHiResPhotoUrls({required String propertyId, required String listingId}) async {
    final url = Uri.https(_apiHost, '/property/get-photos', {
      'property_id': '{"property_id": "$propertyId", "listing_id": "$listingId"}',
    });
    final res = await http.get(url, headers: {
      'X-Rapidapi-Key': _apiKey,
      'X-Rapidapi-Host': _apiHost,
    });
    if (res.statusCode != 200) return [];
    final data = json.decode(res.body);
    final photos = data['photos'] as List? ?? [];
    final urls = <String>[];
    for (final p in photos) {
      if (p is Map) {
        final candidates = [p['xxl'], p['xl'], p['hires'], p['full'], p['url'], p['src'], p['href']];
        for (final c in candidates) {
          if (c != null && c is String && c.startsWith('http')) {
            urls.add(c);
            break;
          }
        }
      } else if (p is String && p.startsWith('http')) {
        urls.add(p);
      }
    }
    return urls;
  }
}
