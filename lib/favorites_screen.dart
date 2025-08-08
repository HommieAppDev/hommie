// favorites_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> favoriteListings = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final List favorites = doc.data()?['favorites'] ?? [];

    // Example static listings list (simulate from mock data)
    final listings = [
      {
        'id': '1',
        'title': 'Cozy Apartment in Brooklyn',
        'image': 'assets/images/house1.jpg',
        'price': '\$2,500/mo'
      },
      {
        'id': '2',
        'title': 'Sunny Loft in Manhattan',
        'image': 'assets/images/house2.jpg',
        'price': '\$3,200/mo'
      },
      {
        'id': '3',
        'title': 'Modern Condo with Balcony',
        'image': 'assets/images/house3.jpg',
        'price': '\$2,900/mo'
      },
    ];

    setState(() {
      favoriteListings = listings.where((listing) => favorites.contains(listing['id'])).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: favoriteListings.isEmpty
          ? const Center(child: Text('No favorites yet.'))
          : ListView.builder(
              itemCount: favoriteListings.length,
              itemBuilder: (context, index) {
                final listing = favoriteListings[index];
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(
                    leading: Image.asset(
                      listing['image'],
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                    title: Text(listing['title']),
                    subtitle: Text(listing['price']),
                  ),
                );
              },
            ),
    );
  }
}
