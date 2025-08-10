// lib/search_results_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hommie/data/realtor_api_service.dart';

class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key});
  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

enum _SortMode { newest, priceLow, priceHigh, beds, sqft, dom }

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  // ---- API ----
  late final RealtorApiService _realtor = RealtorApiService();

  // UI
  bool _loading = true;
  bool _mapView = false;
  bool _loadingMore = false;
  _SortMode _sortMode = _SortMode.newest;

  // Data
  List<Map<String, dynamic>> _listings = [];
  int _offset = 0;
  static const int _pageSize = 50;

  // Query (from args)
  String? _city;
  String? _state;
  String? _zip;
  double _radiusMiles = 10;

  int? _bedsFilter;
  double? _bathsFilter;
  int? _minPrice;
  int? _maxPrice;
  int? _minSqft;
  String? _propertyType;
  bool? _hasGarage;

  // Extras
  bool? _pool, _pets, _waterfront, _views, _basement, _hasOpenHouse;
  int? _domMax, _yearBuiltMin, _hoaMax;
  double? _lotAcresMin;

  // Map stuff
  final _mapController = MapController();
  bool _mapDirty = false;
  bool _isMapReady = false;
  double? _lastZoom;
  Map<String, dynamic>? _selectedOnMap;

  // Simple cache
  final Map<String, List<Map<String, dynamic>>> _cache = {};

  Map<String, dynamic>? get _args =>
      ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

  // ---- Favorites plumbing ----
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  Set<String> _favIDs = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final a = _args ?? {};
      _city = a['city'] as String?;
      _state = a['state'] as String?;
      _zip = a['zip'] as String?;
      _radiusMiles = (a['radiusMiles'] as num?)?.toDouble() ?? 10.0;

      _bedsFilter = a['beds'] as int?;
      _bathsFilter = (a['baths'] is int)
          ? (a['baths'] as int).toDouble()
          : (a['baths'] as num?)?.toDouble();

      _minPrice = a['minPrice'] as int?;
      _maxPrice = a['maxPrice'] as int?;
      _minSqft = a['minSqft'] as int?;
      _propertyType = a['propertyType'] as String?;
      _hasGarage = (a['hasGarage'] ?? a['garage']) as bool?;

      // Extras
      _pool         = a['pool'] as bool?;
      _pets         = a['pets'] as bool?;
      _waterfront   = a['waterfront'] as bool?;
      _views        = a['views'] as bool?;
      _basement     = a['basement'] as bool?;
      _hasOpenHouse = a['hasOpenHouse'] as bool?;
      _domMax       = a['domMax'] as int?;
      _yearBuiltMin = a['yearBuiltMin'] as int?;
      _lotAcresMin  = (a['lotAcresMin'] as num?)?.toDouble();
      _hoaMax       = a['hoaMax'] as int?;

      await _loadFavs();       // hydrate hearts
      await _fetch(reset: true);
    });
  }

  // ——— Debug helper: long-press title to copy 1 raw result ———
  Future<void> _copyRawSample() async {
    try {
      final raw = await _realtor.searchByLocationRaw(
        zip: _zip, city: _city, state: _state, status: 'for_sale', limit: 1,
      );
      if (raw.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No sample found for this search.')),
        );
        return;
      }
      final pretty = const JsonEncoder.withIndent('  ').convert(raw.first);
      await Clipboard.setData(ClipboardData(text: pretty));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied one raw listing to clipboard.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t copy sample: $e')),
      );
    }
  }

  // ---------- Favorites helpers ----------
  Future<void> _loadFavs() async {
    final u = _auth.currentUser;
    if (u == null) return;
    final qs = await _fs.collection('favorites').doc(u.uid).collection('listings').get();
    setState(() => _favIDs = qs.docs.map((d) => d.id).toSet());
  }

  String _deriveListingId(Map<String, dynamic> l) {
    return l['id']?.toString()
        ?? l['property_id']?.toString()
        ?? l['listingId']?.toString()
        ?? ('${_addrLine(l) ?? ''}${_addrCity(l) ?? ''}${l['price'] ?? ''}').hashCode.toString();
  }

  Future<void> _ensureListingDoc(Map<String, dynamic> l, String id) async {
    final photos = _ListingCard._extractPhotoUrls(l);
    final primaryPhoto = photos.isNotEmpty ? photos.first : null;

    // best-effort address fields
    final a = l['address'];
    final addr = <String, dynamic>{
      'line': _addrLine(l) ?? '',
      'city': _addrCity(l) ?? '',
      'state': _addrState(l) ?? '',
      'postalCode': (a is Map ? (a['zip'] ?? a['postalCode']) : null) ??
          l['zip'] ?? l['zipCode'] ?? '',
    };

    await _fs.collection('listings').doc(id).set({
      'address': addr,
      'price': l['price'] ?? l['listPrice'],
      'beds' : _bedsValue(l),
      'baths': _bathsValue(l),
      'sqft' : l['sqft'] ?? l['squareFeet'],
      'lat'  : l['lat'] ?? l['coordinates']?['latitude'],
      'lng'  : l['lon'] ?? l['lng'] ?? l['coordinates']?['longitude'],
      if (primaryPhoto != null) 'primaryPhoto': primaryPhoto,
      'source'   : 'realtor',
      'provider' : 'rapidapi',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _toggleFavoriteFromList(Map<String, dynamic> l) async {
    final u = _auth.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save favorites.')),
      );
      return;
    }
    final id = _deriveListingId(l);
    final ref = _fs.collection('favorites').doc(u.uid).collection('listings').doc(id);
    final isFav = _favIDs.contains(id);

    // optimistic UI
    setState(() {
      if (isFav) _favIDs.remove(id); else _favIDs.add(id);
    });

    try {
      if (isFav) {
        await ref.delete();
      } else {
        await _ensureListingDoc(l, id); // mirror first
        await ref.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      // revert
      setState(() {
        if (isFav) _favIDs.add(id); else _favIDs.remove(id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t update favorite: $e')),
        );
      }
    }
  }

  // ---------------- Fetching ----------------
  Future<void> _fetch({
    bool reset = false,
    double? centerLat,
    double? centerLng,
  }) async {
    final keyVal = dotenv.env['RAPIDAPI_KEY'] ?? '';
    if (keyVal.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing RapidAPI key (.env RAPIDAPI_KEY).')),
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

    // Cache key
    final key = (centerLat != null && centerLng != null)
        ? _tileKey(centerLat, centerLng, _radiusMiles)
        : 'CS:${_city ?? ''}|ST:${_state ?? ''}|ZIP:${_zip ?? ''}|R:$_radiusMiles'
          '|B:${_bedsFilter ?? '-'}|Ba:${_bathsFilter ?? '-'}|P:${_minPrice ?? '-'}-${_maxPrice ?? '-'}'
          '|SQ:${_minSqft ?? '-'}|T:${_propertyType ?? '-'}|G:${_hasGarage ?? '-'}'
          '|X:${_pool ?? '-'}${_pets ?? '-'}${_waterfront ?? '-'}${_views ?? '-'}${_basement ?? '-'}'
          '|Y:${_domMax ?? '-'}${_yearBuiltMin ?? '-'}${_lotAcresMin ?? '-'}${_hoaMax ?? '-'}${_hasOpenHouse ?? '-'}'
          '|O:$_offset|S:$_sortMode';

    if (reset && _cache.containsKey(key)) {
      setState(() {
        _listings = List<Map<String, dynamic>>.from(_cache[key]!);
        _applyClientSorting(_listings);
        _loading = false;
      });
      return;
    }

    try {
      List<Map<String, dynamic>> mapped = [];

      if (centerLat != null && centerLng != null) {
        try {
          final data = await _realtor.searchByCoordinates(
            lat: centerLat,
            lon: centerLng,
            radiusMiles: _radiusMiles,
            limit: _pageSize,
            offset: _offset,
            status: 'for_sale',
            propertyType: _propertyType,
            beds: _bedsFilter,
            baths: _bathsFilter,
          );
          mapped = data;
        } catch (_) {/* fall back below */}
      }

      if (mapped.isEmpty) {
        final data = await _realtor.searchByLocation(
          zip: _zip,
          city: _city,
          state: _state,
          status: 'for_sale',
          limit: _pageSize,
          offset: _offset,
          propertyType: _propertyType,
          beds: _bedsFilter,
          baths: _bathsFilter,
        );
        mapped = data;
      }

      // ---------- Client-side filters ----------
      if (_minPrice != null || _maxPrice != null) {
        mapped = mapped.where((l) {
          final p = _num(l['price']);
          if (p == null) return false;
          if (_minPrice != null && p < _minPrice!) return false;
          if (_maxPrice != null && p > _maxPrice!) return false;
          return true;
        }).toList();
      }
      if (_minSqft != null) {
        mapped = mapped.where((l) {
          final s = _num(l['sqft']);
          return s == null ? false : s >= _minSqft!;
        }).toList();
      }
      if (_hasGarage == true) {
        mapped = mapped.where((l) {
          final g = l['garage'];
          if (g == null) return false;
          if (g is num) return g > 0;
          if (g is String) return g.toLowerCase().contains('garage');
          return false;
        }).toList();
      }

      // Extras (best-effort text match)
      String _t(Map<String, dynamic> l) =>
          '${(l['description'] ?? '').toString().toLowerCase()} '
          '${(l['features'] ?? '').toString().toLowerCase()}';
      if (_pool == true)        mapped = mapped.where((l) => _t(l).contains('pool')).toList();
      if (_pets == true)        mapped = mapped.where((l) => _t(l).contains('pets')).toList();
      if (_waterfront == true)  mapped = mapped.where((l) => _t(l).contains('waterfront')).toList();
      if (_views == true)       mapped = mapped.where((l) => _t(l).contains('view')).toList();
      if (_basement == true)    mapped = mapped.where((l) => _t(l).contains('basement')).toList();
      if (_domMax != null)      mapped = mapped.where((l) {
        final n = (l['dom'] ?? l['daysOnMarket']);
        final v = (n is num) ? n.toInt() : int.tryParse('$n');
        return v == null ? true : v <= _domMax!;
      }).toList();
      if (_yearBuiltMin != null) mapped = mapped.where((l) {
        final y = l['yearBuilt'] ?? l['year_built'] ?? l['year'];
        final v = (y is num) ? y.toInt() : int.tryParse('$y');
        return v == null ? true : v >= _yearBuiltMin!;
      }).toList();
      if (_lotAcresMin != null) mapped = mapped.where((l) {
        final acres = l['lotAcres'] ?? l['lot_size_acres'];
        final sqft  = l['lotSize'] ?? l['lot_sqft'];
        double? lotInAcres;
        if (acres is num) lotInAcres = acres.toDouble();
        if (lotInAcres == null && sqft is num) lotInAcres = sqft / 43560.0;
        return lotInAcres == null ? true : lotInAcres >= _lotAcresMin!;
      }).toList();
      if (_hoaMax != null) mapped = mapped.where((l) {
        final hoa = l['hoa'] ?? l['hoaFee'] ?? l['associationFee'];
        final n = (hoa is num) ? hoa.toInt() : int.tryParse('$hoa');
        return n == null ? true : n <= _hoaMax!;
      }).toList();
      if (_hasOpenHouse == true) mapped = mapped.where((l) {
        final oh = l['openHouse'] ?? l['open_houses'] ?? l['openHouseSchedule'];
        if (oh is List && oh.isNotEmpty) return true;
        return _t(l).contains('open house');
      }).toList();

      _applyClientSorting(mapped);

      setState(() {
        if (reset) {
          _listings = mapped;
          _cache[key] = mapped;
        } else {
          _listings.addAll(mapped);
        }
        _selectedOnMap = null;
        _mapDirty = false;
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

  void _applyClientSorting(List<Map<String, dynamic>> list) {
    int numOrMax(num? n) => (n == null) ? 1 << 30 : n.toInt();
    switch (_sortMode) {
      case _SortMode.newest:
        list.sort((a, b) {
          final sa = '${a['list_date'] ?? a['listDate'] ?? ''}';
          final sb = '${b['list_date'] ?? b['listDate'] ?? ''}';
          return sb.compareTo(sa);
        });
        break;
      case _SortMode.priceLow:
        list.sort((a, b) => (numOrMax(_num(a['price'])) - numOrMax(_num(b['price']))));
        break;
      case _SortMode.priceHigh:
        list.sort((a, b) => (numOrMax(_num(b['price'])) - numOrMax(_num(a['price']))));
        break;
      case _SortMode.beds:
        list.sort((a, b) => (numOrMax(_bedsValue(b)) - numOrMax(_bedsValue(a))));
        break;
      case _SortMode.sqft:
        list.sort((a, b) => (numOrMax(_num(b['sqft'])) - numOrMax(_num(a['sqft']))));
        break;
      case _SortMode.dom:
        list.sort((a, b) => (numOrMax(_num(a['dom'] ?? a['daysOnMarket'])) -
            numOrMax(_num(b['dom'] ?? b['daysOnMarket']))));
        break;
    }
  }

  String _tileKey(double lat, double lng, double radius) {
    final rLat = (lat * 100).roundToDouble() / 100.0;
    final rLng = (lng * 100).roundToDouble() / 100.0;
    return 'LAT:$rLat|LNG:$rLng|R:$radius|O:$_offset';
  }

  double _radiusFromZoom(double zoom) {
    final clamp = zoom.clamp(3, 16);
    final miles = pow(2, (13 - clamp)) * 3.0;
    return miles.toDouble().clamp(1.0, 200.0);
  }

  void _openDetails(Map<String, dynamic> listing) {
    Navigator.pushNamed(context, '/listing-details', arguments: {'listing': listing});
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final hasData = _listings.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _copyRawSample,
          child: const Text('Search Results'),
        ),
        actions: [
          if (!_loading && hasData)
            IconButton(
              icon: Icon(_mapView ? Icons.list : Icons.map),
              onPressed: () => setState(() {
                _mapView = !_mapView;
                _selectedOnMap = null;
              }),
              tooltip: _mapView ? 'Show List' : 'Show Map',
            ),
          PopupMenuButton<_SortMode>(
            tooltip: 'Sort',
            onSelected: (m) {
              setState(() => _sortMode = m);
              final cp = [..._listings];
              _applyClientSorting(cp);
              setState(() => _listings = cp);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortMode.newest,    child: Text('Newest')),
              PopupMenuItem(value: _SortMode.priceLow,  child: Text('Price: Low to High')),
              PopupMenuItem(value: _SortMode.priceHigh, child: Text('Price: High to Low')),
              PopupMenuItem(value: _SortMode.beds,      child: Text('Beds')),
              PopupMenuItem(value: _SortMode.sqft,      child: Text('Square Feet')),
              PopupMenuItem(value: _SortMode.dom,       child: Text('Days on Market')),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: _loading
          ? _buildSkeletonList()
          : (!hasData
              ? const Center(child: Text('No results. Try widening your search.'))
              : Column(
                  children: [
                    _FiltersBar(
                      city: _city,
                      state: _state,
                      zip: _zip,
                      radiusMiles: _radiusMiles,
                      beds: _bedsFilter,
                      baths: _bathsFilter,
                      minPrice: _minPrice,
                      maxPrice: _maxPrice,
                      minSqft: _minSqft,
                      typeCode: _propertyType,
                      garage: _hasGarage == true,
                      pool: _pool == true,
                      pets: _pets == true,
                      waterfront: _waterfront == true,
                      views: _views == true,
                      basement: _basement == true,
                      domMax: _domMax,
                      yearBuiltMin: _yearBuiltMin,
                      lotAcresMin: _lotAcresMin,
                      hoaMax: _hoaMax,
                      openHouse: _hasOpenHouse == true,
                    ),
                    const Divider(height: 1),
                    Expanded(child: _mapView ? _buildMap() : _buildList()),
                  ],
                )),
    );
  }

  // ---------- List view ----------
  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: () => _fetch(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (!_loadingMore &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
            setState(() => _loadingMore = true);
            _offset += _pageSize;
            _fetch(); // don't await in onNotification
          }
          return false; // allow the notification to continue bubbling
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _listings.length + 1,
          itemBuilder: (context, i) {
            if (i == _listings.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox.shrink(),
              );
            }
            final l = _listings[i];
            final id = _deriveListingId(l);
            return _ListingCard(
              data: l,
              saved: _favIDs.contains(id),
              onTap: () => _openDetails(l),
              onSaveToggle: () => _toggleFavoriteFromList(l),
              onHide: () {
                setState(() => _listings.removeAt(i));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Listing hidden'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => setState(() => _listings.insert(i, l)),
                    ),
                  ),
                );
              },
              onShare: () async {
                final addr = _composeAddress(l);
                await Clipboard.setData(ClipboardData(text: addr));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied. Paste to share.')),
                );
              },
              onOpenMaps: () => _openInMaps(_composeAddress(l)),
            );
          },
        ),
      ),
    );
  }

  // ---------- Map view ----------
  Widget _buildMap() {
    final first = _listings.firstWhere(
      (l) => (l['lat'] ?? l['coordinates']?['latitude']) != null &&
             (l['lon'] ?? l['coordinates']?['longitude']) != null,
      orElse: () => <String, dynamic>{},
    );
    final double centerLat =
        (first['lat'] ?? first['coordinates']?['latitude'] ?? 39.0).toDouble();
    final double centerLon =
        (first['lon'] ?? first['coordinates']?['longitude'] ?? -77.0).toDouble();

    final zoomForCluster = _lastZoom ?? 11;

    final markers = _buildClusterMarkers(
      _listings,
      zoom: zoomForCluster,
      onTapListing: (l) => setState(() => _selectedOnMap = l),
      onTapCluster: (lat, lon) {
        final next = ((_lastZoom ?? 11) + 1).clamp(4, 18.0).toDouble();
        _mapController.move(LatLng(lat, lon), next);
      },
    );

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLon),
            initialZoom: 11,
            onMapReady: () {
              _isMapReady = true;
              _lastZoom ??= 11;
            },
            onMapEvent: (evt) {
              _lastZoom = evt.camera.zoom;
              if (!_mapDirty) setState(() => _mapDirty = true);
              _selectedOnMap = null;
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

        if (_mapDirty)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Search this area'),
                onPressed: () {
                  if (!_isMapReady) return;
                  final c = _mapController.camera.center;
                  final z = _mapController.camera.zoom;
                  final r = _radiusFromZoom(z);
                  setState(() {
                    _radiusMiles = r;
                    _offset = 0;
                  });
                  _fetch(reset: true, centerLat: c.latitude, centerLng: c.longitude);
                },
              ),
            ),
          ),

        Positioned(
          right: 12,
          bottom: 24,
          child: Column(
            children: [
              _ZoomBtn(
                icon: Icons.add,
                onTap: () {
                  if (!_isMapReady) return;
                  final c = _mapController.camera.center;
                  final next = _mapController.camera.zoom + 1;
                  _mapController.move(c, next);
                },
              ),
              const SizedBox(height: 8),
              _ZoomBtn(
                icon: Icons.remove,
                onTap: () {
                  if (!_isMapReady) return;
                  final c = _mapController.camera.center;
                  final next = _mapController.camera.zoom - 1;
                  _mapController.move(c, next);
                },
              ),
            ],
          ),
        ),

        if (_selectedOnMap != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 110,
            child: _MiniPreviewCard(
              data: _selectedOnMap!,
              onOpen: () => _openDetails(_selectedOnMap!),
            ),
          ),

        DraggableScrollableSheet(
          minChildSize: 0.10,
          initialChildSize: 0.10,
          maxChildSize: 0.85,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26, borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _listings.length,
                      itemBuilder: (_, i) {
                        final l = _listings[i];
                        final id = _deriveListingId(l);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ListingCard(
                            data: l,
                            saved: _favIDs.contains(id),
                            onTap: () => _openDetails(l),
                            onSaveToggle: () => _toggleFavoriteFromList(l),
                            onHide: () {
                              setState(() => _listings.removeAt(i));
                            },
                            onShare: () async {
                              final addr = _composeAddress(l);
                              await Clipboard.setData(ClipboardData(text: addr));
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Address copied.')),
                              );
                            },
                            onOpenMaps: () => _openInMaps(_composeAddress(l)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------- helpers ----------
  String _composeAddress(Map<String, dynamic> l) {
    final line  = _addrLine(l);
    final city  = _addrCity(l) ?? '';
    final state = _addrState(l) ?? '';
    if (line == null || line.trim().isEmpty) {
      final fallback = (l['formattedAddress'] ?? '').toString();
      if (fallback.isNotEmpty) return fallback;
      return (city.isEmpty && state.isEmpty) ? 'Address unavailable' : '$city, $state';
    }
    return '$line, $city, $state';
  }

  Future<void> _openInMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final apple = Uri.parse('http://maps.apple.com/?q=$encoded');
    final google = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(apple)) {
      await launchUrl(apple, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(google, mode: LaunchMode.externalApplication);
    }
  }

  String? _addrLine(Map<String, dynamic> l) {
    final a = l['address'];
    if (a is Map) {
      return a['line'] ?? a['street'] ?? l['addressLine1'] ?? l['streetAddress'] ?? l['formattedAddress'];
    }
    return l['addressLine1'] ?? l['streetAddress'] ?? l['formattedAddress'];
  }

  String? _addrCity(Map<String, dynamic> l) {
    final a = l['address'];
    return (a is Map ? a['city'] : null) ?? l['city'];
  }

  String? _addrState(Map<String, dynamic> l) {
    final a = l['address'];
    return (a is Map ? (a['state'] ?? a['stateCode']) : null) ?? l['state'] ?? l['stateCode'];
  }

  num? _bedsValue(Map<String, dynamic> l) {
    return _num(l['beds']) ??
        _num(l['bedrooms']) ??
        _num(l['numBedrooms']) ??
        _num(l['bed']) ??
        _num(l['beds_min']) ??
        _num(l['beds_max']);
  }

  num? _bathsValue(Map<String, dynamic> l) {
    final tot = _num(l['baths']) ??
        _num(l['bathrooms']) ??
        _num(l['bathroomsTotal']) ??
        _num(l['bathroomsTotalInteger']) ??
        _num(l['baths_full_calc']);
    if (tot != null) return tot;

    final full = _num(l['fullBathrooms']) ?? _num(l['bathsFull']) ?? _num(l['bathrooms_full']) ?? 0;
    final half = _num(l['halfBathrooms']) ?? _num(l['bathsHalf']) ?? _num(l['bathrooms_half']) ?? 0;
    if ((full ?? 0) != 0 || (half ?? 0) != 0) return (full ?? 0) + (half ?? 0) * 0.5;
    return null;
  }

  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  // ---- clustering (no extra package) ----
  List<Marker> _buildClusterMarkers(
    List<Map<String, dynamic>> items, {
    required double zoom,
    required Function(Map<String, dynamic>) onTapListing,
    required Function(double, double) onTapCluster,
  }) {
    const cell = 60.0; // pixels
    final scale = 256 * pow(2, zoom);
    double _x(num lon) => ((lon + 180) / 360) * scale;
    double _y(num lat) {
      final r = pi / 180;
      final s = sin(lat * r);
      return (0.5 - log((1 + s) / (1 - s)) / (4 * pi)) * scale;
    }

    final buckets = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final lat = _num(it['lat']) ?? _num(it['coordinates']?['latitude']);
      final lon = _num(it['lon']) ?? _num(it['lng']) ?? _num(it['longitude']) ?? _num(it['coordinates']?['longitude']);
      if (lat == null || lon == null) continue;
      final px = _x(lon);
      final py = _y(lat);
      final key = '${(px / cell).floor()}|${(py / cell).floor()}';
      (buckets[key] ??= []).add(it);
    }

    final markers = <Marker>[];
    buckets.forEach((_, group) {
      double lat = 0, lon = 0;
      for (final it in group) {
        lat += (_num(it['lat']) ?? _num(it['coordinates']?['latitude']))!.toDouble();
        lon += (_num(it['lon']) ?? _num(it['lng']) ?? _num(it['longitude']) ?? _num(it['coordinates']?['longitude']))!.toDouble();
      }
      lat /= group.length; lon /= group.length;

      if (group.length == 1) {
        final l = group.first;
        final price = _num(l['price']) ?? 0;
        markers.add(
          Marker(
            width: 96, height: 36, point: LatLng(lat, lon),
            child: GestureDetector(
              onTap: () => onTapListing(l),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  '\$${_short(price)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        markers.add(
          Marker(
            width: 44, height: 44, point: LatLng(lat, lon),
            child: GestureDetector(
              onTap: () => onTapCluster(lat, lon),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  '${group.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    });

    return markers;
  }

  // ---------- skeletons ----------
  Widget _buildSkeletonList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(height: 18, width: 120, color: Colors.grey.shade200),
                    const SizedBox(height: 10),
                    Container(height: 14, width: double.infinity, color: Colors.grey.shade200),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: Container(height: 28, color: Colors.grey.shade200)),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 28, color: Colors.grey.shade200)),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 28, color: Colors.grey.shade200)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _short(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }
}

// ---------- Listing Card (image-first) ----------
class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.data,
    required this.saved,
    required this.onTap,
    required this.onSaveToggle,
    required this.onHide,
    required this.onShare,
    required this.onOpenMaps,
  });

  final Map<String, dynamic> data;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSaveToggle;
  final VoidCallback onHide;
  final VoidCallback onShare;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final price = _num(data['price']) ?? 0;
    final beds  = _bedsValue(data);
    final baths = _bathsValue(data);
    final sqft  = _num(data['sqft']);
    final type  = _prettyType(data['type'] ?? data['propertyType']);

    final addr = _composeAddress(data);

    final photos = _extractPhotoUrls(data);
    final heroTag = 'photo-${data['id'] ?? addr}';

    final flags = data['flags'] is Map ? (data['flags'] as Map) : const {};
    final isNew = flags['is_new_listing'] == true;
    final isContingent = flags['is_contingent'] == true;
    final hasOpenHouse = (data['open_houses'] is List && (data['open_houses'] as List).isNotEmpty);

    final priceReduced = (data['price_reduced_amount'] != null) ||
        (data['price_reduced_date'] != null);

    return Dismissible(
      key: ValueKey('listing-${data['id'] ?? addr}'),
      background: _swipeBg(context, Icons.favorite, 'Save'),
      secondaryBackground: _swipeBg(context, Icons.hide_source, 'Hide', alignEnd: true),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onSaveToggle();
          return false;
        } else {
          onHide();
          return true;
        }
      },
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => _showActionsSheet(context),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Image/Gallery ----
              Stack(
                children: [
                  SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: (photos.isEmpty)
                        ? Container(color: Colors.grey.shade200, alignment: Alignment.center,
                            child: const Icon(Icons.home_outlined, size: 36))
                        : Hero(
                            tag: heroTag,
                            child: PageView.builder(
                              itemCount: min(photos.length, 4),
                              itemBuilder: (_, i) {
                                final url = photos[i];
                                return Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.image_not_supported),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  // Price pill
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Text(
                        '\$${_fmt(price)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  // Badges
                  Positioned(
                    right: 12, top: 12,
                    child: Row(
                      children: [
                        if (isNew) _badge(context, 'New'),
                        if (priceReduced) const SizedBox(width: 6),
                        if (priceReduced) _badge(context, 'Price drop'),
                        if (hasOpenHouse) const SizedBox(width: 6),
                        if (hasOpenHouse) _badge(context, 'Open house'),
                        if (isContingent) const SizedBox(width: 6),
                        if (isContingent) _badge(context, 'Under contract'),
                      ],
                    ),
                  ),
                  // Quick save
                  Positioned(
                    right: 12, bottom: 12,
                    child: InkWell(
                      onTap: onSaveToggle,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white,
                        child: Icon(
                          saved ? Icons.favorite : Icons.favorite_border,
                          color: saved ? Colors.red : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ---- Text/details ----
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Address (clickable)
                    InkWell(
                      onTap: onOpenMaps,
                      child: Text(
                        addr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _miniChip(context, Icons.bed_outlined, '${_fmtBeds(beds)} bd'),
                        _miniChip(context, Icons.bathtub_outlined, '${_fmtBaths(baths)} ba'),
                        if (sqft != null) _miniChip(context, Icons.square_foot, '${_fmt(sqft)} sqft'),
                        if (type != null) _miniChip(context, Icons.home_work_outlined, type),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Quick actions
                    Row(
                      children: [
                        IconButton(
                          tooltip: saved ? 'Unsave' : 'Save',
                          icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                          onPressed: onSaveToggle,
                        ),
                        IconButton(
                          tooltip: 'Share',
                          icon: const Icon(Icons.ios_share),
                          onPressed: onShare,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'More',
                          icon: const Icon(Icons.more_horiz),
                          onPressed: () => _showActionsSheet(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.favorite_border), title: const Text('Save / Unsave'), onTap: () { Navigator.pop(context); onSaveToggle(); }),
            ListTile(leading: const Icon(Icons.ios_share), title: const Text('Share (copy address)'), onTap: () { Navigator.pop(context); onShare(); }),
            ListTile(leading: const Icon(Icons.map_outlined), title: const Text('Open in Maps'), onTap: () { Navigator.pop(context); onOpenMaps(); }),
            ListTile(leading: const Icon(Icons.hide_source), title: const Text('Hide'), onTap: () { Navigator.pop(context); onHide(); }),
          ],
        ),
      ),
    );
  }

  static Widget _swipeBg(BuildContext context, IconData icon, String label, {bool alignEnd = false}) {
    return Container(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!alignEnd) Icon(icon),
          if (!alignEnd) const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (alignEnd) const SizedBox(width: 8),
          if (alignEnd) Icon(icon),
        ],
      ),
    );
  }

  static Widget _badge(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
        fontSize: 11, fontWeight: FontWeight.w700,
      )),
    );
  }

  static Widget _miniChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
        color: Colors.grey.shade100,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _composeAddress(Map<String, dynamic> l) {
    final a = l['address'];
    String? line, city, state;
    if (a is Map) {
      line  = a['line'] ?? a['street'];
      city  = a['city'];
      state = a['state'] ?? a['stateCode'];
    }
    line ??= l['addressLine1'] ?? l['streetAddress'] ?? l['formattedAddress'];
    city ??= l['city'];
    state ??= l['state'] ?? l['stateCode'];
    final fallback = (l['formattedAddress'] ?? '').toString();
    if ((line ?? '').toString().trim().isEmpty) return fallback.isNotEmpty ? fallback : '${city ?? ''}, ${state ?? ''}';
    return '$line, ${city ?? ''}, ${state ?? ''}'.replaceAll(RegExp(r',\s*,+'), ', ');
  }

  static String? _prettyType(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    final words = s.replaceAll('_', ' ').split(' ');
    return words.map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1))).join(' ');
  }

  static List<String> _extractPhotoUrls(Map<String, dynamic> l) {
    final urls = <String>[];
    void add(dynamic v) {
      if (v is! String) return;
      var s = v.trim();
      if (s.isEmpty) return;
      if (s.startsWith('//')) s = 'https:$s';
      if (s.startsWith('http://')) s = s.replaceFirst('http://', 'https://');
      if (s.startsWith('https://')) urls.add(s);
    }
    add(l['primaryPhotoUrl']); add(l['primaryPhotoURL']); add(l['primaryPhoto']);
    add(l['imageUrl']); add(l['imageURL']); add(l['photo']); add(l['thumbnail']);
    add(l['thumbnailUrl']); add(l['thumbnailURL']);
    final a = l['address'];
    if (a is Map) { add(a['imageUrl']); add(a['thumbnail']); }
    for (final key in const ['photos', 'photoUrls', 'photoURLs', 'images', 'media']) {
      final arr = l[key];
      if (arr is List) {
        for (final item in arr) {
          if (item is String) add(item);
          if (item is Map) { add(item['url']); add(item['href']); add(item['link']); add(item['imageUrl']); add(item['thumbnailUrl']); add(item['mediaUrl']); }
        }
      }
    }
    return urls.toSet().toList();
  }

  static num? _bedsValue(Map<String, dynamic> l) {
    num? n(v) => (v is num) ? v : num.tryParse(v?.toString() ?? '');
    return n(l['beds']) ?? n(l['bedrooms']) ?? n(l['numBedrooms']) ?? n(l['bed']) ?? n(l['beds_min']) ?? n(l['beds_max']);
  }

  static num? _bathsValue(Map<String, dynamic> l) {
    num? n(v) => (v is num) ? v : num.tryParse(v?.toString() ?? '');
    final tot = n(l['baths']) ?? n(l['bathrooms']) ?? n(l['bathroomsTotal']) ?? n(l['bathroomsTotalInteger']) ?? n(l['baths_full_calc']);
    if (tot != null) return tot;
    final full = n(l['fullBathrooms']) ?? n(l['bathsFull']) ?? n(l['bathrooms_full']) ?? 0;
    final half = n(l['halfBathrooms']) ?? n(l['bathsHalf']) ?? n(l['bathrooms_half']) ?? 0;
    if ((full ?? 0) != 0 || (half ?? 0) != 0) return (full ?? 0) + (half ?? 0) * 0.5;
    return null;
  }

  static String _fmtBeds(num? n) {
    if (n == null) return '-';
    final isInt = n % 1 == 0;
    return isInt ? n.toInt().toString() : n.toString();
  }

  static String _fmtBaths(num? n) {
    if (n == null) return '-';
    return (n % 1 == 0) ? n.toInt().toString() : n.toString();
  }

  static String _fmt(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      b.write(s[i]);
      if (idx > 1 && idx % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  static num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }
}

