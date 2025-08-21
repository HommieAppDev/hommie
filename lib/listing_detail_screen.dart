// lib/listing_detail_screen.dart
import 'dart:io';
import 'dart:math';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:hommie/data/realtor_api_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants/asset_paths.dart'; // avatarOptions, defaultAvatar
import 'package:hommie/data/realtor_api_service.dart';

// Normalize Realtor/rdcpix image URLs to higher-res variants.
String _hiResUrl(String url) {
  var u = url.trim();
  if (u.isEmpty) return u;

  // Ensure https
  if (u.startsWith('//')) u = 'https:$u';
  if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');

  // Common RDC small-image patterns:
  // ...-m123456s.jpg  OR  ...-m123x456s.jpg  ->  ....jpg
  u = u.replaceAllMapped(
    RegExp(r'-m\d+s\.(jpg|jpeg|png)$', caseSensitive: false),
    (m) => '.${m[1]}',
  );
  u = u.replaceAllMapped(
    RegExp(r'-m\d+x\d+s\.(jpg|jpeg|png)$', caseSensitive: false),
    (m) => '.${m[1]}',
  );

  // Path segments like /300x200/ -> bump up to /1600x1200/
  u = u.replaceAllMapped(
    RegExp(r'/(\d{2,4})x(\d{2,4})(/|$)'),
    (m) => '/1600x1200${m[3]}',
  );

  // Query-based sizes -> bump width, drop explicit height to keep aspect ratio
  final uri = Uri.tryParse(u);
  if (uri != null && uri.hasQuery) {
    final qp = Map<String, String>.from(uri.queryParameters);
    final keys = qp.map((k, v) => MapEntry(k.toLowerCase(), k));
    bool changed = false;

    void setWidth(int v) {
      if (keys.containsKey('w')) { qp[keys['w']!] = '$v'; changed = true; }
      if (keys.containsKey('width')) { qp[keys['width']!] = '$v'; changed = true; }
    }

    // Prefer ~1600px wide for detail/carousel
    setWidth(1600);

    // Remove tiny height caps if present
    if (keys.containsKey('h')) { qp.remove(keys['h']!); changed = true; }
    if (keys.containsKey('height')) { qp.remove(keys['height']!); changed = true; }

    if (changed) {
      u = uri.replace(queryParameters: qp).toString();
    }
  }

  return u;
}

// Helper skeleton line widget
Widget _lineSkeleton({double width = 100, double height = 20}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.grey.shade300,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

// Helper chip widget
Widget _Chip(String label) {
  return Chip(
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
    backgroundColor: Colors.grey.shade100,
    shape: const StadiumBorder(),
  );
}

// Helper for int or decimal display
String _intOrDec(dynamic n) {
  if (n == null) return '';
  if (n is int || (n is double && n == n.roundToDouble())) return n.toString();
  if (n is double) return n.toStringAsFixed(1);
  return n.toString();
}

// FactsGrid widget
class _FactsGrid extends StatelessWidget {
  final List<Widget> items;
  const _FactsGrid({required this.items, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.5,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items,
    );
  }
}

// Simple dots indicator for carousel
class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          return Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == index ? Colors.blueAccent : Colors.grey.shade400,
            ),
          );
        }),
      ),
    );
  }
}
// Helper for numeric parsing
num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

// Bath derivation
num? _deriveBaths(Map<String, dynamic> l) {
  return _num(l['baths']) ?? _num(l['bathrooms']);
}

// Year built
int? _coerceYearBuilt(Map<String, dynamic> l) {
  return _num(l['yearBuilt'])?.toInt();
}

// DOM
int? _coerceDOM(Map<String, dynamic> l) {
  return _num(l['dom'])?.toInt();
}

// Description
String? _stringifyDescription(Map<String, dynamic> l) {
  return l['description']?.toString();
}

/// ---------------- Avatars / profiles / DMs ----------------

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

void _openUserProfile(BuildContext context, String uid) {
  Navigator.pushNamed(context, '/user-profile', arguments: {'uid': uid});
}

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

