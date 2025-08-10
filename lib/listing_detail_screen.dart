// lib/listing_detail_screen.dart
import 'dart:io';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants/asset_paths.dart'; // avatarOptions, defaultAvatar

// ----------------- Helpers for avatars, profiles, DMs -----------------

Widget _userAvatar(String? keyOrUrl, {double radius = 18}) {
  if (keyOrUrl == null || keyOrUrl.isEmpty) {
    return CircleAvatar(radius: radius, backgroundImage: AssetImage(defaultAvatar));
  }
  if (avatarOptions.containsKey(keyOrUrl)) {
    return CircleAvatar(radius: radius, backgroundImage: AssetImage(avatarOptions[keyOrUrl]!));
  }
  if (keyOrUrl.startsWith('http')) {
    return CircleAvatar(radius: radius, backgroundImage: NetworkImage(keyOrUrl));
  }
  return CircleAvatar(radius: radius, backgroundImage: AssetImage(defaultAvatar));
}

// push to a public user profile
void _openUserProfile(BuildContext context, String uid) {
  Navigator.pushNamed(context, '/user-profile', arguments: {'uid': uid});
}

// open/create a DM thread and navigate to chat
Future<void> _openDM(BuildContext context, String otherUid) async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null || me == otherUid) return;

  final ids = [me, otherUid]..sort();
  final threadId = ids.join('_');

  final ref = FirebaseFirestore.instance.collection('threads').doc(threadId);
  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      'participants': ids,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
    });
  } else {
    await ref.update({'updatedAt': FieldValue.serverTimestamp()});
  }

  if (context.mounted) {
    Navigator.pushNamed(context, '/chat', arguments: {'threadId': threadId, 'otherUid': otherUid});
  }
}

// ----------------- Screen -----------------

class ListingDetailsScreen extends StatefulWidget {
  const ListingDetailsScreen({super.key, required this.listing});
  final Map<String, dynamic> listing;

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  late final String listingId;

  bool _fav = false;
  bool _visited = false;
  bool _agreeToPolicy = false;

  final _publicCommentCtrl = TextEditingController();
  final _visitorFeedbackCtrl = TextEditingController();

  User? get _user => _auth.currentUser;

  // Primary photo derived from the listing payload
  String? get primaryPhoto {
    final pics = _extractPhotoUrls(widget.listing);
    return pics.isNotEmpty ? pics.first : null;
  }

  @override
  void initState() {
    super.initState();
    listingId = _deriveListingId(widget.listing);
    _bootstrapFlags();
    _ensureListingDoc();
  }

  @override
  void dispose() {
    _publicCommentCtrl.dispose();
    _visitorFeedbackCtrl.dispose();
    super.dispose();
  }

  String _deriveListingId(Map<String, dynamic> l) {
    return l['id']?.toString() ??
        l['listingId']?.toString() ??
        ((l['address']?['line'] ?? '') +
                (l['address']?['city'] ?? '') +
                (l['listPrice']?.toString() ?? ''))
            .hashCode
            .toString();
  }

  Future<void> _bootstrapFlags() async {
    final u = _user;
    if (u == null) return;
    final favRef = _fs.collection('favorites').doc(u.uid).collection('listings').doc(listingId);
    final visRef = _fs.collection('visited').doc(u.uid).collection('listings').doc(listingId);
    final fav = await favRef.get();
    final vis = await visRef.get();
    if (!mounted) return;
    setState(() {
      _fav = fav.exists;
      _visited = vis.exists;
    });
  }

