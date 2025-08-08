import 'package:cloud_firestore/cloud_firestore.dart';
import 'sample_listings.dart'; // make sure this is imported

Future<void> uploadSampleListings() async {
  final listingsRef = FirebaseFirestore.instance.collection('listings');

  for (final listing in sampleListings) {
    await listingsRef.add(listing);
  }

  print('✅ Sample listings uploaded!');
}
