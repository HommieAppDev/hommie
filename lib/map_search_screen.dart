// lib/map_search_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class Coords {
  final double? lat;
  final double? lon;
  const Coords({this.lat, this.lon});
}

class MapSearchScreen extends StatefulWidget {
  const MapSearchScreen({Key? key}) : super(key: key);

  @override
  State<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends State<MapSearchScreen> {
  final MapController _map = MapController();

  // incoming filters (city/state/zip + minPrice/maxPrice/beds/baths + advanced…)
  Map<String, dynamic> _filters = {};

  // results
  List<Map<String, dynamic>> _listings = [];

  // ui state
  bool _loading = false;
  String? _lastError;
  int _reqId = 0; // latest-request-wins guard
  Timer? _debounce;

  // map state
  LatLng _center = LatLng(39.2904, -76.6122); // default to Baltimore-ish
  double _zoom = 11;

  get AttributionWidget => null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
            {};
    _filters = Map<String, dynamic>.from(args);

    // If user already selected a point (from a previous screen), center there
    final mapLat = _toDouble(args['mapLat']);
    final mapLng = _toDouble(args['mapLng']);
    if (mapLat != null && mapLng != null) {
      _center = LatLng(mapLat, mapLng);
      _zoom = 12.5;
    }

    // Kick one initial fetch for the current view
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchThisArea());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _toStr(dynamic v) => (v ?? '').toString().trim();
  double? _toDouble(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  // robust “radius in miles” from the current visible bounds
  double _radiusMilesFromView() {
    final camera = _map.camera;
    final b = camera.visibleBounds;
    final dist = const Distance().as(
      LengthUnit.Mile,
      LatLng(b.south, b.west),
      LatLng(b.north, b.east),
    );
    return (dist / 2).clamp(1.0, 50.0);
  }

  String _priceShort(dynamic p) {
    if (p == null) return '—';
    final n = (p is num) ? p.toDouble() : double.tryParse(p.toString()) ?? 0;
    if (n >= 1000000)
      return '\$${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    if (n >= 1000)
      return '\$${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '\$${n.toStringAsFixed(0)}';
  }

  String? _primaryPhoto(Map<String, dynamic> l) {
    final t = l['thumbnail'];
    if (t is String && t.isNotEmpty) return t;
    final photos = l['photos'];
    if (photos is List && photos.isNotEmpty) {
      final first = photos.first;
      if (first is String) return _bumpPhoto(first);
      if (first is Map && first['href'] is String)
        return _bumpPhoto(first['href'] as String);
    }
    final media = l['media'];
    if (media is List) {
      for (final m in media) {
        if (m is Map && m['media_url'] is String)
          return _bumpPhoto(m['media_url'] as String);
      }
    }
    return null;
  }

  String _bumpPhoto(String url) {
    var u = url.trim();
    if (u.startsWith('//')) u = 'https:$u';
    if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');
    u = u.replaceAllMapped(
      RegExp(r'-m\d+s\.(jpg|jpeg|png)$', caseSensitive: false),
      (m) => '.${m[1]}',
    );
    u = u.replaceAllMapped(
      RegExp(r'-m\d+x\d+s\.(jpg|jpeg|png)$', caseSensitive: false),
      (m) => '.${m[1]}',
    );
    u = u.replaceAllMapped(
        RegExp(r'/(\d{2,4})x(\d{2,4})(/|$)'), (m) => '/1600x1200${m[3]}');
    final uri = Uri.tryParse(u);
    if (uri != null && uri.hasQuery) {
      final qp = Map<String, String>.from(uri.queryParameters);
      final keys = qp.map((k, v) => MapEntry(k.toLowerCase(), k));
      bool changed = false;
      void setWidth(int v) {
        if (keys.containsKey('w')) {
          qp[keys['w']!] = '$v';
          changed = true;
        }
        if (keys.containsKey('width')) {
          qp[keys['width']!] = '$v';
          changed = true;
        }
      }

      setWidth(1600);
      if (keys.containsKey('h')) {
        qp.remove(keys['h']!);
        changed = true;
      }
      if (keys.containsKey('height')) {
        qp.remove(keys['height']!);
        changed = true;
      }
      if (changed) u = uri.replace(queryParameters: qp).toString();
    }
    return u;
  }

  Coords _coords(Map<String, dynamic> l) {
    double? lat;
    double? lon;
    double? _asD(v) => v == null ? null : double.tryParse(v.toString());

    // Shape A: { "coordinate": { "lat": ..., "lon": ... } }
    final coord = (l['coordinate'] as Map?)?.cast<String, dynamic>();
    if (coord != null) {
      lat ??= _asD(coord['lat']);
      lon ??= _asD(coord['lon']);
    }

    // Shape B: { "address": { "coordinate": { "lat":..., "lon":... } } }
    final addr = (l['address'] as Map?)?.cast<String, dynamic>();
    final addrCoord = (addr?['coordinate'] as Map?)?.cast<String, dynamic>();
    if (addrCoord != null) {
      lat ??= _asD(addrCoord['lat']);
      lon ??= _asD(addrCoord['lon']);
    }

    // Shape C: { "location": { "address": { "coordinate": { "lat":..., "lon":... } } } }
    final loc = (l['location'] as Map?)?.cast<String, dynamic>();
    final locAddr = (loc?['address'] as Map?)?.cast<String, dynamic>();
    final locAddrCoord =
        (locAddr?['coordinate'] as Map?)?.cast<String, dynamic>();
    if (locAddrCoord != null) {
      lat ??= _asD(locAddrCoord['lat']);
      lon ??= _asD(locAddrCoord['lon']);
    }

    // Fallbacks: sometimes lat/lon are flat keys or use "lng"
    lat ??= _asD(l['lat']) ?? _asD(l['latitude']);
    lon ??= _asD(l['lon']) ?? _asD(l['lng']) ?? _asD(l['longitude']);

    return Coords(lat: lat, lon: lon);
  }

  // ----------- Networking -----------

  Future<void> _searchThisArea() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _lastError = null;
    });

    final key = dotenv.env['RAPIDAPI_KEY'] ?? '';
    final host = dotenv.env['RAPIDAPI_HOST'] ?? 'realtor-search.p.rapidapi.com';
    final path = dotenv.env['RE_PATH_SEARCH_GEO'] ?? '/properties/search-buy';

    if (key.isEmpty) {
      setState(() {
        _loading = false;
        _lastError = 'Missing RAPIDAPI_KEY in .env';
      });
      return;
    }

    final center = _map.camera.center;
    final radius = _radiusMilesFromView();

    // Build query from map + filters
    final qp = <String, String>{
      // geo
      'lat': center.latitude.toString(),
      'lon': center.longitude.toString(),
      'radius': radius.toStringAsFixed(1),

      // pagination-ish (optional)
      'limit': '50',
      'offset': '0',

      // filters (keep names consistent with your Results screen)
      if (_filters['minPrice'] != null)
        'price_min': _filters['minPrice'].toString(),
      if (_filters['maxPrice'] != null)
        'price_max': _filters['maxPrice'].toString(),
      if (_filters['beds'] != null) 'beds_min': _filters['beds'].toString(),
      if (_filters['baths'] != null) 'baths_min': _filters['baths'].toString(),

      // include any advanced filters you support, e.g.:
      if (_filters['property_type'] != null)
        'property_type': _toStr(_filters['property_type']),
      if (_filters['year_built_min'] != null)
        'year_built_min': _toStr(_filters['year_built_min']),
      if (_filters['hoa_max'] != null) 'hoa_max': _toStr(_filters['hoa_max']),
    };

    final myReq = ++_reqId; // tag this request
    try {
      final uri = Uri.https(host, path, qp);
      if (kDebugMode) debugPrint('🗺️  MAP GET $uri');

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(uri);
      req.headers
        ..set('X-RapidAPI-Key', key)
        ..set('X-RapidAPI-Host', host);

      final resp = await req.close();
      final body = await resp.transform(const Utf8Decoder()).join();

      if (myReq != _reqId)
        return; // a newer request finished first; ignore this one

      if (resp.statusCode == 403) {
        throw HttpException(
            'HTTP 403 — check subscription to $host and path $path.\n$body');
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('HTTP ${resp.statusCode}: $body');
      }

      final data = jsonDecode(body);
      final raw = (data['properties'] as List?) ??
          (data['data']?['home_search']?['results'] as List?) ??
          const [];

      setState(() {
        _listings = raw
            .map<Map<String, dynamic>>(
                (e) => (e as Map).cast<String, dynamic>())
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = e.toString());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Map search failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ----------- UI -----------

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    for (final l in _listings) {
      final c = _coords(l);
      if (c.lat == null || c.lon == null) continue;
      final price = l['price'] ?? l['list_price'];
      markers.add(
        Marker(
          point: LatLng(c.lat!, c.lon!),
          width: 88,
          height: 44,
          child: _PricePin(
            label: _priceShort(price),
            onTap: () => Navigator.pushNamed(
              context,
              '/listing-details',
              arguments: {'listing': l},
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search by Map Location'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: 3,
              maxZoom: 18,
              onMapReady: () {
                _searchThisArea();
              },
              onMapEvent: (evt) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  setState(() {});
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.hommie.app',
              ),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
              AttributionWidget.defaultWidget(
                source: '© OpenStreetMap contributors',
                onSourceTapped: () {
                  launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'));
                },
              ),
            ],
          ),

          // Loading overlay
          if (_loading)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Container(
                  color: Colors.black.withOpacity(0.08),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),

          // Bottom “Search this area” button
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.search),
                label: Text('Search this area (${markers.length})'),
                onPressed: _loading ? null : _searchThisArea,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),

          // Error chip (non-blocking)
          if (_lastError != null)
            Positioned(
              left: 12,
              right: 12,
              top: 12 + MediaQuery.of(context).viewPadding.top,
              child: _ErrorPill(
                message: 'Map error – tap to retry',
                onTap: _searchThisArea,
              ),
            ),
        ],
      ),
    );
  }
}

// ----------- UI widgets -----------

class _PricePin extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PricePin({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // pin tail
          Positioned(
            bottom: 0,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 12,
                height: 12,
                color: Colors.black87,
              ),
            ),
          ),
          // bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPill extends StatelessWidget {
  final String message;
  final VoidCallback onTap;
  const _ErrorPill({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
