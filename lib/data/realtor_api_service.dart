// lib/data/realtor_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RealtorApiService {
  RealtorApiService();

  // Host & key from .env
  final String _host = (dotenv.env['RAPIDAPI_HOST'] ?? 'realtor-search.p.rapidapi.com').trim();
  final String _key  = (dotenv.env['RAPIDAPI_KEY']  ?? '').trim();

  // Endpoint paths (safe defaults; override via .env to match your provider)
  String get _pathSearchBuy  => (dotenv.env['RE_PATH_SEARCH_LOC']  ?? '/properties/search-buy').trim();
  String get _pathSearchRent => (dotenv.env['RE_PATH_SEARCH_RENT'] ?? '/properties/search-rent').trim();
  String get _pathDetail     => (dotenv.env['RE_PATH_DETAIL']      ?? '/properties/detail').trim();

  Uri _uri(String path, [Map<String, dynamic>? params]) =>
      Uri.parse('https://$_host$path')
          .replace(queryParameters: params?.map((k, v) => MapEntry(k, '$v')));

  Map<String, String> get _headers => {
        'x-rapidapi-key': _key,
        'x-rapidapi-host': _host,
      };

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? params]) async {
    final res = await http.get(_uri(path, params), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Realtor API error ${res.statusCode} on $path\n'
      'Host: $_host\n'
      'Body: ${res.body}\n'
      'Tip: Open RapidAPI → Endpoints and copy exact paths into .env (RE_PATH_*).',
    );
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  /// Provider wants a single `location` string.
  /// ZIP -> `postal_code:21044`, City/State -> `city:Columbia, MD`, State -> `state_code:MD`.
  String? _buildLocation({String? zip, String? city, String? state}) {
    if (zip != null && zip.isNotEmpty) return 'postal_code:$zip';
    if (city != null && city.isNotEmpty && state != null && state.isNotEmpty) {
      return 'city:$city, $state';
    }
    if (city != null && city.isNotEmpty) return 'city:$city';
    if (state != null && state.isNotEmpty) return 'state_code:$state';
    return null;
  }

  /// Tries common envelopes (many RapidAPI realtor proxies use these).
  List<dynamic> _extractArray(Map<String, dynamic> body) {
    // flat lists
    for (final k in const ['results', 'listings', 'properties', 'homes']) {
      final v = body[k];
      if (v is List) return v;
    }
    // data.* lists
    final data = body['data'];
    if (data is Map) {
      for (final k in const ['results', 'listings', 'properties', 'homes']) {
        final v = data[k];
        if (v is List) return v;
      }
      // common GraphQL-like: data.home_search.results
      final hs = data['home_search'];
      if (hs is Map && hs['results'] is List) return hs['results'] as List;
    }
    // response.* lists
    final resp = body['response'];
    if (resp is Map) {
      for (final k in const ['results', 'listings', 'properties', 'homes']) {
        final v = resp[k];
        if (v is List) return v;
      }
    }
    return const [];
  }

  // --------------------------------------------------------------------------
  // Mapping to unified shape (tailored to your sample)
  // --------------------------------------------------------------------------
  Map<String, dynamic> mapListing(dynamic item) {
    if (item is! Map) return {};
    num? _num(v) => (v is num) ? v : num.tryParse(v?.toString() ?? '');
    String? _str(v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    // ----- Photos -----
    final photos = <String>[];
    void addPhoto(dynamic v) {
      if (v == null) return;
      String? s;
      if (v is String) {
        s = v.trim();
      } else if (v is Map) {
        final href = v['href'];
        if (href is String) s = href.trim();
      }
      if (s == null || s.isEmpty) return;
      if (s.startsWith('//')) s = 'https:$s';
      if (s.startsWith('http://')) s = s.replaceFirst('http://', 'https://');
      if (s.startsWith('https://')) photos.add(s);
    }

    // primary_photo { href }
    addPhoto(item['primary_photo']);
    // photos: [{href}, ...] or strings
    final ph = item['photos'];
    if (ph is List) {
      for (final p in ph) addPhoto(p);
    }
    // a few common alternates
    for (final k in const [
      'photo_urls', 'images', 'media', 'photoUrls', 'primaryPhoto', 'primaryPhotoUrl', 'imageUrl',
      'photo', 'thumbnail', 'thumbnailUrl'
    ]) {
      addPhoto(item[k]);
    }

    // ----- Address / Coordinates (from your sample) -----
    final location = (item['location'] is Map) ? item['location'] as Map : const {};
    final addrMap = (location['address'] is Map) ? location['address'] as Map : const {};
    final coord   = (addrMap['coordinate'] is Map) ? addrMap['coordinate'] as Map : const {};

    final addrLine  = addrMap['line'] ?? addrMap['address_line'];
    final addrCity  = addrMap['city'];
    final addrState = addrMap['state_code'] ?? addrMap['state'];
    final addrZip   = addrMap['postal_code'];

    // ----- Beds / Baths / Sqft / Price / Type (from description map) -----
    final descMap = (item['description'] is Map) ? item['description'] as Map : const {};
    final bedsVal = _num(descMap['beds']) ?? _num(item['beds']) ?? _num(item['bedrooms']);
    final bathsCalc = (() {
      final total = _num(descMap['baths']);
      if (total != null) return total;
      final full   = _num(descMap['baths_full_calc']) ?? 0;
      final half   = _num(descMap['baths_partial_calc']) ?? 0;
      if (full != 0 || half != 0) return full + (half * 0.5);
      return _num(item['baths']) ?? _num(item['bathrooms']);
    })();
    final sqftVal = _num(descMap['sqft']) ?? _num(item['sqft']) ?? _num(item['living_area']);
    final lotSqft = _num(descMap['lot_sqft']) ?? _num(item['lot_sqft']) ?? _num(item['lot_size']);
    final price   = _num(item['list_price']) ?? _num(item['price']) ?? _num(item['price_raw']);
    final type    = _str(descMap['type']) ?? _str(item['property_type']) ?? _str(item['prop_type']);

    // ----- Features (nice-to-have: flatten details[].text) -----
    String? featuresText;
    final details = item['details'];
    if (details is List && details.isNotEmpty) {
      final pieces = <String>[];
      for (final d in details) {
        if (d is Map && d['text'] is List) {
          for (final t in (d['text'] as List)) {
            if (t is String && t.trim().isNotEmpty) pieces.add(t.trim());
          }
        }
      }
      if (pieces.isNotEmpty) {
        // Keep it modest; don’t dump 100 lines into one field
        featuresText = pieces.take(30).join(' • ');
      }
    }

    // ----- Lat/Lon (from address.coordinate) with fallbacks -----
    final lat = coord['lat'] ?? item['lat'] ?? item['latitude'];
    final lon = coord['lon'] ?? item['lon'] ?? item['lng'] ?? item['longitude'];

    // ----- MLS id / provider bits (can help later in details) -----
    final source = (item['source'] is Map) ? item['source'] as Map : const {};
    final mlsId  = source['listing_id'] ?? item['listing_id'];

    // Formatted address for easy display / mapping to Maps
    final formatted = [
      if ((addrLine ?? '').toString().trim().isNotEmpty) addrLine,
      if ((addrCity ?? '').toString().trim().isNotEmpty || (addrState ?? '').toString().trim().isNotEmpty)
        [addrCity, addrState].where((e) => (e ?? '').toString().trim().isNotEmpty).join(', '),
      if ((addrZip ?? '').toString().trim().isNotEmpty) addrZip,
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).join(', ');

    return {
      'id'    : (item['property_id'] ?? item['id'] ?? mlsId ?? '').toString(),
      'mlsId' : (mlsId ?? '').toString(),
      'status': item['status'],
      'price' : price,
      'beds'  : bedsVal,
      'baths' : bathsCalc,
      'sqft'  : sqftVal,
      'lot_sqft': lotSqft,
      'type'  : type,
      // Intentionally keep `description` a string (avoid putting Maps here).
      'description': null, // this feed’s "description" is a Map of stats; we avoid junk text
      'features': featuresText, // handy for keyword filters ("pool", "basement", etc.)
      'lat'   : (lat is num) ? lat.toDouble() : _num(lat)?.toDouble(),
      'lon'   : (lon is num) ? lon.toDouble() : _num(lon)?.toDouble(),
      'address': {
        'line' : (addrLine  ?? '').toString(),
        'city' : (addrCity  ?? '').toString(),
        'state': (addrState ?? '').toString(),
        'zip'  : (addrZip   ?? '').toString(),
      },
      'formattedAddress': formatted,
      'photos': photos.toSet().toList(),
    };
  }

  // --------------------------------------------------------------------------
  // Public search methods
  // --------------------------------------------------------------------------

  /// City/State/ZIP search (provider requires a single `location` query param).
  Future<List<Map<String, dynamic>>> searchByLocation({
    String? zip,
    String? city,
    String? state,
    String status = 'for_sale', // or 'for_rent'
    String? propertyType,
    int? beds,
    double? baths,
    int limit = 50,
    int offset = 0,
    String? sortField, // provider uses "relevance", etc.
    String? sortDir,
  }) async {
    final path = (status == 'for_rent') ? _pathSearchRent : _pathSearchBuy;
    final location = _buildLocation(zip: zip, city: city, state: state);

    final params = <String, dynamic>{
      if (location != null) 'location': location,
      'limit': limit,
      'offset': offset,
      if (propertyType != null && propertyType.isNotEmpty) 'property_type': propertyType,
      if (beds != null) 'beds_min': beds,
      if (baths != null) 'baths_min': baths,
      if (sortField != null) 'sortBy': sortField,     // provider key
      if (sortField != null) 'sort_field': sortField, // generic fallback
      if (sortDir != null) 'sort_dir': sortDir,
    };

    final body = await _get(path, params);
    final raw = _extractArray(body);
    return raw.map<Map<String, dynamic>>((e) => mapListing(e)).toList();
  }

  /// Map/geo search using the same search endpoint: `location=lat:..,lon:..,radius:10mi`
  Future<List<Map<String, dynamic>>> searchByCoordinates({
    required double lat,
    required double lon,
    double radiusMiles = 10,
    String status = 'for_sale',
    String? propertyType,
    int? beds,
    double? baths,
    int limit = 50,
    int offset = 0,
  }) async {
    final path = (status == 'for_rent') ? _pathSearchRent : _pathSearchBuy;
    final geo = 'lat:$lat,lon:$lon,radius:${radiusMiles}mi';

    final params = <String, dynamic>{
      'location': geo,
      'limit': limit,
      'offset': offset,
      if (propertyType != null && propertyType.isNotEmpty) 'property_type': propertyType,
      if (beds != null) 'beds_min': beds,
      if (baths != null) 'baths_min': baths,
    };

    final body = await _get(path, params);
    final raw = _extractArray(body);
    return raw.map<Map<String, dynamic>>((e) => mapListing(e)).toList();
  }

  /// Details by property id.
  Future<Map<String, dynamic>> getListingDetails(String propertyId) async {
    // Try a couple of param names, most proxies expect "property_id".
    for (final params in [
      {'property_id': propertyId},
      {'id': propertyId},
      {'listing_id': propertyId},
    ]) {
      try {
        final body = await _get(_pathDetail, params);
        final arr = _extractArray(body);
        if (arr.isNotEmpty) return mapListing(arr.first);
        final data = body['data'];
        if (data is Map) return mapListing(data);
        return mapListing(body);
      } catch (_) {
        // try next param name
      }
    }
    throw Exception('Details failed for id=$propertyId. Verify RE_PATH_DETAIL in .env matches your RapidAPI endpoint.');
  }

  // --------------------------------------------------------------------------
  // Raw helpers (for debugging / “Copy sample” in Results title long-press)
  // --------------------------------------------------------------------------
  Future<List<dynamic>> searchByLocationRaw({
    String? zip,
    String? city,
    String? state,
    String status = 'for_sale',
    int limit = 20,
    int offset = 0,
  }) async {
    final path = (status == 'for_rent') ? _pathSearchRent : _pathSearchBuy;
    final location = _buildLocation(zip: zip, city: city, state: state);
    final body = await _get(path, {
      if (location != null) 'location': location,
      'limit': limit,
      'offset': offset,
    });
    return _extractArray(body);
  }
}
