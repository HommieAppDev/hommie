import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class RealtorApiService {
  final String _base = dotenv.env['RAPIDAPI_URL']!;
  final String _host = dotenv.env['RAPIDAPI_HOST']!;
  final String _key  = dotenv.env['RAPIDAPI_KEY']!;

  Future<Map<String, dynamic>> searchBuy({
    String? city,
    String? state,
    String? zipcode,
    int resultsPerPage = 20,
    int page = 1,
  }) async {
    if (dotenv.env.isEmpty) await dotenv.load();
    late final String location;
    if ((zipcode ?? '').isNotEmpty) {
      location = 'zipcode:$zipcode';
    } else if ((city ?? '').isNotEmpty && (state ?? '').isNotEmpty) {
      location = 'city:$city, $state';
    } else if ((city ?? '').isNotEmpty) {
      location = 'city:$city';
    } else {
      throw ArgumentError('Provide zipcode or city/state');
    }

    final path = dotenv.env['RE_PATH_SEARCH_LOC'] ?? '/properties/search-buy';
    final uri = Uri.parse('$_base$path').replace(queryParameters: {
      'location': location,
      'resultsPerPage': resultsPerPage.toString(),
      'page': page.toString(),
    });

    debugPrint('SEARCH BUY: ' + uri.toString());

    final res = await http.get(
      uri,
      headers: {
        'x-rapidapi-host': _host,
        'x-rapidapi-key': _key,
      },
    );

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }
}
