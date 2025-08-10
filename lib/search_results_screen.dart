// lib/search_results_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'data/rentcast_api.dart';

// Top-level helper class (cannot be nested inside a class in Dart)
class _Addr {
  final String? line, city, state, zip;
  const _Addr(this.line, this.city, this.state, this.zip);
}

class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key});
  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  // API client using .env key
  late final RentcastApi _rentcast =
      RentcastApi(dotenv.env['RENTCAST_API_KEY'] ?? '');

  // UI
  bool _loading = true;
  bool _mapView = false;
  bool _loadingMore = false;

  // Data
  List<Map<String, dynamic>> _listings = [];
  int _offset = 0;
  static const int _pageSize = 50;

  // Query (from args)
  String? _city;
  String? _state;
  String? _zip;
  double _radiusMiles = 10;
  int? _beds;
  double? _baths;

  // extras filtered client-side
  int? _minPrice;
  int? _maxPrice;
  int? _minSqft;
  String? _propertyType;
  bool? _hasGarage;

  // Map + debounce
  final _mapController = MapController();
  Timer? _debounce;

  // Simple cache by rounded center+radius
  final Map<String, List<Map<String, dynamic>>> _cache = {};

  bool _gotArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gotArgs) return;

    final a = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
    _city = a['city'] as String?;
    _state = a['state'] as String?;
    _zip = a['zip'] as String?;
    _radiusMiles = (a['radiusMiles'] as num?)?.toDouble() ?? 10.0;

    _beds = a['beds'] as int?;
    _baths = (a['baths'] is int)
        ? (a['baths'] as int).toDouble()
        : (a['baths'] as num?)?.toDouble();

    _minPrice = (a['minPrice'] ?? a['priceMin']) as int?;
    _maxPrice = (a['maxPrice'] ?? a['priceMax']) as int?;
    _minSqft = (a['minSqft'] ?? a['squareFootage']) as int?;
    _propertyType = a['propertyType'] as String?;
    _hasGarage = (a['hasGarage'] ?? a['garage']) as bool?;

    _gotArgs = true;
    _fetch(reset: true);
  }

  // ---------------- Fetching ----------------
  Future<void> _fetch({bool reset = false, double? centerLat, double? centerLng}) async {
    if ((_rentcast.apiKey).isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing Rentcast API key.')),
        );
      }
      return;
    }

    if (reset) {
      setState(() {
        _loading = true;
        _offset = 0;
      });
    }

    final lat = centerLat;
    final lng = centerLng;

    // Cache key (~2 decimals so nearby pans reuse)
    final key = (lat != null && lng != null)
        ? _tileKey(lat, lng, _radiusMiles)
        : 'CS:${_city ?? ''}|ST:${_state ?? ''}|ZIP:${_zip ?? ''}|R:$_radiusMiles'
          '|B:${_beds ?? '-'}|Ba:${_baths ?? '-'}|P:${_minPrice ?? '-'}-${_maxPrice ?? '-'}'
          '|SQ:${_minSqft ?? '-'}|T:${_propertyType ?? '-'}|G:${_hasGarage ?? '-'}|O:$_offset';

    if (reset && _cache.containsKey(key)) {
      setState(() {
        _listings = List<Map<String, dynamic>>.from(_cache[key]!);
        _loading = false;
      });
      return;
    }

    try {
      // your rentcast_api.dart supports these params
      var results = await _rentcast.getForSaleListings(
        city: (lat == null && _zip == null) ? _city : null,
        state: (lat == null && _zip == null) ? _state : null,
        zipCode: (lat == null) ? _zip : null,
        latitude: lat,
        longitude: lng,
        radiusMiles: (lat != null && lng != null) ? _radiusMiles : null,
        bedrooms: _beds,
        bathrooms: _baths,
        propertyType: _propertyType,
        status: 'Active',
        limit: _pageSize,
        offset: _offset,
      );

      // Client-side filters
      if (_minPrice != null || _maxPrice != null) {
        results = results.where((l) {
          final p = _num(l['listPrice']) ?? _num(l['price']);
          if (p == null) return false;
          if (_minPrice != null && p < _minPrice!) return false;
          if (_maxPrice != null && p > _maxPrice!) return false;
          return true;
        }).toList();
      }
      if (_minSqft != null) {
        results = results.where((l) {
          final s = _num(l['squareFeet']) ?? _num(l['sqft']);
          if (s == null) return false;
          return s >= _minSqft!;
        }).toList();
      }
      if (_hasGarage == true) {
        results = results.where((l) {
          final g = l['garage'] ?? l['garageSpaces'] ?? l['parking'];
          if (g == null) return false;
          if (g is num) return g > 0;
          if (g is String) return g.toLowerCase().contains('garage');
          return false;
        }).toList();
      }

      setState(() {
        if (reset) {
          _listings = results;
          _cache[key] = results;
        } else {
          _listings.addAll(results);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading listings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String _tileKey(double lat, double lng, double radius) {
    final rLat = (lat * 100).roundToDouble() / 100.0;
    final rLng = (lng * 100).roundToDouble() / 100.0;
    return 'LAT:$rLat|LNG:$rLng|R:$radius|O:$_offset';
  }

  // Heuristic: zoom → miles
  double _radiusFromZoom(double zoom) {
    final clamp = zoom.clamp(3, 16);
    final miles = pow(2, (13 - clamp)) * 3.0;
    return miles.toDouble().clamp(1.0, 200.0);
  }

  void _openDetails(Map<String, dynamic> listing) {
    Navigator.pushNamed(
      context,
      '/listing-details',
      arguments: {'listing': listing},
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final hasData = _listings.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          if (!_loading && hasData)
            IconButton(
              icon: Icon(_mapView ? Icons.list : Icons.map),
              onPressed: () => setState(() => _mapView = !_mapView),
              tooltip: _mapView ? 'Show List' : 'Show Map',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!hasData
              ? const Center(child: Text('No results. Try widening your search.'))
              : (_mapView ? _buildMap() : _buildList())),
    );
  }

  // ---------- List view ----------
  Widget _buildList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!_loadingMore && n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
          _loadingMore = true;
          _offset += _pageSize;
          _fetch(); // same query, next page
        }
        return false;
      },
      child: ListView.separated(
        itemCount: _listings.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == _listings.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _loadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            );
          }

          final l = _listings[i];
          final price = _num(l['listPrice']) ?? _num(l['price']) ?? 0;

          // Address
          final ap = _addressParts(l);
          final addr = ap.line?.trim().isNotEmpty == true
              ? '${ap.line}, ${ap.city ?? ''}, ${ap.state ?? ''}'
                  .replaceAll(RegExp(r',\s*,+'), ', ')
                  .replaceAll(RegExp(r',\s*$'), '')
              : (ap.city != null || ap.state != null)
                  ? '${ap.city ?? ''}, ${ap.state ?? ''}'
                      .replaceAll(RegExp(r',\s*,+'), ', ')
                      .replaceAll(RegExp(r',\s*$'), '')
                  : 'Address unavailable';

          // beds/baths
          final beds  = _num(l['bedrooms']) ?? _num(l['beds']);
          final baths = _num(l['bathrooms']) ?? _num(l['baths']);

          // Thumbnail
          final photos = _extractPhotoUrls(l);
          final thumb  = photos.isNotEmpty ? photos.first : null;

          return ListTile(
            onTap: () => _openDetails(l),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: thumb == null
                    ? Container(color: Colors.grey.shade200, child: const Icon(Icons.home_outlined))
                    : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported),
                        ),
                      ),
              ),
            ),
            title: Text('\$${_fmt(price)}'),
            subtitle: Text('$addr • ${beds ?? '-'} bd • ${baths ?? '-'} ba'),
            trailing: const Icon(Icons.chevron_right),
          );
        },
      ),
    );
  }

  // ---------- Map view ----------
  Widget _buildMap() {
    // Center on first listing with coords, otherwise fallback
    final first = _listings.firstWhere(
      (l) => (l['coordinates']?['latitude'] ?? l['lat']) != null &&
             (l['coordinates']?['longitude'] ?? l['lng']) != null,
      orElse: () => {},
    );
    final double centerLat =
        (first['coordinates']?['latitude'] ?? first['lat'] ?? 39.0).toDouble();
    final double centerLng =
        (first['coordinates']?['longitude'] ?? first['lng'] ?? -77.0).toDouble();

    final markers = _listings.map<Marker?>((l) {
      final lat = (l['coordinates']?['latitude'] ?? l['lat']) as num?;
      final lng = (l['coordinates']?['longitude'] ?? l['lng']) as num?;
      if (lat == null || lng == null) return null;
      final price = _num(l['listPrice']) ?? _num(l['price']) ?? 0;

      return Marker(
        width: 90,
        height: 36,
        point: LatLng(lat.toDouble(), lng.toDouble()),
        child: GestureDetector(
          onTap: () => _openDetails(l),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Text(
              '\$${_short(price)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLng),
            initialZoom: 11,
            onMapEvent: (evt) {
              // Debounce refetch after pan/zoom
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 450), () {
                final c = _mapController.camera.center;
                final z = _mapController.camera.zoom;
                final r = _radiusFromZoom(z);
                setState(() {
                  _radiusMiles = r;
                  _offset = 0;
                });
                _fetch(reset: true, centerLat: c.latitude, centerLng: c.longitude);
              });
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.hommie.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        // Zoom controls (+ / –)
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(
            children: [
              _ZoomBtn(
                icon: Icons.add,
                onTap: () {
                  final c = _mapController.camera.center;
                  final z = _mapController.camera.zoom + 1;
                  _mapController.move(c, z);
                },
              ),
              const SizedBox(height: 8),
              _ZoomBtn(
                icon: Icons.remove,
                onTap: () {
                  final c = _mapController.camera.center;
                  final z = _mapController.camera.zoom - 1;
                  _mapController.move(c, z);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------- helpers --------
  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _fmt(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      b.write(s[i]);
      if (idx > 1 && idx % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  String _short(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  _Addr _addressParts(Map<String, dynamic> l) {
    final a = (l['address'] is Map) ? (l['address'] as Map) : <String, dynamic>{};

    String? line =
        a['line'] ??
        a['street'] ??
        l['addressLine1'] ??
        l['streetAddress'] ??
        l['formattedAddress'];

    String? city  = a['city']  ?? l['city'];
    String? state = a['state'] ?? a['stateCode'] ?? l['state'] ?? l['stateCode'];
    String? zip   = a['postalCode'] ?? a['zipCode'] ?? l['postalCode'] ?? l['zipCode'];

    return _Addr(
      (line is String) ? line : null,
      (city is String) ? city : null,
      (state is String) ? state : null,
      (zip is String) ? zip : null,
    );
  }

  /// Accept many shapes:
  /// - photos: List<String>
  /// - photos: List<Map>{ url | link | imageUrl | src }
  /// - primaryPhotoUrl / imageUrl / thumbnail / primaryPhoto on root or address
  List<String> _extractPhotoUrls(Map<String, dynamic> l) {
    final urls = <String>[];

    void addIfString(dynamic v) {
      if (v is String && v.trim().isNotEmpty) urls.add(v.trim());
    }

    // direct single fields
    addIfString(l['primaryPhotoUrl']);
    addIfString(l['imageUrl']);
    addIfString(l['thumbnail']);
    addIfString(l['photo']);
    addIfString(l['primaryPhoto']);

    // nested common fields
    final a = l['address'];
    if (a is Map) {
      addIfString(a['imageUrl']);
      addIfString(a['thumbnail']);
    }

    // list forms
    final raw = l['photos'];
    if (raw is List) {
      for (final p in raw) {
        if (p is String) addIfString(p);
        if (p is Map) {
          addIfString(p['url']);
          addIfString(p['link']);
          addIfString(p['imageUrl']);
          addIfString(p['src']);
        }
      }
    }

    // dedupe
    return urls.toSet().toList();
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}
