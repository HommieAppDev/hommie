// lib/listing_detail_screen.dart
import 'dart:io';
import 'dart:math';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants/asset_paths.dart'; // avatarOptions, defaultAvatar
import 'package:hommie/data/realtor_api_service.dart';

// Normalizes Realtor/rdcpix image URLs to higher-res variants.
String _hiResUrl(String url) {
  var u = url.trim();
  if (u.isEmpty) return u;

  // Ensure https
  if (u.startsWith('//')) u = 'https:$u';
  if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');

  // Common RDC small-image pattern: ...-m123456789s.jpg -> ... .jpg
  u = u.replaceAll(RegExp(r'-m\d+s(/.(jpg|jpeg|png))$', caseSensitive: false), r'$1');

  // Optional: drop trivial size query params if present
  // (keeps the URL clean; safe if provider ignores unknown params)
  final uri = Uri.tryParse(u);
  if (uri != null && (uri.queryParameters.containsKey('w') ||
      uri.queryParameters.containsKey('width') ||
      uri.queryParameters.containsKey('h') ||
      uri.queryParameters.containsKey('height'))) {
    u = uri.replace(queryParameters: {
      for (final e in uri.queryParameters.entries)
        if (!{'w','width','h','height','auto'}.contains(e.key.toLowerCase())) e.key: e.value
    }).toString();
  }
  return u;
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
  String? zip   = m['postal_code'] ?? m['zip'] ?? fallback['zip'] ?? fallback['zipCode'];

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
    final zip   = (a['zip'] ?? a['postal_code'] ?? a['postalCode'] ?? '').toString().trim();
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
      final full = await _api.getListingDetails(listingId);
      if (!mounted) return;
      setState(() {
        _data = _mergeListing(_data, full);
        _detailsLoading = false;
      });
      _ensureListingDoc();
    } catch (_) {
      if (!mounted) return;
      setState(() => _detailsLoading = false);
    }
  }

  /// Background hydration: use your existing searchByLocationRaw to grab MLS
  /// "details" sections and any extra photos we didn’t get from the mapped call.
  Future<void> _hydrateFromRaw() async {
    try {
      // figure out a location to search by
      final addr = _coerceAddressMap(_data['address'], _data);
      final zip = addr['postalCode'];
      final city = addr['city'];
      final state = addr['state'];
      if ((zip ?? city ?? state) == null || ((zip ?? '').isEmpty && (city ?? '').isEmpty)) return;

      final rawList = await _api.searchByLocationRaw(
        zip: zip?.isNotEmpty == true ? zip : null,
        city: (city?.isNotEmpty == true) ? city : null,
        state: (state?.isNotEmpty == true) ? state : null,
        status: 'for_sale',
        limit: 100,
      );

      if (rawList.isEmpty) return;

      // Find best match by property_id or listing_id
      final wantId = (_data['property_id'] ?? _data['id'] ?? '').toString();
      Map<String, dynamic>? match;
      for (final x in rawList) {
        if (x is Map) {
          final pid = (x['property_id'] ?? x['listing_id'] ?? '').toString();
          if (pid.isNotEmpty && pid == wantId) {
            match = x.cast<String, dynamic>();
            break;
          }
        }
      }
      match ??= rawList.firstWhere(
        (e) => e is Map<String, dynamic>,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>;

      if (match == null || match.isEmpty) return;

      // Photos + address + details
      final extraPhotos = _extractPhotoUrls(match);
      final addrString = _bestAddressString({'address': match['location']?['address'] ?? match['address']});
      final details = (match['details'] is List) ? List<dynamic>.from(match['details']) : <dynamic>[];

      if (!mounted) return;
      setState(() {
        // merge photos/address
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
    // Use the most recent merged data (_data gets enriched in _loadDetails)
    final l = _data.isNotEmpty ? _data : widget.listing;
    
    // Normalize address
    final addr = _coerceAddressMap(l['address'], l);

    // Collect a small, hi-res photo set to keep doc size reasonable
    final photoUrls = _extractPhotoUrls(l)
        .map(_hiResUrl)
        .toSet()
        .take(16) // keep first 16
        .toList();
    final primaryPhoto = photoUrls.isNotEmpty ? photoUrls.first : null;

    await _fs.collection('listings').doc(listingId).set({
      'address': addr,
      'price': l['price'] ?? l['listPrice'],
      'beds' : l['beds'] ?? l['bedrooms'],
      'baths': l['baths'] ?? l['bathrooms'],
      'sqft' : l['sqft'] ?? l['squareFeet'],

      // location
      'lat'  : l['lat'] ?? l['coordinates']?['latitude'],
      'lng'  : l['lon'] ?? l['lng'] ?? l['coordinates']?['longitude'],

      // extras that other screens want:
      if (primaryPhoto != null) 'primaryPhoto': primaryPhoto,
      if (photoUrls.isNotEmpty) 'photos': photoUrls,
      if (l['details'] is List) 'details': l['details'],
      if (l['type'] != null || l['propertyType'] != null) 
        'type': l['type'] ?? l['propertyType'],
      if (l['description'] != null) 'description': l['description'],
  
      // provenance
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

  /// ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final l = _data;

    final photos = _extractPhotoUrls(l);
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
                      height: 300,
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
            child: _FactsGrid(items: [
              if (type != null) MapEntry('Type', type),
              if (beds != null) MapEntry('Bedrooms', _intOrDec(beds)),
              if (baths != null) MapEntry('Bathrooms', _intOrDec(baths)),
              if (sqft != null) MapEntry('Square Feet', _fmt(sqft)),
              if (yearBuilt != null) MapEntry('Year Built', '$yearBuilt'),
              if (_data['hoa'] != null) MapEntry('HOA', '\$${_fmt(_num(_data['hoa']) ?? 0)}'),
            ]),
          ),

          // Mini map
          if (lat != null && lon != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: const [
                  Icon(Icons.map_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat.toDouble(), lon.toDouble()),
                      initialZoom: 13,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hommie.app',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          width: 40,
                          height: 40,
                          point: LatLng(lat.toDouble(), lon.toDouble()),
                          child: const Icon(Icons.location_on, size: 36, color: Colors.red),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const Divider(height: 1),

          // Visitor Feedback
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: const [
                Icon(Icons.verified_user_outlined, size: 20),
                SizedBox(width: 8),
                Text('Visitor Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fs.collection('listings').doc(listingId).collection('visitor_feedback').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Only visitors can leave feedback about what they saw.\nBe respectful. No interior photos.',
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
                    );
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _fs.collection('users').doc(uid).snapshots(),
                    builder: (_, userSnap) {
                      final user = userSnap.data?.data();
                      final display = user?['displayName'] ?? d['displayName'] ?? 'Visitor';
                      final avatarKeyOrUrl = user?['avatarKey'] ?? user?['avatarUrl'] ?? user?['photoURL'];
                      final isMe = _user?.uid == uid;
                      return ListTile(
                        leading: GestureDetector(onTap: () => _openUserProfile(context, uid), child: _userAvatar(avatarKeyOrUrl)),
                        title: GestureDetector(onTap: () => _openUserProfile(context, uid), child: Text(display, style: const TextStyle(fontWeight: FontWeight.w600))),
                        subtitle: Text(d['text'] ?? ''),
                        trailing: isMe ? null : IconButton(tooltip: 'Message', icon: const Icon(Icons.mail_outline), onPressed: () => _openDM(context, uid)),
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
              child: Text('Mark as “Visited” to post feedback and upload photos.', style: TextStyle(color: Colors.orange.shade700)),
            ),

          // Approved visitor photos
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
                        future: storagePath == null ? Future.value('') : _storage.ref(storagePath).getDownloadURL(),
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

          // Comments
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
            stream: _fs.collection('listings').doc(listingId).collection('comments').orderBy('createdAt', descending: true).snapshots(),
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
                    return const ListTile(leading: Icon(Icons.person_outline), title: Text('User'));
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _fs.collection('users').doc(uid).snapshots(),
                    builder: (_, userSnap) {
                      final user = userSnap.data?.data();
                      final display = user?['displayName'] ?? c['displayName'] ?? 'User';
                      final avatarKeyOrUrl = user?['avatarKey'] ?? user?['avatarUrl'] ?? user?['photoURL'];
                      final isMe = _user?.uid == uid;
                      return ListTile(
                        leading: GestureDetector(onTap: () => _openUserProfile(context, uid), child: _userAvatar(avatarKeyOrUrl)),
                        title: GestureDetector(onTap: () => _openUserProfile(context, uid), child: Text(display, style: const TextStyle(fontWeight: FontWeight.w600))),
                        subtitle: Text(c['text'] ?? ''),
                        trailing: isMe ? null : IconButton(tooltip: 'Message', icon: const Icon(Icons.mail_outline), onPressed: () => _openDM(context, uid)),
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

  /// ---------------- helpers ----------------

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

    // mapped/common
    add(l['primaryPhotoUrl']);
    add(l['primaryPhotoURL']);
    add(l['primaryPhoto']);
    add(l['imageUrl']);
    add(l['imageURL']);
    add(l['photo']);
    add(l['thumbnail']);
    add(l['thumbnailUrl']);
    add(l['thumbnailURL']);

    final a = l['address'];
    if (a is Map) {
      add(a['imageUrl']);
      add(a['thumbnail']);
    }

    // raw arrays & realtor shapes
    for (final key in const ['photos', 'photoUrls', 'photoURLs', 'images', 'media']) {
      final arr = l[key];
      if (arr is List) {
        for (final item in arr) {
          if (item is String) add(item);
          if (item is Map) {
            add(item['url']);
            add(item['link']);
            add(item['href']);          // realtor sample
            add(item['imageUrl']);
            add(item['thumbnailUrl']);
            add(item['mediaUrl']);
          }
        }
      }
    }
    // primary_photo: { href: ... }
    if (l['primary_photo'] is Map) add(l['primary_photo']['href']);

    return urls.toList();
  }

  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _intOrDec(num n) => (n % 1 == 0) ? n.toInt().toString() : n.toString();

  num? _deriveBaths(Map<String, dynamic> l) {
    final tot = _num(l['baths']) ??
        _num(l['bathrooms']) ??
        _num(l['bathroomsTotal']) ??
        _num(l['bathroomsTotalInteger']);
    if (tot != null) return tot;

    final full = _num(l['fullBathrooms']) ?? _num(l['bathsFull']) ?? 0;
    final half = _num(l['halfBathrooms']) ?? _num(l['bathsHalf']) ?? 0;
    if (full != 0 || half != 0) return full + (half * 0.5);
    return null;
  }

  int? _coerceYearBuilt(Map<String, dynamic> l) {
    final y = l['year_built'] ?? l['yearBuilt'] ?? l['year'];
    final n = (y is num) ? y.toInt() : int.tryParse('${y ?? ''}');
    if (n == null || n < 1700 || n > DateTime.now().year + 1) return null;
    return n;
  }

  int? _coerceDOM(Map<String, dynamic> l) {
    final dom = _num(l['dom']) ?? _num(l['daysOnMarket']);
    if (dom != null) return dom.toInt();

    final listDateRaw = l['list_date'];
    if (listDateRaw is String && listDateRaw.isNotEmpty) {
      try {
        final dt = DateTime.tryParse(listDateRaw);
        if (dt != null) {
          final days = DateTime.now().difference(dt).inDays;
          return max(days, 0);
        }
      } catch (_) {}
    }
    return null;
  }

  void _openFullGallery(List<String> urls, {int initial = 0}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _FullScreenGallery(
          heroTag: 'listing-$listingId',
          urls: urls,
          initialIndex: initial,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _showFullDetailsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        final sections = _mlsDetails;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: (sections.isNotEmpty)
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: sections.length,
                    itemBuilder: (_, i) {
                      final d = sections[i];
                      if (d is! Map) return const SizedBox.shrink();
                      final category = (d['category'] ?? '').toString();
                      final texts = (d['text'] is List) ? List<String>.from(d['text']) : const <String>[];
                      if (category.trim().isEmpty && texts.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(category, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ...texts.map((t) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('•  '),
                                      Expanded(child: Text(t)),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      );
                    },
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No additional details available.', style: TextStyle(color: Colors.grey.shade700)),
                    ),
                  ),
          ),
        );
      },
    );
  }

  // skeletons
  Widget _photoSkeleton() => Container(
        height: 300,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _lineSkeleton({double width = 120, double height = 18}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
      );

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

  String _titleCase(String s) {
    final parts = s.split(' ');
    return parts
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.isNotEmpty ? p[0].toUpperCase() + p.substring(1).toLowerCase() : '')
        .join(' ');
  }
}

String? _stringifyDescription(Map<String, dynamic> l) {
  final d = l['description'] ?? l['publicRemarks'] ?? l['remarks'] ?? l['marketingRemarks'];
  if (d == null) return null;
  if (d is String) return d.trim();
  if (d is Map) {
    for (final k in const ['text', 'value', 'description', 'remarks']) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
  return null;
}

/// -------- small UI widgets --------

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

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 12,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            count,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 8,
              width: i == index ? 20 : 8,
              decoration: BoxDecoration(
                color: i == index ? Colors.black87 : Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.items, super.key});

  final List<MapEntry<String, String>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 40,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final entry = items[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.key}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            Expanded(child: Text(entry.value)),
          ],
        );
      },
    );
  }
}


class _FullScreenGallery extends StatefulWidget {
  const _FullScreenGallery({
    required this.heroTag,
    required this.urls,
    this.initialIndex = 0,
  });

  final String heroTag;
  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text('${_idx + 1}/${widget.urls.length}'),
      ),
      body: Hero(
        tag: widget.heroTag,
        child: PageView.builder(
          controller: _pc,
          onPageChanged: (i) => setState(() => _idx = i),
          itemCount: widget.urls.length,
          itemBuilder: (_, i) {
            final url = widget.urls[i];
            return InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