/// --------------- Address helpers ----------------

Map<String, String> _coerceAddressMap(dynamic a, Map<String, dynamic> fallback) {
  Map m = {};
  if (a is Map) m = a;
  else if (fallback['address'] is Map) m = fallback['address'];
  else if (fallback['location'] is Map && (fallback['location']['address'] is Map)) {
    m = fallback['location']['address'];
  }

  String? line  = m['line'] ?? m['address_line'] ?? m['street'] ?? fallback['streetAddress'];
  String? city  = m['city'] ?? fallback['city'];
  String? state = m['state'] ?? m['state_code'] ?? fallback['state'] ?? fallback['stateCode'];
  String? zip   = m['zip'] ?? m['postal_code'] ?? fallback['zip'] ?? fallback['zipCode'];

  if (a is String && a.trim().isNotEmpty) {
    line ??= a.trim();
    final parts = a.split(',').map((s) => s.trim()).toList();
    if (parts.length >= 2) {
      city ??= parts[0];
      if (parts[1].length == 2) state ??= parts[1];
    }
  }

  return {
    'line': (line ?? '').toString(),
    'city': (city ?? '').toString(),
    'state': (state ?? '').toString(),
    'postalCode': (zip ?? '').toString(),
  };
}

String _bestAddressString(Map<String, dynamic> l) {
  // 1) explicit formatted address if provided
  final fa = l['formattedAddress'];
  if (fa is String && fa.trim().isNotEmpty) return fa.trim();

  // 2) address object(s)
  dynamic a = l['address'];
  if (a == null && l['address_new'] is Map) a = l['address_new'];
  if (a == null && l['location'] is Map) a = (l['location']['address'] ?? l['location']['line']);

  if (a is Map) {
    final line  = (a['line'] ?? a['address_line'] ?? a['street'] ?? '').toString().trim();
    final city  = (a['city'] ?? '').toString().trim();
    final state = (a['state'] ?? a['state_code'] ?? a['stateCode'] ?? '').toString().trim();
  final zip   = (a['zip'] ?? a['postalCode'] ?? '').toString().trim();
    final parts = <String>[
      if (line.isNotEmpty) line,
      [city, state].where((s) => s.isNotEmpty).join(', '),
      if (zip.isNotEmpty) zip,
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
  }

  // 3) string forms
  if (a is String && a.trim().isNotEmpty) return a.trim();
  if (l['location'] is Map && l['location']['address'] is String) {
    final s = (l['location']['address'] as String).trim();
    if (s.isNotEmpty) return s;
  }

  // 4) weak fallback from city/state
  final city = (l['city'] ?? '').toString().trim();
  final state = (l['state'] ?? l['stateCode'] ?? '').toString().trim();
  final weak = [city, state].where((s) => s.isNotEmpty).join(', ');
  return weak;
}

/// ---------------- Screen ----------------

class ListingDetailsScreen extends StatefulWidget {
  const ListingDetailsScreen({super.key, required this.listing});
  final Map<String, dynamic> listing;

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  final _api = RealtorApiService();

  late final String listingId;

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  Map<String, dynamic> _data = {};   // merged listing (passed-in + fetched)
  List<dynamic> _mlsDetails = [];    // raw "details" sections (hydrated)
  bool _detailsLoading = true;

  bool _fav = false;
  bool _visited = false;
  bool _agreeToPolicy = false;

  final _publicCommentCtrl = TextEditingController();
  final _visitorFeedbackCtrl = TextEditingController();

  int _photoIndex = 0;

  User? get _user => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.listing);
    listingId = _deriveListingId(_data);
    _bootstrapFlags();
    _ensureListingDoc();
    _loadDetails();       // mapped (fast)
    _hydrateFromRaw();    // raw "details" + any missing photos/address (best-effort)
  }

  @override
  void dispose() {
    _publicCommentCtrl.dispose();
    _visitorFeedbackCtrl.dispose();
    super.dispose();
  }

  /// --------------- Data + API ----------------

  String _deriveListingId(Map<String, dynamic> l) {
    return l['id']?.toString() ??
        l['property_id']?.toString() ??
        l['listingId']?.toString() ??
        ((l['address']?['line'] ?? '') +
                (l['address']?['city'] ?? '') +
                (l['price']?.toString() ?? ''))
            .hashCode
            .toString();
  }

  Future<void> _loadDetails() async {
    try {
      // Use address info to search for details
      final addr = _coerceAddressMap(_data['address'], _data);
      final zip = addr['postalCode'];
      final city = addr['city'];
      final state = addr['state'];
      if ((zip ?? city ?? state) == null || ((zip ?? '').isEmpty && (city ?? '').isEmpty)) {
        setState(() => _detailsLoading = false);
        return;
      }
      final resultsRaw = await _api.searchBuy(
        zipcode: zip?.isNotEmpty == true ? zip : null,
        city: (city?.isNotEmpty == true) ? city : null,
        state: (state?.isNotEmpty == true) ? state : null,
        resultsPerPage: 100,
        page: 1,
      );
      final results = (resultsRaw['data']?['results'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
      // Find best match by property_id or id
      final wantId = (_data['property_id'] ?? _data['id'] ?? '').toString();
      Map<String, dynamic>? match;
      for (final x in results) {
        if (x is Map) {
          final pid = (x['property_id'] ?? x['listing_id'] ?? '').toString();
          if (pid.isNotEmpty && pid == wantId) {
            match = x.cast<String, dynamic>();
            break;
          }
        }
      }
      match ??= results.firstWhere(
        (e) => e is Map<String, dynamic>,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        if (match != null && match.isNotEmpty) {
          _data = _mergeListing(_data, match);
        }
        _detailsLoading = false;
      });
      _ensureListingDoc();
    } catch (_) {
      if (!mounted) return;
      setState(() => _detailsLoading = false);
    }
  }

  /// Background hydration
  Future<void> _hydrateFromRaw() async {
    try {
      final addr = _coerceAddressMap(_data['address'], _data);
      final zip = addr['postalCode'];
      final city = addr['city'];
      final state = addr['state'];
      if ((zip ?? city ?? state) == null || ((zip ?? '').isEmpty && (city ?? '').isEmpty)) return;

      final resultsRaw = await _api.searchBuy(
        zipcode: zip?.isNotEmpty == true ? zip : null,
        city: (city?.isNotEmpty == true) ? city : null,
        state: (state?.isNotEmpty == true) ? state : null,
        resultsPerPage: 100,
        page: 1,
      );
      final results = (resultsRaw['data']?['results'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
      if (results.isEmpty) return;

      final wantId = (_data['property_id'] ?? _data['id'] ?? '').toString();
      Map<String, dynamic>? match;
      for (final x in results) {
        if (x is Map) {
          final pid = (x['property_id'] ?? x['listing_id'] ?? '').toString();
          if (pid.isNotEmpty && pid == wantId) {
            match = x.cast<String, dynamic>();
            break;
          }
        }
      }
      match ??= results.firstWhere(
        (e) => e is Map<String, dynamic>,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>;

      if (match == null || match.isEmpty) return;

      final extraPhotos = _extractPhotoUrls(match);
      final addrString = _bestAddressString({'address': match['location']?['address'] ?? match['address']});
      final details = (match['details'] is List) ? List<dynamic>.from(match['details']) : <dynamic>[];

      if (!mounted) return;
      setState(() {
        final mergedPhotos = <String>{
          ..._extractPhotoUrls(_data),
          ...extraPhotos,
        }.toList();
        _data['photos'] = mergedPhotos;
        if (addrString.trim().isNotEmpty) {
          _data['formattedAddress'] = addrString.trim();
        }
        _mlsDetails = details;
      });
      _ensureListingDoc();
    } catch (_) {
      // silent best-effort
    }
  }

  Map<String, dynamic> _mergeListing(Map<String, dynamic> a, Map<String, dynamic> b) {
    final address = {
      'line':  b['address']?['line'] ?? a['address']?['line'] ?? a['address']?['street'],
      'city':  b['address']?['city'] ?? a['address']?['city'],
      'state': b['address']?['state'] ?? b['address']?['stateCode'] ??
               a['address']?['state'] ?? a['address']?['stateCode'],
      'zip'  : b['address']?['zip'] ?? b['address']?['postalCode'] ??
               a['address']?['postalCode'] ?? a['address']?['zip'] ?? a['address']?['zipCode'],
    };

    final photos = <String>{
      ..._extractPhotoUrls(a),
      ..._extractPhotoUrls(b),
    }.toList();

    return {
      'id'    : _deriveListingId(b).isNotEmpty ? _deriveListingId(b) : _deriveListingId(a),
      'property_id': b['property_id'] ?? a['property_id'],
      'price' : b['price'] ?? a['price'] ?? a['listPrice'],
      'beds'  : b['beds'] ?? b['bedrooms'] ?? a['beds'] ?? a['bedrooms'],
      'baths' : b['baths'] ?? b['bathrooms'] ?? a['baths'] ?? a['bathrooms'],
      'sqft'  : b['sqft'] ?? b['building_size'] ?? a['sqft'] ?? a['squareFeet'],
      'type'  : b['type'] ?? b['propertyType'] ?? a['type'] ?? a['propertyType'],
      'status': b['status'] ?? a['status'],
      'description': b['description'] ??
                     b['publicRemarks'] ??
                     a['description'] ??
                     a['publicRemarks'] ??
                     a['remarks'] ??
                     a['marketingRemarks'],
      'lat'   : b['lat'] ?? b['latitude'] ?? a['lat'] ?? a['coordinates']?['latitude'],
      'lon'   : b['lon'] ?? b['longitude'] ?? a['lon'] ?? a['coordinates']?['longitude'],
      'list_date': b['list_date'] ?? a['list_date'],
      'dom'      : b['dom'] ?? b['daysOnMarket'] ?? a['dom'] ?? a['daysOnMarket'],
      'address'  : address,
      'photos'   : photos,
    };
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
    final l = _data.isNotEmpty ? _data : widget.listing;
    final addr = _coerceAddressMap(l['address'], l);

    final photoUrls = _extractPhotoUrls(l)
        .map(_hiResUrl)
        .toSet()
        .take(16)
        .toList();
    final primaryPhoto = photoUrls.isNotEmpty ? photoUrls.first : null;

    await _fs.collection('listings').doc(listingId).set({
      'address': addr,
      'price': l['price'] ?? l['listPrice'],
      'beds' : l['beds'] ?? l['bedrooms'],
      'baths': l['baths'] ?? l['bathrooms'],
      'sqft' : l['sqft'] ?? l['squareFeet'],
      'lat'  : l['lat'] ?? l['coordinates']?['latitude'],
      'lng'  : l['lon'] ?? l['lng'] ?? l['coordinates']?['longitude'],
      if (primaryPhoto != null) 'primaryPhoto': primaryPhoto,
      if (photoUrls.isNotEmpty) 'photos': photoUrls,
      if (l['details'] is List) 'details': l['details'],
      if (l['type'] != null || l['propertyType'] != null)
        'type': l['type'] ?? l['propertyType'],
      if (l['description'] != null) 'description': l['description'],
      'source'  : 'realtor',
      'provider': 'rapidapi',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// --------------- Favorites / Visited / Comments ----------------

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Marked as visited")));
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
        const SnackBar(content: Text('Mark as “Visited” to post feedback and upload photos.')),
      );
    return;
    }

    if (!_agreeToPolicy) {
      final ok = await _showPhotoPolicyDialog();
      if (ok != true) return;
      setState(() => _agreeToPolicy = true);
    }

    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 90);
    if (x == null) return;

    final u = _user;
    if (u == null) return;
    final file = File(x.path);
    final path = 'listing_photos/$listingId/${u.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final task = await _storage.ref(path).putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final storagePath = task.ref.fullPath;

    await _fs.collection('listings').doc(listingId).collection('photos').add({
      'uid': u.uid,
      'storagePath': storagePath,
      'status': 'pending',
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

  Future<void> _shareListing() async {
    try {
      Navigator.pushNamed(context, '/share-listing', arguments: {
        'listingId': listingId,
        'payload': _data,
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open your “share” flow to pick a person to DM this listing.')),
      );
    }
  }

// Collect plausible photo URLs from many possible listing shapes.
List<String> _extractPhotoUrls(Map<String, dynamic> l) {
  final urls = <String>{};

  void add(dynamic v) {
    if (v is! String) return;
    var s = v.trim();
    if (s.isEmpty) return;
    if (s.startsWith('//')) s = 'https:$s';
    if (s.startsWith('http://')) s = s.replaceFirst('http://', 'https://');
    if (s.startsWith('https://')) urls.add(s);
  }

  // Common fields
  add(l['primaryPhotoUrl']);
  add(l['primaryPhotoURL']);
  add(l['primaryPhoto']);
  add(l['imageUrl']);
  add(l['imageURL']);
  add(l['photo']);
  add(l['thumbnail']);
  add(l['thumbnailUrl']);
  add(l['thumbnailURL']);

  // Sometimes nested under address/location
  final a = l['address'];
  if (a is Map) {
    add(a['imageUrl']);
    add(a['thumbnail']);
  }

  // Realtor/MLS shapes & arrays
  for (final key in const ['photos', 'photoUrls', 'photoURLs', 'images', 'media']) {
    final arr = l[key];
    if (arr is List) {
      for (final item in arr) {
        if (item is String) add(item);
        if (item is Map) {
          add(item['url']);
          add(item['link']);
          add(item['href']);
          add(item['imageUrl']);
          add(item['thumbnailUrl']);
          add(item['mediaUrl']);
        }
      }
    }
  }

  // Realtor “primary_photo”
  if (l['primary_photo'] is Map) add(l['primary_photo']['href']);

  return urls.toList();
}

  /// ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final l = _data;

    // IMPORTANT: use hi-res mapping here
    final photos = _extractPhotoUrls(l).map(_hiResUrl).toList();
    final price = _num(l['price']) ?? 0;

    final addressStr = _bestAddressString(l);
    final beds  = _num(l['beds']) ?? _num(l['bedrooms']);
    final baths = _deriveBaths(l);
    final sqft  = _num(l['sqft']) ?? _num(l['squareFeet']);
    final typeRaw = (l['type'] ?? l['propertyType'])?.toString();
    final type = typeRaw == null ? null : _titleCase(typeRaw.replaceAll('_', ' '));
    final yearBuilt = _coerceYearBuilt(l);
    final dom = _coerceDOM(l);

    final lat = _num(l['lat']);
    final lon = _num(l['lon']) ?? _num(l['lng']);

    final desc = _stringifyDescription(l);

    // For crisp images: compute cache target based on widget size & DPR
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final screenW = MediaQuery.of(context).size.width;
    final headerHeight = 300.0;
    final cacheW = (screenW * dpr * 1.5).round();        // ~1.5x safety
    final cacheH = (headerHeight * dpr * 1.5).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing'),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _shareListing,
            icon: const Icon(Icons.ios_share),
          ),
          if (_detailsLoading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: ListView(
        children: [
          // Photos header
          if (_detailsLoading && photos.isEmpty)
            _photoSkeleton()
          else if (photos.isNotEmpty)
            Column(
              children: [
                Hero(
                  tag: 'listing-$listingId',
                  child: CarouselSlider.builder(
                    itemCount: photos.length,
                    options: CarouselOptions(
                      height: headerHeight,
                      viewportFraction: 1,
                      enableInfiniteScroll: false,
                      onPageChanged: (i, _) => setState(() => _photoIndex = i),
                    ),
                    itemBuilder: (_, i, __) {
                      final url = photos[i];
                      return GestureDetector(
                        onTap: () => _openFullGallery(photos, initial: i),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Semantics(
                              label: 'Property photo ${i + 1} of ${photos.length}',
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                // ask engine for crisp bitmap close to view size
                                cacheWidth: cacheW,
                                cacheHeight: cacheH,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                                loadingBuilder: (ctx, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                },
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
                                      colors: [Colors.transparent, Color(0x22000000)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _Dots(count: photos.length, index: _photoIndex),
                const SizedBox(height: 8),
              ],
            )
          else
            Container(
              height: 200,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Text('No photos available'),
            ),

          // Price + address + chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_detailsLoading && price == 0) _lineSkeleton(width: 160, height: 28)
                else Text('\$${_fmt(price)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: addressStr.isNotEmpty ? () => _openInMaps(addressStr) : null,
                  child: Text(
                    addressStr.isEmpty ? 'Address unavailable' : addressStr,
                    style: TextStyle(
                      fontSize: 16,
                      color: addressStr.isEmpty ? Colors.black87 : Colors.blue,
                      decoration: addressStr.isEmpty ? TextDecoration.none : TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (dom != null && dom >= 0)
                  Text('$dom days on market', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (beds != null) _Chip('${_intOrDec(beds)} bd'),
                    if (baths != null) _Chip('${_intOrDec(baths)} ba'),
                    if (sqft != null) _Chip('${_fmt(sqft)} sqft'),
                    if (type != null) _Chip(type),
                    if (yearBuilt != null) _Chip('Built $yearBuilt'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Save',
                      icon: Icon(_fav ? Icons.favorite : Icons.favorite_border, color: _fav ? Colors.red : null),
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

          // Description
          if (desc != null && desc.isNotEmpty) ...[
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Description', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(desc),
            ),
          ],

          // Facts grid + See more
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text('Property Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => _showFullDetailsSheet(),
                  child: const Text('See more'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _FactsGrid(items:
                [
                  if (l['yearBuilt'] != null)
                    _factItem(Icons.calendar_today, 'Year Built', '${l['yearBuilt']}'),
                  if (l['lotSize'] != null)
                    _factItem(Icons.terrain, 'Lot Size', '${_fmtLotSize(l['lotSize'])}'),
                  if (l['stories'] != null)
                    _factItem(Icons.layers, 'Stories', '${l['stories']}'),
                  if (l['garageSpaces'] != null)
                    _factItem(Icons.garage, 'Garage', '${l['garageSpaces']} spaces'),
                  if (l['heating'] != null)
                    _factItem(Icons.local_fire_department, 'Heating', '${l['heating']}'),
                  if (l['cooling'] != null)
                    _factItem(Icons.ac_unit, 'Cooling', '${l['cooling']}'),
                  if (l['hoaFee'] != null)
                    _factItem(Icons.attach_money, 'HOA Fee', '\$${_fmt(l['hoaFee'])}'),
                  if (l['pricePerSqft'] != null)
                    _factItem(Icons.square_foot, 'Price/Sqft', '\$${_fmt(l['pricePerSqft'])}'),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _factItem(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.black87)),
      ],
    );
  }

  String _fmt(dynamic number) {
    if (number == null) return '';
    if (number is int) {
      return number.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');
    }
    if (number is double) {
      return number.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');
    }
    return number.toString();
  }

  String _fmtLotSize(dynamic value) {
    if (value is num) {
      return '${value.toStringAsFixed(2)} acres';
    }
    return value.toString();
  }

  void _showFullDetailsSheet() {
    // TODO: Implement your full details modal sheet
  }

  // Helper to convert a string to Title Case
  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  // Add this missing method to fix the error
  Widget _photoSkeleton() {
    return Container(
      height: 300,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }

  // Add this method to fix the _openFullGallery error
  void _openFullGallery(List<String> photos, {int initial = 0}) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              CarouselSlider.builder(
                itemCount: photos.length,
                options: CarouselOptions(
                  initialPage: initial,
                  enableInfiniteScroll: false,
                  viewportFraction: 1,
                  height: MediaQuery.of(context).size.height,
                ),
                itemBuilder: (context, i, __) {
                  return InteractiveViewer(
                    child: Image.network(
                      photos[i],
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  );
                },
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
