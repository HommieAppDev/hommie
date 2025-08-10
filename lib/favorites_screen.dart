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

  bool _compareMode = false;
  final Set<String> _selected = <String>{};

  User? get _user => _auth.currentUser;

  Future<void> _removeFavorite(String listingId) async {
    final u = _user;
    if (u == null) return;
    await _fs
        .collection('favorites')
        .doc(u.uid)
        .collection('listings')
        .doc(listingId)
        .delete();

    if (!mounted) return;
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

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        if (_selected.length < 2) _selected.add(id);
      }
    });
  }

  void _goCompare() {
    if (_selected.length != 2) return;
    final ids = _selected.toList();
    Navigator.pushNamed(context, '/compare', arguments: {
      'leftId': ids[0],
      'rightId': ids[1],
    });
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
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          Row(
            children: [
              const Text('Compare'),
              Switch(
                value: _compareMode,
                onChanged: (v) {
                  setState(() {
                    _compareMode = v;
                    _selected.clear();
                  });
                },
              ),
            ],
          ),
        ],
      ),
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

          return Stack(
            children: [
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: favDocs.length,
                itemBuilder: (context, i) {
                  final listingId = favDocs[i].id;
                  final listingRef = _fs.collection('listings').doc(listingId);

                  final isSelected = _selected.contains(listingId);

                  return Dismissible(
                    key: ValueKey(listingId),
                    direction: _compareMode
                        ? DismissDirection.none
                        : DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      color: Colors.red.shade400,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _removeFavorite(listingId),
                    child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: listingRef.snapshots(),
                      builder: (context, snap) {
                        final data = snap.data?.data();

                        // If this is an old doc from the previous provider, show a small cleanup row
                        if ((data?['source'] ?? '') != 'realtor') {
                          return ListTile(
                            leading: const Icon(Icons.history, color: Colors.orange),
                            title: const Text('Legacy favorite (from previous source)'),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete),
                              onPressed: () => _removeFavorite(listingId),
                            ),
                          );
                        }

                        final price = (data?['price'] as num?) ?? 0;
                        final addr =
                            (data?['address'] as Map?)?.cast<String, dynamic>() ??
                                const {};
                        final line = addr['line'] as String? ?? 'Address unavailable';
                        final city = addr['city'] as String? ?? '';
                        final state = addr['state'] as String? ?? '';
                        final zip = addr['postalCode'] as String? ?? '';
                        final beds = data?['beds'];
                        final baths = data?['baths'];
                        final sqft = data?['sqft'];
                        final thumb = data?['primaryPhoto'] as String?;

                        final listingForDetails = {
                          'id': listingId,
                          'listPrice': price,
                          'address': {
                            'line': line,
                            'city': city,
                            'state': state,
                            'postalCode': zip,
                          },
                          'bedrooms': beds,
                          'bathrooms': baths,
                          'squareFeet': sqft,
                          if (thumb != null) 'primaryPhoto': thumb,
                          if (thumb != null) 'photos': [thumb],
                        };

                        return GestureDetector(
                          onTap: () {
                            if (_compareMode) {
                              _toggleSelect(listingId);
                            } else {
                              _openDetails(listingForDetails);
                            }
                          },
                          onLongPress: () {
                            if (!_compareMode) {
                              setState(() => _compareMode = true);
                            }
                            _toggleSelect(listingId);
                          },
                          child: Stack(
                            children: [
                              Card(
                                elevation: 2,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: _compareMode && isSelected
                                      ? BorderSide(
                                          color: Theme.of(context).colorScheme.primary,
                                          width: 2,
                                        )
                                      : BorderSide.none,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        bottomLeft: Radius.circular(16),
                                      ),
                                      child: SizedBox(
                                        width: 120,
                                        height: 100,
                                        child: (thumb == null)
                                            ? Container(
                                                color: Colors.grey.shade200,
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.home_outlined),
                                              )
                                            : Image.network(
                                                thumb,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  color: Colors.grey.shade200,
                                                  alignment: Alignment.center,
                                                  child: const Icon(
                                                      Icons.image_not_supported),
                                                ),
                                              ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(999),
                                                border: Border.all(
                                                    color: Colors.red.shade200),
                                              ),
                                              child: Text(
                                                '\$${_fmt(price)}',
                                                style: TextStyle(
                                                  color: Colors.red.shade700,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              line,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [city, state, zip]
                                                  .where((s) => (s ?? '').isNotEmpty)
                                                  .join(', '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.black54),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 10,
                                              runSpacing: 6,
                                              children: [
                                                _MiniFact(Icons.bed_outlined,
                                                    '${beds ?? '-'} bd'),
                                                _MiniFact(Icons.bathtub_outlined,
                                                    '${baths ?? '-'} ba'),
                                                if (sqft != null)
                                                  _MiniFact(Icons.square_foot,
                                                      '${_fmt(sqft)} sqft'),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (!_compareMode)
                                      IconButton(
                                        tooltip: 'Remove',
                                        icon: const Icon(Icons.favorite,
                                            color: Colors.red),
                                        onPressed: () => _removeFavorite(listingId),
                                      ),
                                  ],
                                ),
                              ),
                              if (_compareMode)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.white,
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => _toggleSelect(listingId),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              if (_compareMode)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: ElevatedButton.icon(
                    onPressed: _selected.length == 2 ? _goCompare : null,
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(_selected.length == 2
                        ? 'Compare ${_selected.length} homes'
                        : 'Select 2 to compare'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
            ],
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

class _MiniFact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniFact(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.black54),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