  Future<void> _ensureListingDoc() async {
    final l = widget.listing;
    await _fs.collection('listings').doc(listingId).set({
      'address': {
        'line': l['address']?['line'] ?? l['address']?['street'],
        'city': l['address']?['city'],
        'state': l['address']?['state'] ?? l['address']?['stateCode'],
        'postalCode': l['address']?['postalCode'] ?? l['address']?['zipCode'],
      },
      'price': l['listPrice'] ?? l['price'],
      'beds': l['bedrooms'] ?? l['beds'],
      'baths': l['bathrooms'] ?? l['baths'],
      'sqft': l['squareFeet'] ?? l['sqft'],
      'lat': l['coordinates']?['latitude'] ?? l['lat'],
      'lng': l['coordinates']?['longitude'] ?? l['lng'],
      'primaryPhoto': primaryPhoto, // stored for favorites/visited list thumbs
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _toggleFavorite() async {
    final u = _user;
    if (u == null) return;
    final ref = _fs.collection('favorites').doc(u.uid).collection('listings').doc(listingId);
    if (_fav) {
      await ref.delete();
      if (mounted) setState(() => _fav = false);
    } else {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
      if (mounted) setState(() => _fav = true);
    }
  }

  Future<void> _toggleVisited() async {
    final u = _user;
    if (u == null) return;
    final ref = _fs.collection('visited').doc(u.uid).collection('listings').doc(listingId);
    if (_visited) {
      await ref.delete();
      if (!mounted) return;
      setState(() => _visited = false);
    } else {
      await ref.set({'visitedAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      setState(() => _visited = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Marked as visited")));
    }
  }

  Future<void> _addPublicComment() async {
    final u = _user;
    final txt = _publicCommentCtrl.text.trim();
    if (u == null || txt.isEmpty) return;
    await _fs.collection('listings').doc(listingId).collection('comments').add({
      'uid': u.uid,
      'displayName': u.displayName ?? 'User',
      'text': txt,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _publicCommentCtrl.clear();
  }

  Future<void> _addVisitorFeedback() async {
    if (!_visited) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only visitors can leave Visitor Feedback.')),
      );
      return;
    }
    final u = _user;
    final txt = _visitorFeedbackCtrl.text.trim();
    if (u == null || txt.isEmpty) return;
    await _fs.collection('listings').doc(listingId).collection('visitor_feedback').add({
      'uid': u.uid,
      'displayName': u.displayName ?? 'Visitor',
      'text': txt,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _visitorFeedbackCtrl.clear();
  }

  Future<void> _uploadVisitorPhoto() async {
    if (!_visited) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mark as visited to upload visitor photos.')),
      );
      return;
    }

    if (!_agreeToPolicy) {
      final ok = await _showPhotoPolicyDialog();
      if (ok != true) return;
      setState(() => _agreeToPolicy = true);
    }

    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 88);
    if (x == null) return;

    final u = _user;
    if (u == null) return;
    final file = File(x.path);
    final path =
        'listing_photos/$listingId/${u.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final task =
        await _storage.ref(path).putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final storagePath = task.ref.fullPath;

    await _fs.collection('listings').doc(listingId).collection('photos').add({
      'uid': u.uid,
      'storagePath': storagePath,
      'status': 'pending', // moderator approval required
      'type': 'visitor',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo uploaded for review.')),
    );
  }

  Future<bool?> _showPhotoPolicyDialog() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Visitor Photo Policy'),
        content: const Text(
          'Upload only photos you took during your visit.\n\n'
          '• Do NOT upload interior photos (privacy)\n'
          '• No faces, license plates, or private information\n'
          '• No copyrighted MLS photos\n\n'
          'All uploads are moderated before appearing publicly.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('I Agree')),
        ],
      ),
    );
  }

  Future<void> _openInMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;

    final photos = _extractPhotoUrls(l);
    final price = l['listPrice'] ?? l['price'] ?? 0;
    final line = l['address']?['line'] ?? l['address']?['street'];
    final city = l['address']?['city'];
    final state = l['address']?['state'] ?? l['address']?['stateCode'];
    final zip = l['address']?['postalCode'] ?? l['address']?['zipCode'];
    final address = (line != null && line.toString().trim().isNotEmpty)
        ? '$line, ${city ?? ''}, ${state ?? ''} ${zip ?? ''}'
            .replaceAll(RegExp(r',\s*,+'), ', ')
        : '${city ?? ''}, ${state ?? ''}'.trim().replaceAll(RegExp(r',\s*$'), '');
    final beds = l['bedrooms'] ?? l['beds'];
    final baths = l['bathrooms'] ?? l['baths'];
    final sqft = l['squareFeet'] ?? l['sqft'];
    final type = l['propertyType'] ?? l['type'];

    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: ListView(
        children: [
          // --- Photos header ---
          if (photos.isNotEmpty)
            CarouselSlider(
              options: CarouselOptions(height: 260, viewportFraction: 1, enableInfiniteScroll: false),
              items: photos.map((u) {
                return Builder(
                  builder: (_) => Stack(
                    children: [
                      Positioned.fill(
                        child: Image.network(
                          u,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: true,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0x33000000)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else
            Container(
              height: 200,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Text('No photos available'),
            ),

          // --- Price + quick facts ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\$${_fmt(price)}',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: address.isNotEmpty ? () => _openInMaps(address) : null,
                  child: Text(
                    address.isEmpty ? 'Address unavailable' : address,
                    style: TextStyle(
                      fontSize: 16,
                      color: address.isEmpty ? Colors.black87 : Colors.blue,
                      decoration: address.isEmpty ? TextDecoration.none : TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip('${beds ?? '-'} bd'),
                    _Chip('${baths ?? '-'} ba'),
                    if (sqft != null) _Chip('${_fmt(sqft)} sqft'),
                    if (type != null) _Chip(type.toString()),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Save',
                      icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                          color: _fav ? Colors.red : null),
                      onPressed: _toggleFavorite,
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      onPressed: _toggleVisited,
                      icon: Icon(_visited ? Icons.check_circle : Icons.check_circle_outline),
                      label: Text(_visited ? 'Visited' : "I've Visited"),
                      style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _uploadVisitorPhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Add Photo'),
                      style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // --- Visitor Feedback (readable by all; only visitors can post) ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: const [
                Icon(Icons.verified_user_outlined, size: 20),
                SizedBox(width: 8),
                Text('Visitor Feedback',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fs
                .collection('listings')
                .doc(listingId)
                .collection('visitor_feedback')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Only visitors can leave feedback about what they saw.\n'
                    'Be respectful. No interior photos.',
                    style: TextStyle(color: Colors.black54),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final uid = d['uid'] as String?;
                  if (uid == null) {
                    return const ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('Visitor'),
                      subtitle: Text(''),
                    );
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _fs.collection('users').doc(uid).snapshots(),
                    builder: (_, userSnap) {
                      final user = userSnap.data?.data();
                      final display = user?['displayName'] ?? d['displayName'] ?? 'Visitor';
                      final avatarKeyOrUrl =
                          user?['avatarKey'] ?? user?['avatarUrl'] ?? user?['photoURL'];
                      return ListTile(
                        leading: GestureDetector(
                          onTap: () => _openUserProfile(context, uid),
                          child: _userAvatar(avatarKeyOrUrl),
                        ),
                        title: GestureDetector(
                          onTap: () => _openUserProfile(context, uid),
                          child: Text(display, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        subtitle: Text(d['text'] ?? ''),
                        trailing: IconButton(
                          tooltip: 'Message',
                          icon: const Icon(Icons.mail_outline),
                          onPressed: () => _openDM(context, uid),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          if (_visited)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _visitorFeedbackCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Share what you saw (no interior photos)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _addVisitorFeedback, child: const Text('Post')),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Mark as “Visited” to post feedback and upload photos.',
                style: TextStyle(color: Colors.orange.shade700),
              ),
            ),

          // --- Approved visitor photos gallery ---
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fs
                .collection('listings')
                .doc(listingId)
                .collection('photos')
                .where('status', isEqualTo: 'approved')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 120,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final storagePath = docs[i].data()['storagePath'] as String?;
                    return AspectRatio(
                      aspectRatio: 4 / 3,
                      child: FutureBuilder<String>(
                        future: storagePath == null
                            ? Future.value('')
                            : _storage.ref(storagePath).getDownloadURL(),
                        builder: (_, urlSnap) {
                          final url = urlSnap.data;
                          if (url == null || url.isEmpty) {
                            return Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Text('Loading...'),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const Divider(height: 1),

          // --- Public Comments ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: const [
                Icon(Icons.forum_outlined, size: 20),
                SizedBox(width: 8),
                Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fs
                .collection('listings')
                .doc(listingId)
                .collection('comments')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Be the first to comment.'),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = docs[i].data();
                  final uid = c['uid'] as String?;
                  if (uid == null) {
                    return const ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('User'),
                      subtitle: Text(''),
                    );
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _fs.collection('users').doc(uid).snapshots(),
                    builder: (_, userSnap) {
                      final user = userSnap.data?.data();
                      final display = user?['displayName'] ?? c['displayName'] ?? 'User';
                      final avatarKeyOrUrl =
                          user?['avatarKey'] ?? user?['avatarUrl'] ?? user?['photoURL'];
                      return ListTile(
                        leading: GestureDetector(
                          onTap: () => _openUserProfile(context, uid),
                          child: _userAvatar(avatarKeyOrUrl),
                        ),
                        title: GestureDetector(
                          onTap: () => _openUserProfile(context, uid),
                          child: Text(display, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        subtitle: Text(c['text'] ?? ''),
                        trailing: IconButton(
                          tooltip: 'Message',
                          icon: const Icon(Icons.mail_outline),
                          onPressed: () => _openDM(context, uid),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _publicCommentCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addPublicComment, child: const Text('Post')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------- helpers inside State ---------

  List<String> _extractPhotoUrls(Map<String, dynamic> l) {
    final raw = l['photos'];
    if (raw is List) {
      if (raw.isEmpty) return const [];
      if (raw.first is String) {
        return raw.cast<String>();
      } else if (raw.first is Map) {
        return raw
            .map((e) => (e as Map)['url'])
            .where((u) => u is String && u.toString().isNotEmpty)
            .cast<String>()
            .toList();
      }
    }
    return const [];
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

class _Chip extends StatelessWidget {
  const _Chip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: Colors.grey.shade100,
      shape: const StadiumBorder(side: BorderSide(color: Colors.black12)),
    );
  }
}
