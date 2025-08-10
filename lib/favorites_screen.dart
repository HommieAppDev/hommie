// lib/favorites_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  User? get _user => _auth.currentUser;

  Future<void> _removeFavorite(String listingId) async {
    final u = _user;
    if (u == null) return;
    await _fs.collection('favorites').doc(u.uid).collection('listings').doc(listingId).delete();
    // no setState needed; the stream updates automatically
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from favorites')),
    );
  }

  void _openDetails(Map<String, dynamic> listing) {
    Navigator.pushNamed(
      context,
      '/listing-details',
      arguments: {'listing': listing},
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    if (u == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view favorites.')),
      );
    }

    final favQuery = _fs
        .collection('favorites')
        .doc(u.uid)
        .collection('listings')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: favQuery.snapshots(),
        builder: (context, favSnap) {
          if (favSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final favDocs = favSnap.data?.docs ?? [];
          if (favDocs.isEmpty) {
            return const Center(child: Text('No favorites yet.'));
          }

          return ListView.separated(
            itemCount: favDocs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final listingId = favDocs[i].id;

              // Look up mirrored listing info
              final listingRef = _fs.collection('listings').doc(listingId);

              return Dismissible(
                key: ValueKey(listingId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.red.shade400,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _removeFavorite(listingId),
                child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: listingRef.get(),
                  builder: (context, snap) {
                    final data = snap.data?.data();

                    // Fallbacks if the mirrored doc hasn’t been created yet
                    final price = data?['price'] as num? ?? 0;
                    final addr = data?['address'] as Map<String, dynamic>? ?? {};
                    final line = addr['line'] as String? ?? 'Address unavailable';
                    final city = addr['city'] as String? ?? '';
                    final state = addr['state'] as String? ?? '';
                    final beds = data?['beds'];
                    final baths = data?['baths'];
                    final sqft = data?['sqft'];

                    // Compose a minimal listing map for details screen
                    final listingForDetails = {
                      'id': listingId,
                      'listPrice': price,
                      'address': {
                        'line': line,
                        'city': city,
                        'state': state,
                        'postalCode': addr['postalCode'],
                      },
                      'bedrooms': beds,
                      'bathrooms': baths,
                      'squareFeet': sqft,
                      // coordinates may be null here; details screen handles it
                    };

                    return ListTile(
                      onTap: () => _openDetails(listingForDetails),
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey.shade200,
                        child: const Icon(Icons.favorite, color: Colors.red),
                      ),
                      title: Text('\$${_fmt(price)}'),
                      subtitle: Text(
                        '$line${(city.isEmpty && state.isEmpty) ? '' : ', $city, $state'}'
                        ' • ${beds ?? '-'} bd • ${baths ?? '-'} ba'
                        '${sqft != null ? ' • ${_fmt(sqft)} sqft' : ''}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.favorite, color: Colors.red),
                        onPressed: () => _removeFavorite(listingId),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
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
}
