// visited_properties_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VisitedPropertiesScreen extends StatelessWidget {
  const VisitedPropertiesScreen({super.key});

  Future<List<Map<String, dynamic>>> _fetchVisitedProperties() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('visited_properties')
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visited Properties')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchVisitedProperties(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('Error loading visited properties'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No visited properties yet.'));
          }

          final properties = snapshot.data!;
          return ListView.builder(
            itemCount: properties.length,
            itemBuilder: (context, index) {
              final property = properties[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: property['imageUrl'] != null
                      ? Image.network(
                          property['imageUrl'],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.home, size: 40),
                  title: Text(property['address'] ?? 'Unknown Address'),
                  subtitle: Text('${property['beds']} beds • ${property['baths']} baths'),
                  trailing: Text('\$${property['price']}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
