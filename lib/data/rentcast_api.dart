// lib/data/rentcast_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class RentcastApi {
  final String apiKey;
  RentcastApi(this.apiKey);

  /// Wraps GET /v1/listings/sale
  ///
  /// Notes:
  /// - `city/state/zipCode` OR `latitude/longitude(+radiusMiles)` can be used.
  /// - Some feature flags (garage/pool/etc.) aren’t supported by RentCast; keep them
  ///   in your UI but they won’t change the API query unless RentCast adds them.
  Future<List<Map<String, dynamic>>> getForSaleListings({
    // Location
    String? city,
    String? state,              // e.g., "MD"
    String? zipCode,            // e.g., "21043"
    double? latitude,
    double? longitude,
    double? radiusMiles,        // miles

    // Beds / baths
    int? bedrooms,              // exact
    double? bathrooms,          // can be fractional

    // Price & size
    int? minPrice,
    int? maxPrice,
    int? minSqft,
    int? maxSqft,

    // Year built
    int? minYear,
    int? maxYear,

    // Status / type
    String? status,             // e.g. "Active"
    String? propertyType,       // e.g. "Single Family", "Condo"

    // Sorting (if supported)
    String? sort,               // e.g. "price" | "listDate"
    String? order,              // "asc" | "desc"

    // Paging
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };

    // Location
    if (zipCode != null && zipCode.isNotEmpty) params['zipCode'] = zipCode;
    if (city != null && city.isNotEmpty) params['city'] = city;
    if (state != null && state.isNotEmpty) params['state'] = state;

    if (latitude != null && longitude != null) {
      params['latitude'] = '$latitude';
      params['longitude'] = '$longitude';
      if (radiusMiles != null) params['radius'] = '$radiusMiles';
    }

    // Beds / baths
    if (bedrooms != null) params['bedrooms'] = '$bedrooms';
    if (bathrooms != null) params['bathrooms'] = '$bathrooms';

    // Price & size
    if (minPrice != null) params['minPrice'] = '$minPrice';
    if (maxPrice != null) params['maxPrice'] = '$maxPrice';
    if (minSqft != null) params['minSqft'] = '$minSqft';
    if (maxSqft != null) params['maxSqft'] = '$maxSqft';

    // Year built
    if (minYear != null) params['minYear'] = '$minYear';
    if (maxYear != null) params['maxYear'] = '$maxYear';

    // Status / type
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (propertyType != null && propertyType.isNotEmpty) {
      params['propertyType'] = propertyType;
    }

    // Sorting
    if (sort != null && sort.isNotEmpty) params['sort'] = sort;
    if (order != null && order.isNotEmpty) params['order'] = order;

    final uri = Uri.https('api.rentcast.io', '/v1/listings/sale', params);
    final res = await http.get(uri, headers: {'X-Api-Key': apiKey});

    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return (data is List) ? data.cast<Map<String, dynamic>>() : const [];
    } else if (res.statusCode == 404) {
      // Valid request, no results
      return const [];
    }

    throw Exception('RentCast ${res.statusCode}: ${res.body}');
  }
}