// ---------- Pretty top filter summary ----------
class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.city,
    required this.state,
    required this.zip,
    required this.radiusMiles,
    required this.beds,
    required this.baths,
    required this.minPrice,
    required this.maxPrice,
    required this.minSqft,
    required this.typeCode,
    required this.garage,
    required this.pool,
    required this.pets,
    required this.waterfront,
    required this.views,
    required this.basement,
    required this.domMax,
    required this.yearBuiltMin,
    required this.lotAcresMin,
    required this.hoaMax,
    required this.openHouse,
    super.key,
  });

  final String? city, state, zip;
  final double radiusMiles;
  final int? beds, minPrice, maxPrice;
  final double? baths, lotAcresMin;
  final int? minSqft, domMax, yearBuiltMin, hoaMax;
  final String? typeCode;
  final bool garage, pool, pets, waterfront, views, basement, openHouse;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[];

    final loc = [
      if ((city ?? '').isNotEmpty) city,
      if ((state ?? '').isNotEmpty) state,
      if ((zip ?? '').isNotEmpty) zip,
    ].whereType<String>().join(', ');
    if (loc.isNotEmpty) chips.add(loc);
    chips.add('${radiusMiles.toStringAsFixed(0)} mi');

    if (beds != null) chips.add('$beds bd');
    if (baths != null) chips.add('${baths! % 1 == 0 ? baths!.toInt() : baths} ba');
    if (minPrice != null || maxPrice != null) {
      final lo = minPrice == null ? '' : '\$${_fmt(minPrice!)}';
      final hi = maxPrice == null ? '' : '\$${_fmt(maxPrice!)}';
      chips.add([lo, hi].where((s) => s.isNotEmpty).join('–'));
    }
    if (minSqft != null) chips.add('${_fmt(minSqft!)}+ sqft');
    if ((typeCode ?? '').isNotEmpty) chips.add(_titleCase(typeCode!.replaceAll('_', ' ')));
    if (garage) chips.add('garage');
    if (pool) chips.add('pool');
    if (pets) chips.add('pets ok');
    if (waterfront) chips.add('waterfront');
    if (views) chips.add('views');
    if (basement) chips.add('basement');
    if (domMax != null) chips.add('≤ ${domMax} DOM');
    if (yearBuiltMin != null) chips.add('≥ $yearBuiltMin');
    if (lotAcresMin != null) chips.add('≥ ${lotAcresMin!.toStringAsFixed(2)} ac');
    if (hoaMax != null) chips.add('HOA ≤ \$${_fmt(hoaMax!)}');
    if (openHouse) chips.add('open house');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Colors.grey.shade50,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips
              .map((c) => Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      c,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      buf.write(s[i]);
      if (idx > 1 && idx % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  static String _titleCase(String s) =>
      s.split(' ').map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1))).join(' ');
}

// ---------- small UI helpers ----------
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

class _MiniPreviewCard extends StatelessWidget {
  const _MiniPreviewCard({required this.data, required this.onOpen});
  final Map<String, dynamic> data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final photos = _ListingCard._extractPhotoUrls(data);
    final url = photos.isEmpty ? null : photos.first;
    final price = _ListingCard._fmt(_ListingCard._num(data['price'])?.toInt() ?? 0);
    final addr = _ListingCard._composeAddress(data);
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 88, height: 72,
                child: url == null
                    ? Container(color: Colors.grey.shade200, alignment: Alignment.center, child: const Icon(Icons.home_outlined))
                    : Image.network(url, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('\$$price', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
