import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'listing_detail_screen.dart';

class SearchResultsScreen extends StatefulWidget {
  final String? cityOrZip;
  final double? radiusMiles;
  final String? price;
  final String? beds;
  final String? baths;
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
  Set<String> favoritedListingIds = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    setState(() {
      favoritedListingIds = Set<String>.from(data?['favorites'] ?? []);
    });
  }

  Future<void> _toggleFavorite(String listingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      if (favoritedListingIds.contains(listingId)) {
        favoritedListingIds.remove(listingId);
      } else {
        favoritedListingIds.add(listingId);
      }
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'favorites': favoritedListingIds.toList(),
    }, SetOptions(merge: true));
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('listings');

    if (widget.cityOrZip != null && widget.cityOrZip!.isNotEmpty) {
      query = query.where('locationKeywords', arrayContains: widget.cityOrZip!.toLowerCase());
    }

    if (widget.price != null) {
      final maxPrice = int.tryParse(widget.price!.replaceAll(RegExp(r'[^\d]'), ''));
      if (maxPrice != null) {
        query = query.where('price', isLessThanOrEqualTo: maxPrice);
      }
    }

    if (widget.beds != null && widget.beds != '10+') {
      final beds = int.tryParse(widget.beds!);
      if (beds != null) query = query.where('bedrooms', isGreaterThanOrEqualTo: beds);
    }

    if (widget.baths != null && widget.baths != '10+') {
      final baths = int.tryParse(widget.baths!);
      if (baths != null) query = query.where('bathrooms', isGreaterThanOrEqualTo: baths);
    }

    // Proximity search approximation
    if (widget.position != null && widget.radiusMiles != null) {
      const double milesToDegrees = 1.0 / 69.0; // Approx conversion
      final delta = widget.radiusMiles! * milesToDegrees;

      final minLat = widget.position!.latitude - delta;
      final maxLat = widget.position!.latitude + delta;
      final minLon = widget.position!.longitude - delta;
      final maxLon = widget.position!.longitude + delta;

      query = query
          .where('latitude', isGreaterThanOrEqualTo: minLat)
          .where('latitude', isLessThanOrEqualTo: maxLat)
          .where('longitude', isGreaterThanOrEqualTo: minLon)
          .where('longitude', isLessThanOrEqualTo: maxLon);
    }

    return query;
  }

  @override
  Widget build(BuildContext context) {
    final query = _buildQuery();

    return Scaffold(
      appBar: AppBar(title: const Text('Search Results')),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No listings found.'));
          }

          final listings = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              'title': data['title'] ?? 'No title',
              'location': data['location'] ?? 'Unknown',
              'image': data['image'] ?? '',
              ...data,
            };
          }).toList();

          return ListView.builder(
            itemCount: listings.length,
            itemBuilder: (context, index) {
              final listing = listings[index];
              final isFavorited = favoritedListingIds.contains(listing['id']);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ListingDetailsScreen(listing: listing),
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(listing['image'], fit: BoxFit.cover, width: double.infinity, height: 200),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(listing['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(listing['location'], style: const TextStyle(color: Colors.grey)),
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                icon: Icon(
                                  isFavorited ? Icons.favorite : Icons.favorite_border,
                                  color: isFavorited ? Colors.red : null,
                                ),
                                onPressed: () => _toggleFavorite(listing['id']),
                              ),
                            )
                          ],
                        ),
                      )
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
