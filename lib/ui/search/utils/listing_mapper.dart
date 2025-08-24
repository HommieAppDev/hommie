


class ListingView {
  final Map<String, dynamic> raw;
  ListingView(this.raw);
  factory ListingView.fromMap(Map<String, dynamic> map) => ListingView(map);

  // --- Robust field extraction ---
  Map<String, dynamic> get _addr => raw['address'] as Map<String, dynamic>? ?? {};
  Map<String, dynamic> get _desc => raw['description'] as Map<String, dynamic>? ?? {};

  String get id =>
    (raw['property_id']?.toString() ?? raw['listing_id']?.toString() ?? raw['id']?.toString() ?? '');

  dynamic get price => raw['price'] ?? _desc['list_price'] ?? _desc['price'] ?? null;
  int? get beds => raw['beds'] ?? _desc['beds'] ?? null;
  double? get baths {
    final b = raw['baths'] ?? _desc['baths'] ?? null;
    if (b == null) return null;
    if (b is int) return b.toDouble();
    if (b is double) return b;
    return double.tryParse(b.toString());
  }
  int? get sqft => raw['sqft'] ?? _desc['sqft'] ?? null;

  // --- Formatters ---
  static String formatPrice(dynamic price) {
    if (price == null) return "N/A";
    final intPrice = (price is int) ? price : int.tryParse(price.toString()) ?? 0;
    return "\$" + intPrice.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
  String get priceLabel => formatPrice(price);

  static String formatAddress(Map? address) {
    if (address == null) return "Unknown Address";
    String line = address["line"]?.toString() ?? "";
    String city = address["city"]?.toString() ?? "";
    String state = address["state_code"]?.toString() ?? "";
    String zip = address["postal_code"]?.toString() ?? "";
    if (line.isNotEmpty) return "$line, $city, $state $zip".trim();
    if (city.isNotEmpty) return "$city, $state $zip".trim();
    return "Unknown Address";
  }
  String get addressLine => formatAddress(_addr);

  String get addressCityState {
    final city = _addr['city']?.toString().trim() ?? '';
    final state = _addr['state_code']?.toString().trim() ?? _addr['state']?.toString().trim() ?? '';
    final postal = _addr['postal_code']?.toString().trim() ?? '';
    final segs = <String>[];
    if (city.isNotEmpty) segs.add(city);
    if (state.isNotEmpty) segs.add(state);
    if (postal.isNotEmpty) segs.add(postal);
    return segs.join(', ');
  }

  String get bedsLabel => beds == null ? '- bd' : '${beds} bd';
  String get bathsLabel {
    final b = baths;
    if (b == null) return '- ba';
    final isInt = (b % 1) == 0;
    return isInt ? '${b.toInt()} ba' : '${b.toStringAsFixed(1)} ba';
  }
  String get sqftLabel {
    final s = sqft;
    if (s == null) return '- sqft';
    if (s >= 1000) return '${(s / 1000).toStringAsFixed(2)}K sqft';
    return '${s} sqft';
  }

  // --- Media ---
  List<String> get photoUrls {
    final photos = raw['photos'] as List? ?? [];
    final urls = <String>[];
    for (final p in photos) {
      if (p is Map && p['href'] != null) {
        urls.add(_hiRes(p['href'].toString()));
      } else if (p is String) {
        urls.add(_hiRes(p));
      }
    }
    return urls;
  }

  String? get virtualTourUrl {
    final tours = raw['virtual_tours'] as List? ?? [];
    for (final t in tours) {
      if (t is Map && t['url'] != null && t['url'].toString().isNotEmpty) {
        return t['url'].toString();
      } else if (t is String && t.isNotEmpty) {
        return t;
      }
    }
    // Fallback: check description
    final descTour = _desc['virtual_tour_url']?.toString();
    if (descTour != null && descTour.isNotEmpty) return descTour;
    return null;
  }

  String _hiRes(String url) {
    // RDCPix: ...s.jpg small -> try original 'od.jpg' if present
    if (url.contains('rdcpix.com') && url.endsWith('s.jpg')) {
      return url.replaceFirst(RegExp(r's\.jpg$'), 'od.jpg');
    }
    return url;
  }
}
