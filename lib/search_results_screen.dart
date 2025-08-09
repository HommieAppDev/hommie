import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'listing_detail_screen.dart';

class SearchResultsScreen extends StatefulWidget {
  final String? cityOrZip;
  final double? radiusMiles;
  final String? price;   // e.g. "Up to $500k"
  final String? beds;    // e.g. "3"
  final String? baths;   // e.g. "2"
  final Position? position;

  const SearchResultsScreen({
    super.key,
    this.cityOrZip,
    this.radiusMiles,
    this.price,
    this.beds,
    this.baths,
    this.position,
  });

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  static const String _rentcastKey = 'YOUR_RENTCAST_API_KEY_HERE';
  Future<List<Map<String, dynamic>>>? _future;
  final _liked = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _fetchRentcast();
    _loadLiked();
  }

  Future<void> _loadLiked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = snap.data() ?? {};
    final List<dynamic> arr = (data['likes'] ?? const []);
    setState(() {
      _liked
        ..clear()
        ..addAll(arr.whereType<String>());
    });
  }

  Future<void> _toggleLike(String listingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      if (_liked.contains(listingId)) {
        _liked.remove(listingId);
      } else {
        _liked.add(listingId);
      }
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'likes': _liked.toList()}, SetOptions(merge: true));
  }

  // ---- Rentcast fetch ----
  Uri _buildRentcastUrl() {
    // Basic sales search endpoint (adjust if you’re using a different one)
    final base = Uri.parse('https://api.rentcast.io/v2/listings/sale');

    // Try to parse ZIP if cityOrZip is numeric
    final isZip = (widget.cityOrZip != null) &&
        RegExp(r'^\d{5}$').hasMatch(widget.cityOrZip!.trim());

    final qs = <String, String>{
      'limit': '50',
    };

    if (widget.position != null && widget.radiusMiles != null) {
      qs['latitude'] = widget.position!.latitude.toStringAsFixed(6);
      qs['longitude'] = widget.position!.longitude.toStringAsFixed(6);
      qs['radius'] = (widget.radiusMiles!.toStringAsFixed(0));
      qs['radiusUnit'] = 'mi';
    } else if (widget.cityOrZip != null && widget.cityOrZip!.trim().isNotEmpty) {
      if (isZip) {
        qs['postalCode'] = widget.cityOrZip!.trim();
      } else {
        // Let Rentcast geocode the text
        qs['address'] = widget.cityOrZip!.trim();
      }
    }

    // Beds / Baths
    if (widget.beds != null && widget.beds != '10+') {
      final b = int.tryParse(widget.beds!);
      if (b != null) qs['minBeds'] = b.toString();
    }
    if (widget.baths != null && widget.baths != '10+') {
      final b = int.tryParse(widget.baths!);
      if (b != null) qs['minBaths'] = b.toString();
    }

    // Price ceiling (e.g., “Up to $500k”)
    if (widget.price != null) {
      final max = int.tryParse(widget.price!.replaceAll(RegExp(r'[^\d]'), ''));
      if (max != null) qs['maxPrice'] = max.toString();
    }

    return base.replace(queryParameters: qs);
  }

  Future<List<Map<String, dynamic>>> _fetchRentcast() async {
    final url = _buildRentcastUrl();
    final res = await http.get(url, headers: {'X-Api-Key': _rentcastKey});
    if (res.statusCode != 200) {
      throw Exception('Rentcast ${res.statusCode}: ${res.body}');
    }
    final decoded = json.decode(res.body);
    if (decoded is! List) return const [];

    // Normalize
    return decoded.map<Map<String, dynamic>>((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final photos = (map['photos'] is List)
          ? List<String>.from(map['photos'])
          : <String>[];

      // Build a stable id (prefer mlsId, else id, else address hash)
      final id = (map['mlsId'] ??
              map['id'] ??
              (map['address']?['line']?.toString() ?? '') +
                  (map['address']?['postalCode']?.toString() ?? ''))
          .toString();

      return {
        'id': id,
        'mlsId': map['mlsId']?.toString() ?? id,
        'listPrice': map['listPrice'],
        'address': Map<String, dynamic>.from(map['address'] ?? const {}),
        'property': Map<String, dynamic>.from(map['property'] ?? const {}),
        'photos': photos,
        'raw': map, // keep full payload for detail screen
      };
    }).toList();
  }

  String _fmtPrice(dynamic v) {
    if (v == null) return '\$—';
    try {
      final n = (v is num) ? v.toInt() : int.parse(v.toString());
      final s = n.toString();
      final r = s.split('').reversed.toList();
      final out = StringBuffer();
      for (int i = 0; i < r.length; i++) {
        if (i != 0 && i % 3 == 0) out.write(',');
        out.write(r[i]);
      }
      return '\$${out.toString().split('').reversed.join()}';
    } catch (_) {
      return '\$${v.toString()}';
    }
  }

  String _fmtAddress(Map<String, dynamic> a) {
    final full = (a['full'] ?? a['line'])?.toString();
    if (full != null && full.trim().isNotEmpty) return full;
    final parts = [
      a['streetNumber'],
      a['streetName'],
      a['city'],
      a['state'],
      a['postalCode'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
    return parts.isEmpty ? 'Unknown address' : parts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Results')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final listings = snap.data ?? const [];

          if (listings.isEmpty) {
            return const Center(child: Text('No listings found.'));
          }

          return ListView.builder(
            itemCount: listings.length,
            itemBuilder: (_, i) {
              final l = listings[i];
              final id = l['id'] as String;
              final photos = (l['photos'] as List<String>? ?? const []);
              final address = _fmtAddress(l['address'] as Map<String, dynamic>);
              final price = _fmtPrice(l['listPrice']);
              final isLiked = _liked.contains(id);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ListingDetailsScreen(
                        listing: l, // pass normalized map
                      ),
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  clipBehavior: Clip.antiAlias,
                  elevation: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: photos.isEmpty
                            ? Container(
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Icon(Icons.photo, size: 48, color: Colors.grey),
                              )
                            : Image.network(
                                photos.first,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                ),
                              ),
                      ),

                      // Text + like
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(address, style: const TextStyle(color: Colors.black87)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                                  color: isLiked ? Colors.red : null),
                              onPressed: () => _toggleLike(id),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
