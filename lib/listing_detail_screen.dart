// listing_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ListingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> listing; // normalized from SearchResultsScreen

  const ListingDetailsScreen({super.key, required this.listing});

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  late final List<String> _photos;
  late final String _mlsId;

  int _photoIndex = 0;
  bool _savingVisited = false;

  // comments
  final _commentCtrl = TextEditingController();
  bool _posting = false;

  // likes
  bool _liked = false;
  int _likesCount = 0;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    _photos = _extractPhotos(widget.listing);
    _mlsId = (widget.listing['mlsId'] ??
            widget.listing['id'] ??
            widget.listing['address']?['full'] ??
            '')
        .toString();
    _loadLikeState();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  List<String> _extractPhotos(Map<String, dynamic> l) {
    final v = l['photos'];
    if (v is List) return v.whereType<String>().toList();
    return const <String>[];
  }

  Future<void> _loadLikeState() async {
    if (_mlsId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final doc =
        await FirebaseFirestore.instance.collection('listings').doc(_mlsId).get();
    final data = doc.data() ?? {};
    final List likes = List.from(data['likes'] ?? const []);
    setState(() {
      _likesCount = likes.length;
      _liked = uid != null && likes.contains(uid);
    });
  }

  Future<void> _toggleLike() async {
    if (_mlsId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to like properties.')),
      );
      return;
    }

    setState(() => _likeBusy = true);
    try {
      final ref = FirebaseFirestore.instance.collection('listings').doc(_mlsId);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? {};
        final List likes = List.from(data['likes'] ?? const []);
        if (likes.contains(uid)) {
          likes.remove(uid);
        } else {
          likes.add(uid);
        }
        tx.set(ref, {'likes': likes}, SetOptions(merge: true));
        _likesCount = likes.length;
        _liked = likes.contains(uid);
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: $e')),
      );
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  String _priceText(dynamic value) {
    if (value == null) return '\$—';
    try {
      final n = (value is num) ? value.toInt() : int.parse(value.toString());
      final s = n.toString();
      final r = s.split('').reversed.toList();
      final out = StringBuffer();
      for (int i = 0; i < r.length; i++) {
        if (i != 0 && i % 3 == 0) out.write(',');
        out.write(r[i]);
      }
      return '\$${out.toString().split('').reversed.join()}';
    } catch (_) {
      return '\$${value.toString()}';
    }
  }

  String _address(Map<String, dynamic>? a) {
    if (a == null) return 'Unknown address';
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

  Future<void> _markVisited() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save visited homes.')),
      );
      return;
    }
    if (_mlsId.isEmpty) return;

    setState(() => _savingVisited = true);
    try {
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final data = snap.data() ?? {};
        final List visited = List.from(data['visited'] ?? const []);
        if (!visited.contains(_mlsId)) visited.add(_mlsId);

        tx.set(
          docRef,
          {
            'visited': visited,
            'visitedMeta': {
              _mlsId: {
                'lastVisitedAt': FieldValue.serverTimestamp(),
                'address': _address(widget.listing['address'] as Map<String, dynamic>?),
                'price': widget.listing['listPrice'],
                'thumb': _photos.isNotEmpty ? _photos.first : null,
              }
            }
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saved to 'Visited Properties'.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingVisited = false);
    }
  }

  Future<void> _postComment() async {
    if (_mlsId.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to comment.')),
      );
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _posting = true);
    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(_mlsId)
          .collection('comments')
          .add({
        'text': text,
        'uid': user.uid,
        'displayName': user.displayName ?? user.email ?? 'User',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _commentCtrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post comment: $e')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _openGallery(int start) {
    showDialog(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.8),
      builder: (_) {
        final controller = PageController(initialPage: start);
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: _photos.length,
                itemBuilder: (_, i) => InteractiveViewer(
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Image.network(
                      _photos[i],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                        size: 80,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 40,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;

    final address = _address(l['address'] as Map<String, dynamic>?);
    final price = _priceText(l['listPrice']);
    final property = (l['property'] as Map?) ?? {};
    final beds = property['bedrooms'] ?? l['beds'];
    final baths = property['bathsFull'] ?? l['baths'];
    final sqft = property['area'] ?? l['livingArea'];
    final lot = property['lotSize'] ?? property['lotSizeArea'];
    final year = property['yearBuilt'];
    final mls = (l['mls'] as Map?) ?? {};
    final dom = mls['daysOnMarket'] ?? l['daysOnMarket'];
    final remarks = l['remarks'] ?? l['publicRemarks'] ?? l['privateRemarks'];

    return Scaffold(
      appBar: AppBar(title: const Text('Listing Details')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _savingVisited ? null : _markVisited,
        icon: _savingVisited
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check_circle),
        label: const Text("I've Visited"),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- PHOTO CAROUSEL ---
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                PageView.builder(
                  itemCount: _photos.isEmpty ? 1 : _photos.length,
                  onPageChanged: (i) => setState(() => _photoIndex = i),
                  itemBuilder: (_, i) {
                    if (_photos.isEmpty) {
                      return Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.photo, size: 48, color: Colors.grey),
                      );
                    }
                    return GestureDetector(
                      onTap: () => _openGallery(i),
                      child: Image.network(
                        _photos[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                        ),
                      ),
                    );
                  },
                ),
                if (_photos.length > 1)
                  Positioned(
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(0, 0, 0, 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_photoIndex + 1} / ${_photos.length}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- HEADER: PRICE + ADDRESS ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              price,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              address,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
            ),
          ),

          // --- LIKE ROW ---
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Text('Likes: $_likesCount'),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _likeBusy ? null : _toggleLike,
                  icon: Icon(
                    _liked ? Icons.favorite : Icons.favorite_border,
                    color: _liked ? Colors.red : null,
                  ),
                ),
              ],
            ),
          ),

          // --- QUICK FACTS ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _fact(Icons.bed, '${beds ?? '—'} bd'),
                _fact(Icons.bathtub, '${baths ?? '—'} ba'),
                _fact(Icons.square_foot, '${sqft ?? '—'} sqft'),
                _fact(Icons.park, lot != null ? '$lot lot' : '— lot'),
                _fact(Icons.calendar_month, year != null ? '$year built' : '—'),
                _fact(Icons.timelapse, dom != null ? '$dom DOM' : '— DOM'),
                if (_mlsId.isNotEmpty) _fact(Icons.confirmation_number, 'MLS $_mlsId'),
              ],
            ),
          ),

          const Divider(height: 24),

          // --- REMARKS ---
          if (remarks != null && remarks.toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                remarks.toString(),
                style: const TextStyle(fontSize: 16, height: 1.35),
              ),
            ),

          const Divider(height: 24),

          // --- COMMENTS HEADER ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text('Comments', style: Theme.of(context).textTheme.titleMedium),
          ),

          // --- COMMENT INPUT ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _posting ? null : _postComment,
                  child: _posting
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Post'),
                ),
              ],
            ),
          ),

          // --- COMMENTS LIST ---
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot>(
              stream: (_mlsId.isEmpty)
                  ? const Stream.empty()
                  : FirebaseFirestore.instance
                      .collection('listings')
                      .doc(_mlsId)
                      .collection('comments')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No comments yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final name = (d['displayName'] ?? 'User').toString();
                    final text = (d['text'] ?? '').toString();
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(text),
                    );
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 90), // keep space for FAB
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String text) {
    return Chip(
      label: Text(text),
      avatar: Icon(icon, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
