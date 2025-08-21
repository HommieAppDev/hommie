// lib/favorites_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  bool _compareMode = false;
  List<String> _selected = [];

  void _toggleSelect(String listingId) {
    setState(() {
      if (_selected.contains(listingId)) {
        _selected.remove(listingId);
      } else {
        if (_selected.length < 2) {
          _selected.add(listingId);
        }
      }
    });
  }

  void _removeFavorite(String listingId) {
    // TODO: Implement actual removal logic
    setState(() {
      _selected.remove(listingId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Favorite removed')),
    );
  }

  void _openDetails(Map<String, dynamic> listing) {
    // TODO: Implement navigation to details
  }

  void _goCompare() {
    // TODO: Implement compare logic
  }

  @override
  Widget build(BuildContext context) {
    // Example data for demonstration
    final favorites = [
      {
        'id': '1',
        'price': 500000,
        'address': {
          'line': '123 Main St',
          'city': 'Springfield',
          'state': 'IL',
          'postalCode': '62704',
        },
        'beds': 3,
        'baths': 2,
        'sqft': 1800,
        'primaryPhoto': null,
        'source': 'legacy',
      },
      // ...add more sample listings as needed...
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: Stack(
        children: [
          ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final data = favorites[index];
              final listingId = data['id'] as String;
              final source = data['source'] as String? ?? '';
              final isSelected = _selected.contains(listingId);
              final legacySources = ['legacy'];

              if (legacySources.contains(source)) {
                return ListTile(
                  leading: const Icon(Icons.history, color: Colors.orange),
                  title: const Text('Legacy favorite (from previous provider)'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeFavorite(listingId),
                  ),
                );
              }
              if (data == null) {
                return ListTile(
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: const Text('Listing data unavailable'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeFavorite(listingId),
                  ),
                );
              }
              final price = (data['price'] as num?) ?? 0;
              final addr = (data['address'] as Map?)?.cast<String, dynamic>() ?? const {};
              final line = addr['line'] as String? ?? 'Address unavailable';
              final city = addr['city'] as String? ?? '';
              final state = addr['state'] as String? ?? '';
              final zip = addr['postalCode'] as String? ?? '';
              final beds = data['beds'];
              final baths = data['baths'];
              final sqft = data['sqft'];
              final thumb = data['primaryPhoto'] as String?;

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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Compare mode enabled. Select two homes to compare.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
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
                                        child: const Icon(Icons.image_not_supported),
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
                                      _fmt(price).toString(),
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
                                    [city, state, zip].where((s) => s.isNotEmpty).join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.black54),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    children: [
                                      _MiniFact(Icons.bed_outlined, beds != null ? beds.toString() + ' bd' : '- bd'),
                                      _MiniFact(Icons.bathtub_outlined, baths != null ? baths.toString() + ' ba' : '- ba'),
                                      if (sqft != null && sqft is num)
                                        _MiniFact(Icons.square_foot, _fmt(sqft as num).toString() + ' sqft'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!_compareMode)
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.favorite, color: Colors.red),
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
          if (_compareMode)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: _selected.length == 2 ? _goCompare : null,
                icon: const Icon(Icons.compare_arrows),
                label: Text(_selected.length == 2
                    ? 'Compare ' + _selected.length.toString() + ' homes'
                    : 'Select 2 to compare'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(num n) {
    return NumberFormat.decimalPattern().format(n.round());
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
