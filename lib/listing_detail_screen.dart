import 'package:flutter/material.dart';
import 'package:hommie/media_upload_form.dart';

class ListingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> listing;

  const ListingDetailsScreen({
    required this.listing,
    super.key,
  });

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  int likeCount = 0;
  List<String> comments = [];
  List<Map<String, dynamic>> visitorFeedback = [];

  final TextEditingController commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final String title = widget.listing['title'] ?? 'No title';
    final String imageUrl = widget.listing['image'] ?? '';
    final String description = widget.listing['description'] ?? 'No description';
    final String listingId = widget.listing['id'] ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(imageUrl),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 16),
            ),

            // Like button
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.favorite_border),
                  onPressed: () {
                    setState(() {
                      likeCount++;
                    });
                  },
                ),
                Text('$likeCount likes'),
              ],
            ),

            const SizedBox(height: 24),

            // Upload Media
            ElevatedButton.icon(
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Upload Visit Media'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaUploadForm(listingId: listingId),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),
            const Divider(),
            const Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

            // Comment input
            TextField(
              controller: commentController,
              decoration: InputDecoration(
                hintText: 'Leave a comment...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    if (commentController.text.trim().isNotEmpty) {
                      setState(() {
                        comments.add(commentController.text.trim());
                        commentController.clear();
                      });
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Comment list
            ...comments.map((comment) => ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(comment),
                )),

            const SizedBox(height: 32),
            const Divider(),
            const Text('Visitor Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text(
              'Exterior photos only. Photos and feedback are uploaded by visitors and are not verified.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // Visitor feedback list
            ...visitorFeedback.map(
              (item) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.network(item['image']),
                  const SizedBox(height: 4),
                  Text(item['text']),
                  const Divider(),
                ],
              ),
            ),

            // Placeholder feedback (can be replaced with Firestore data later)
            ElevatedButton(
              onPressed: () {
                setState(() {
                  visitorFeedback.add({
                    'image': imageUrl,
                    'text': 'Nice quiet neighborhood with lots of trees.',
                  });
                });
              },
              child: const Text('Add Sample Feedback'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }
}
