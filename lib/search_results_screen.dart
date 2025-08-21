import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hommie/data/realtor_api_service.dart';
import 'package:hommie/widgets/listing_media.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'debug/image_logging.dart';

// Helper to robustly extract virtual tour URLs from listing objects
List<String> _extractVirtualTours(Map<String, dynamic> l) {
  final urls = <String>[];
  void add(dynamic v) {
    if (v is String && v.trim().isNotEmpty) urls.add(v.trim());
  }
  final vt = l['virtual_tours'] ?? l['virtualTours'] ?? l['tours'] ?? l['matterport'];
  if (vt is List) {
    for (final item in vt) {
      if (item is String) add(item);
      if (item is Map) {
        add(item['url']);
        add(item['href']);
        add(item['tour_url']);
        add(item['matterport_url']);
      }
    }
  } else if (vt is String) {
    add(vt);
  }
  add(l['unbranded_virtual_tour']);
  add(l['branded_virtual_tour']);
  return urls.toSet().toList();
}

// Modern WebView widget for virtual tours
class InAppTourWebView extends StatefulWidget {
  final String url;
  const InAppTourWebView({super.key, required this.url});

  @override
  State<InAppTourWebView> createState() => _InAppTourWebViewState();
}

class _InAppTourWebViewState extends State<InAppTourWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Virtual Tour')),
      body: WebViewWidget(controller: _controller),
    );
  }
}


class SearchResultsScreen extends StatefulWidget {
    const SearchResultsScreen({Key? key}) : super(key: key);

    @override
    _SearchResultsScreenState createState() => _SearchResultsScreenState();
  }

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  void _toggleVisited(Map<String, dynamic> listing) {
    // Implement visited logic (e.g., update Firestore or local state)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visited status updated!')),
    );
  }
  void _toggleLike(Map<String, dynamic> listing) {
    // Implement like logic (e.g., update Firestore or local state)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Like status updated!')),
    );
  }
  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    DateTime? dt;
    if (ts is DateTime) {
      dt = ts;
    } else if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      dt = DateTime.tryParse(ts);
    }
    if (dt == null) return ts.toString();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) {
      return '${dt.month}/${dt.day}/${dt.year}';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Map<String, int> _commentCounts = {};
  Map<String, List<Map<String, dynamic>>> _commentsCache = {};
  final _commentController = TextEditingController();
  final _api = RealtorApiService();
  List<Map<String, dynamic>> _listings = [];
  bool _loading = false;
  String? _lastError;
  bool _isFeedMode = true;
  Map<String, dynamic>? _lastArgs;

  Future<int> _fetchCommentCount(Map<String, dynamic> listing) async {
    final id = listing['id'] ?? listing['property_id'] ?? listing['listing_id'] ?? listing['mlsId'] ?? listing['zpid'];
    if (id == null) return 0;
    final snap = await _fs.collection('listings').doc(id.toString()).collection('comments').count().get();
    return snap.count ?? 0;
  }

  Future<List<Map<String, dynamic>>> _fetchComments(Map<String, dynamic> listing) async {
    final id = listing['id'] ?? listing['property_id'] ?? listing['listing_id'] ?? listing['mlsId'] ?? listing['zpid'];
    if (id == null) return [];
    final snap = await _fs.collection('listings').doc(id.toString()).collection('comments').orderBy('createdAt', descending: true).limit(30).get();
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<void> _showCommentsDialog(Map<String, dynamic> listing) async {
    final id = listing['id'] ?? listing['property_id'] ?? listing['listing_id'] ?? listing['mlsId'] ?? listing['zpid'];
    if (id == null) return;
    List<Map<String, dynamic>> comments = [];
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Comments'),
              content: SizedBox(
                width: 350,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchComments(listing),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    comments = snapshot.data ?? [];
                    if (comments.isEmpty) {
                      return const Text('No comments yet.');
                    }
                    return SizedBox(
                      height: 250,
                      child: ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (context, i) {
                          final c = comments[i];
                          return ListTile(
                            leading: const Icon(Icons.person, size: 24),
                            title: Text(c['displayName'] ?? 'User'),
                            subtitle: Text(c['text'] ?? ''),
                            trailing: c['createdAt'] != null ? Text(_formatTimestamp(c['createdAt'])) : null,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(hintText: 'Write a comment...'),
                  maxLines: 2,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await _addComment(listing);
                        setStateDialog(() {});
                      },
                      child: const Text('Post'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }


  Future<void> _addComment(Map<String, dynamic> listing) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final id = listing['id'] ?? listing['property_id'] ?? listing['listing_id'] ?? listing['mlsId'] ?? listing['zpid'];
    if (id == null) return;
    final txt = _commentController.text.trim();
    if (txt.isEmpty) return;
    await _fs.collection('listings').doc(id.toString()).collection('comments').add({
      'uid': u.uid,
      'displayName': u.displayName ?? 'User',
      'text': txt,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _commentController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment added!')));
  }

  Future<void> _showCommentDialog(Map<String, dynamic> listing) async {
    _commentController.clear();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Comment'),
        content: TextField(
          controller: _commentController,
          decoration: const InputDecoration(hintText: 'Write your comment...'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _addComment(listing);
              Navigator.pop(ctx);
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }

  void _shareListing(Map<String, dynamic> listing) {
    final addr = _ListingCard._composeAddress(listing);
    final price = listing['price'] != null ? ' 24${listing['price']}' : '';
    String url = '';
    final photos = (listing['photos'] as List?)?.cast<String>() ?? [];
    if (photos.isNotEmpty) {
      final hiRes = _hiResCandidates(photos.first);
      if (hiRes.isNotEmpty) url = hiRes.first;
    }
    final text = 'Check out this listing: $addr $price $url';
    Share.share(text);
  }

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        if (_lastArgs == null || !_mapEquals(_lastArgs!, args)) {
          _lastArgs = Map<String, dynamic>.from(args);
          _fetchWithArgs(args);
        }
      } else if (_lastArgs == null) {
        // No args, only fetch once
        _lastArgs = {};
        _fetchWithArgs({});
      }

      // Precache first image for smoother UX
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_listings.isNotEmpty && (_listings.first['photos'] is List) && (_listings.first['photos'] as List).isNotEmpty) {
          final firstUrl = (_listings.first['photos'] as List).first;
          final normalized = pickBestPhotoUrl([firstUrl]);
          if (normalized != null) {
            precacheImage(CachedNetworkImageProvider(normalized), context);
          }
        }
      });
    }

    bool _mapEquals(Map a, Map b) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || a[k] != b[k]) return false;
      }
      return true;
    }

    Future<void> _fetchWithArgs(Map<String, dynamic> args) async {
      setState(() {
        _loading = true;
        _lastError = null;
      });

      try {
        if (dotenv.env.isEmpty) {
          await dotenv.load();
        }

        final city = (args['city'] as String?)?.trim();
        final state = (args['state'] as String?)?.trim();
        final zip = (args['zip'] as String?)?.trim();

        final raw = await _api.searchBuy(
          city: city,
          state: state,
          zipcode: zip,
          resultsPerPage: 20,
          page: 1,
        );

        final data = raw['data'];
        final List<Map<String, dynamic>> results =
            (data?['results'] as List? ?? const [])
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();

        // Compose photo and virtual tours for each result
        for (final l in results) {
          final List<String> photos = [];
          if (l['primary_photo'] is Map && l['primary_photo']['href'] is String) {
            photos.add(l['primary_photo']['href']);
          }
          if (l['photos'] is List) {
            for (final p in l['photos']) {
              if (p is String) photos.add(p);
              if (p is Map && p['href'] is String) photos.add(p['href']);
              if (p is Map && p['url'] is String) photos.add(p['url']);
            }
          }
          l['photos'] = photos;
          l['virtual_tours'] = _extractVirtualTours(l);
        }

        // Ensure virtual tours load first in feed
        results.sort((a, b) {
          final av = (a['virtual_tours'] as List?)?.isNotEmpty ?? false;
          final bv = (b['virtual_tours'] as List?)?.isNotEmpty ?? false;
          return (bv ? 1 : 0) - (av ? 1 : 0);
        });

        debugPrint('🔎 Results=${results.length}');
        setState(() {
          _listings = results;
        });
      } catch (e) {
        setState(() {
          _lastError = e.toString();
        });
      } finally {
        setState(() {
          _loading = false;
        });
      }
    }

    num? _num(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Search Results'),
          actions: [
            IconButton(
              icon: Icon(_isFeedMode ? Icons.view_list : Icons.view_carousel),
              tooltip: _isFeedMode ? 'Switch to List View' : 'Switch to Feed View',
              onPressed: () => setState(() => _isFeedMode = !_isFeedMode),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
        : _lastError != null
          ? Center(child: Text('Error:\n${_lastError!}'))
          : _isFeedMode
            ? _buildFeedView()
            : _buildListView(),
      );
    }

    // Feed mode: Fullscreen, swipeable listings with photo carousel and actions
    Widget _buildFeedView() {
      if (_listings.isEmpty) {
        return const Center(child: Text('No listings found.'));
      }
      // Feed view: paged, full-screen, one listing per page (like Instagram/Tinder)
      return PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _listings.length,
        itemBuilder: (context, index) {
          final l = _listings[index];
            // Virtual tours as default landing if available
            final validTours = _extractVirtualTours(l);
            final photos = (l['photos'] as List?)?.cast<String>() ?? [];
            final filteredPhotos = photos.where((p) => !p.trim().endsWith('�241') && !p.trim().endsWith('�241?dpr=2') && !p.trim().endsWith('�241/')).toList();
            final hiResPhotos = filteredPhotos.expand(_hiResCandidates).where((u) => !u.contains('�241')).toList();
            assert(() {
              if (kDebugMode && hiResPhotos.isNotEmpty) {
                logImageUrlIssues(hiResPhotos.first);
              }
              return true;
            }());
            return SizedBox.expand(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pushNamed(
                    '/listing-details',
                    arguments: {'listing': l},
                  );
                },
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show virtual tour if available, else photo carousel
                      Expanded(
                        child: validTours.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox.expand(
                                  child: InAppTourWebView(url: validTours.first),
                                ),
                              )
                            : ListingImage(
                                photos: hiResPhotos,
                                priceLabel: formatListingPrice(l['price'], fallback: l['formattedPrice']),
                                fullScreen: true,
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_ListingCard._composeAddress(l), style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.favorite_border, color: Colors.red),
                                  onPressed: () => _toggleLike(l),
                                ),
                                Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.comment, color: Colors.blue),
                                      onPressed: () => _showCommentsDialog(l),
                                    ),
                                    FutureBuilder<int>(
                                      future: _fetchCommentCount(l),
                                      builder: (context, snapshot) {
                                        final count = snapshot.data ?? 0;
                                        if (count == 0) return const SizedBox.shrink();
                                        return Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                          child: Text(
                                            '$count',
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  onPressed: () => _toggleVisited(l),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.ios_share, color: Colors.black),
                                  onPressed: () => _shareListing(l),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        },
      );
    }

    // List mode: Scrollable list of cards
    Widget _buildListView() {
      if (_listings.isEmpty) {
        return const Center(child: Text('No listings found.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _listings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final l = _listings[index];
          final photos = (l['photos'] as List?)?.cast<String>() ?? [];
          final filteredPhotos = photos.where((p) => !p.trim().endsWith('�241') && !p.trim().endsWith('�241?dpr=2') && !p.trim().endsWith('�241/')).toList();
          final hiResPhotos = filteredPhotos.expand(_hiResCandidates).where((u) => !u.contains('�241')).toList();
          assert(() {
            if (kDebugMode && hiResPhotos.isNotEmpty) {
              logImageUrlIssues(hiResPhotos.first);
            }
            return true;
          }());
          return GestureDetector(
            onTap: () {
              Navigator.of(context).pushNamed(
                '/listing-details',
                arguments: {'listing': l},
              );
            },
            child: Card(
              child: Row(
                children: [
                  if (hiResPhotos.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: ListingImage(
                          photos: hiResPhotos,
                          priceLabel: formatListingPrice(l['price'], fallback: l['formattedPrice']),
                          fullScreen: false,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 72,
                      height: 72,
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Icon(Icons.home_outlined, size: 40),
                    ),
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      title: Text(_ListingCard._composeAddress(l)),
                      subtitle: Text(formatListingPrice(l['price'], fallback: l['formattedPrice'])),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    String? _addrCity(Map<String, dynamic> l) {
      final a = l['address'];
      return (a is Map ? a['city'] : null) ?? l['city'];
    }

    String? _addrState(Map<String, dynamic> l) {
      final a = l['address'];
      return (a is Map ? (a['state'] ?? a['stateCode']) : null) ?? l['state'] ?? l['stateCode'];
    }

    num? _bedsValue(Map<String, dynamic> l) {
      return _num(l['beds']) ??
          _num(l['bedrooms']) ??
          _num(l['numBedrooms']) ??
          _num(l['bed']) ??
          _num(l['beds_min']) ??
          _num(l['beds_max']);
    }

    // ---------- skeletons ----------
    Widget _buildSkeletonList() {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Container(height: 18, width: 120, color: Colors.grey.shade200),
                      const SizedBox(height: 10),
                      Container(height: 14, width: double.infinity, color: Colors.grey.shade200),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(child: Container(height: 28, color: Colors.grey.shade200)),
                          const SizedBox(width: 8),
                          Expanded(child: Container(height: 28, color: Colors.grey.shade200)),
                          const SizedBox(width: 8),
                          Expanded(child: Container(height: 28, color: Colors.grey.shade200)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  // ...existing code...
  } // <-- Correct closing brace for _SearchResultsScreenState

/* ===========================
   IMAGE HELPERS (TOP-LEVEL)
   =========================== */

class _SmartImage extends StatefulWidget {
  const _SmartImage({
    required this.urls,
    this.fit = BoxFit.cover,
    this.height,
    this.width,
  });

  final List<String> urls;
  final BoxFit fit;
  final double? height, width;

  @override
  State<_SmartImage> createState() => _SmartImageState();
}

class _SmartImageState extends State<_SmartImage> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      );
    }
    final url = widget.urls[_idx];
    if (url == null || url.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      );
    }
    // ...existing code...
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }
}

// SAFE hi-res candidates: keep original + upgraded variants (no "$1")
List<String> _hiResCandidates(String url) {
  String norm(String u) {
    var s = u.trim();
    if (s.startsWith('//')) s = 'https:$s';
    if (s.startsWith('http://')) s = s.replaceFirst('http://', 'https://');
    return s;
  }

  final original = norm(url);
  String hi = original;

  // RDC: ...-m12345s.jpg -> ... .jpg
  hi = hi.replaceAll(RegExp(r'-m\d+s(\.(jpg|jpeg|png))$', caseSensitive: false), r'$1');

  // Remove path segments like /300x200 or /1200x900 (at end or before another /)
  final noPathSize = hi.replaceAll(RegExp(r'/\d{2,4}x\d{2,4}(?=(/|$))'), '');

  // Query sizes -> bump and add dpr
  String bump(String u) {
    u = u.replaceAll(RegExp(r'([?&])w=\d+'), r'$1w=1600');
    u = u.replaceAll(RegExp(r'([?&])width=\d+'), r'$1width=1600');
    u = u.replaceAll(RegExp(r'([?&])h=\d+'), r'$1h=1200');
    u = u.replaceAll(RegExp(r'([?&])height=\d+'), r'$1height=1200');
    u = u.replaceAll(RegExp(r'([?&])size=(small|medium)'), r'$1size=large');
    if (!u.contains('dpr=')) u += (u.contains('?') ? '&' : '?') + 'dpr=2';
    return u;
  }

  final bumped = bump(noPathSize);

  // Strip size-ish query params entirely
  String stripQuerySizes(String u) {
    final uri = Uri.parse(u);
    final qp = Map.of(uri.queryParameters)
      ..removeWhere((k, _) => {
        'w','width','h','height','fit','resize','size','auto','quality','q','crop','cs','fm','fl','dpr'
      }.contains(k.toLowerCase()));
    return uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
  }

  final strippedQuery = stripQuerySizes(noPathSize);

  final set = <String>{};
  void add(String s) { if (s.isNotEmpty) set.add(s); }
  add(bumped);
  add(strippedQuery);
  add(original);
  return set.toList();
}

/* ===========================
   LISTING CARD + FILTER BAR + MINI PREVIEW
   =========================== */

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.data,
    required this.saved,
    required this.likes,
    required this.onTap,
    required this.onSaveToggle,
    required this.onHide,
    required this.onShare,
    required this.onOpenMaps,
  });

  final Map<String, dynamic> data;
  final bool saved;
  final int likes;
  final VoidCallback onTap;
  final VoidCallback onSaveToggle;
  final VoidCallback onHide;
  final VoidCallback onShare;
  final VoidCallback onOpenMaps;

  static String? _prettyType(dynamic v) {
    final s = (v ?? '').toString().trim().replaceAll('_', ' ');
    if (s.isEmpty) return null;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1).toLowerCase()))
        .join(' ');
  }

  static String _composeAddress(Map<String, dynamic> l) {
    final a = l['address'];
    String? line, city, state;
    if (a is Map) {
      line  = a['line'] ?? a['street'];
      city  = a['city'];
      state = a['state'] ?? a['stateCode'];
    }
    line ??= l['addressLine1'] ?? l['streetAddress'] ?? l['formattedAddress'];
    state ??= l['state'] ?? l['stateCode'];
    final fallback = (l['formattedAddress'] ?? '').toString();
    if ((line ?? '').toString().trim().isEmpty) {
      return fallback.isNotEmpty ? fallback : '${city ?? ''}, ${state ?? ''}';
    }
    return '$line, ${city ?? ''}, ${state ?? ''}'.replaceAll(RegExp(r',\s*,+'), ', ');
  }

  @override
  Widget build(BuildContext context) {
    final price = _num(data['price']) ?? 0;
    final beds  = _bedsValue(data);
    final baths = _bathsValue(data);
    final sqft  = _num(data['sqft']);
    final type  = _prettyType(data['type'] ?? data['propertyType']);
    final addr  = _composeAddress(data);

    final status = _statusPretty(data);
    final domRaw = data['dom'] ?? data['daysOnMarket'] ?? data['days_on_market'];
    final dom = (domRaw is num) ? domRaw.toInt() : int.tryParse('${domRaw ?? ''}');

  final photos = _extractPhotoUrls(data).expand(_hiResCandidates).toList();
    final heroTag = 'photo-${data['id'] ?? addr}';

    final flags = data['flags'] is Map ? (data['flags'] as Map) : const {};
    final isNew = flags['is_new_listing'] == true;
    final priceReduced = (data['price_reduced_amount'] != null) || (data['price_reduced_date'] != null);

    return Dismissible(
      key: ValueKey('listing-' + (data['id'] != null ? data['id'].toString() : addr)),
      background: _swipeBg(context, Icons.favorite, 'Save'),
      secondaryBackground: _swipeBg(context, Icons.hide_source, 'Hide', alignEnd: true),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onSaveToggle();
          return false;
        } else {
          onHide();
          return true;
        }
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(addr ?? ''),
              subtitle: Text(type ?? ''),
              trailing: Text(_fmt(price).toString()),
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }

  // ---- status helpers ----
  static String? _statusPretty(Map<String, dynamic> l) {
    final raw = (l['status'] ??
            l['prop_status'] ??
            l['status_type'] ??
            (l['flags'] is Map && (l['flags']['is_contingent'] == true) ? 'under_contract' : null))
        ?.toString()
        .toLowerCase();

    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('for_sale') || raw == 'active') return 'For sale';
    if (raw.contains('pending')) return 'Pending';
    if (raw.contains('under') || raw.contains('contingent')) return 'Under contract';
    if (raw.contains('coming')) return 'Coming soon';
    if (raw.contains('sold') || raw.contains('closed')) return 'Sold';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  void _showActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.favorite_border), title: const Text('Save / Unsave'), onTap: () { Navigator.pop(context); onSaveToggle(); }),
            ListTile(leading: const Icon(Icons.ios_share), title: const Text('Share (copy address)'), onTap: () { Navigator.pop(context); onShare(); }),
            ListTile(leading: const Icon(Icons.map_outlined), title: const Text('Open in Maps'), onTap: () { Navigator.pop(context); onOpenMaps(); }),
            ListTile(leading: const Icon(Icons.hide_source), title: const Text('Hide'), onTap: () { Navigator.pop(context); onHide(); }),
          ],
        ),
      ),
    );
  }

  static Widget _swipeBg(BuildContext context, IconData icon, String label, {bool alignEnd = false}) {
    return Container(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!alignEnd) Icon(icon),
          if (!alignEnd) const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (alignEnd) const SizedBox(width: 8),
          if (alignEnd) Icon(icon),
        ],
      ),
    );
  }

  static Widget _badge(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
        fontSize: 11, fontWeight: FontWeight.w700,
      )),
    );
  }

  static Widget _miniChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
        color: Colors.grey.shade100,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------- image helpers (kept for Firestore mirroring etc.) ----------
  static String _maybeHiRes(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;

    // normalize scheme
    if (u.startsWith('//')) u = 'https:$u';
    if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');

    // RDC patterns like ...-m123s.jpg or ...-m123x456s.png -> strip the -m...s
    u = u.replaceAllMapped(RegExp(r'-m\d+s\.(jpg|jpeg|png)$', caseSensitive: false), (m) => '.${m[1]}');
    u = u.replaceAllMapped(RegExp(r'-m\d+x\d+s\.(jpg|jpeg|png)$', caseSensitive: false), (m) => '.${m[1]}');

    // Path sizes like /300x200/ -> /1600x1200/ (preserves trailing slash or end)
    u = u.replaceAllMapped(RegExp(r'/\d{2,4}x\d{2,4}(/|$)'), (m) => '/1600x1200${m[1]}');

    // Query sizes: bump width to ~1600, remove tiny heights, upgrade size=*
    final uri = Uri.tryParse(u);
    if (uri != null) {
      final qp = Map<String, String>.from(uri.queryParameters);
      bool changed = false;

      void setWidth(int v) {
        if (qp.containsKey('w')) { qp['w'] = '$v'; changed = true; }
        if (qp.containsKey('width')) { qp['width'] = '$v'; changed = true; }
      }

      void removeHeight() {
        if (qp.remove('h') != null) changed = true;
        if (qp.remove('height') != null) changed = true;
      }

      if (qp.containsKey('size')) {
        final v = qp['size']!.toLowerCase();
        if (v == 'small' || v == 'medium') { qp['size'] = 'large'; changed = true; }
      }

      setWidth(1600);
      removeHeight();

      if (changed) {
        u = uri.replace(queryParameters: qp).toString();
      }
    }

    return u;
  }

  static List<String> _extractPhotoUrls(Map<String, dynamic> l) {
    final urls = <String>[];
    void add(dynamic v) {
      if (v is! String) return;
      var s = v.trim();
      if (s.isEmpty) return;
      if (s.startsWith('//')) s = 'https:$s';
      if (s.startsWith('http://')) s = s.replaceFirst('http://', 'https://');
      if (s.startsWith('https://')) urls.add(_maybeHiRes(s));
    }

    // Handle various listing photo field formats
    if (l['photos'] is List) {
      for (var p in l['photos']) {
        if (p is String) {
          add(p);
        } else if (p is Map && p['url'] is String) {
          add(p['url']);
        }
      }
    }
    if (l['photo'] is String) add(l['photo']);
    if (l['primary_photo'] is Map && l['primary_photo']['href'] is String) {
      add(l['primary_photo']['href']);
    }
    if (l['thumbnail'] is String) add(l['thumbnail']);
    if (l['images'] is List) {
      for (var img in l['images']) {
        if (img is String) add(img);
        if (img is Map && img['url'] is String) add(img['url']);
      }
    }

    return urls.toSet().toList(); // ensure unique URLs
  }

  static num? _bedsValue(Map<String, dynamic> l) {
    num? n(v) => (v is num) ? v : num.tryParse(v?.toString() ?? '');
    return n(l['beds']) ?? n(l['bedrooms']) ?? n(l['numBedrooms']) ?? n(l['bed']) ?? n(l['beds_min']) ?? n(l['beds_max']);
  }

  static num? _bathsValue(Map<String, dynamic> l) {
    num? n(v) => (v is num) ? v : num.tryParse(v?.toString() ?? '');
    final tot = n(l['baths']) ?? n(l['bathrooms']) ?? n(l['bathroomsTotal']) ?? n(l['bathroomsTotalInteger']) ?? n(l['baths_full_calc']);
    if (tot != null) return tot;
    final full = n(l['fullBathrooms']) ?? n(l['bathsFull']) ?? n(l['bathrooms_full']) ?? 0;
    final half = n(l['halfBathrooms']) ?? n(l['bathsHalf']) ?? n(l['bathrooms_half']) ?? 0;
    if ((full ?? 0) != 0 || (half ?? 0) != 0) return (full ?? 0) + (half ?? 0) * 0.5;
    return null;
  }

  static String _fmtBeds(num? n) {
    if (n == null) return '-';
    final isInt = n % 1 == 0;
    return isInt ? n.toInt().toString() : n.toString();
  }

  static String _fmtBaths(num? n) {
    if (n == null) return '-';
    return (n % 1 == 0) ? n.toInt().toString() : n.toString();
  }

  static String _fmt(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      b.write(s[i]);
      if (idx > 1 && idx % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  static num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.city,
    required this.state,
    required this.zip,
    required this.radiusMiles,
    required this.beds,
    required this.baths,
    required this.minPrice,
    required this.maxPrice,
    required this.minSqft,
    required this.typeCode,
    required this.garage,
    required this.pool,
    required this.pets,
    required this.waterfront,
    required this.views,
    required this.basement,
    required this.domMax,
    required this.yearBuiltMin,
    required this.lotAcresMin,
    required this.hoaMax,
    required this.openHouse,
    super.key,
  });

  final String? city, state, zip;
  final double radiusMiles;
  final int? beds, minPrice, maxPrice;
  final double? baths, lotAcresMin;
  final int? minSqft, domMax, yearBuiltMin, hoaMax;
  final String? typeCode;
  final bool garage, pool, pets, waterfront, views, basement, openHouse;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[];

    final loc = [
      if ((city ?? '').isNotEmpty) city,
      if ((state ?? '').isNotEmpty) state,
      if ((zip ?? '').isNotEmpty) zip,
    ].whereType<String>().join(', ');
    if (loc.isNotEmpty) chips.add(loc);
    chips.add('${radiusMiles.toStringAsFixed(0)} mi');

    if (beds != null) chips.add('$beds bd');
    if (baths != null) chips.add('${baths! % 1 == 0 ? baths!.toInt() : baths} ba');
    if (minPrice != null || maxPrice != null) {
      final lo = minPrice == null ? '' : '\$${_fmt(minPrice!)}';
      final hi = maxPrice == null ? '' : '\$${_fmt(maxPrice!)}';
      chips.add([lo, hi].where((s) => s.isNotEmpty).join('–'));
    }
    if (minSqft != null) chips.add('${_fmt(minSqft!)}+ sqft');
    if ((typeCode ?? '').isNotEmpty) chips.add(_titleCase(typeCode!.replaceAll('_', ' ')));
    if (garage) chips.add('garage');
    if (pool) chips.add('pool');
    if (pets) chips.add('pets ok');
    if (waterfront) chips.add('waterfront');
    if (views) chips.add('views');
    if (basement) chips.add('basement');
    if (domMax != null) chips.add('≤ ${domMax} DOM');
    if (yearBuiltMin != null) chips.add('≥ $yearBuiltMin');
    if (lotAcresMin != null) chips.add('≥ ${lotAcresMin!.toStringAsFixed(2)} ac');
    if (hoaMax != null) chips.add('HOA ≤ \$${_fmt(hoaMax!)}');
    if (openHouse) chips.add('open house');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Colors.grey.shade50,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips
              .map(
                (c) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    c,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      buf.write(s[i]);
      if (idx > 1 && idx % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  static String _titleCase(String s) =>
      s.split(' ').map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1))).join(' ');
// End of _FiltersBar


}

/* ===========================
   SMALL UI HELPER: MINI PREVIEW CARD
   =========================== */

class _MiniPreviewCard extends StatelessWidget {
  const _MiniPreviewCard({required this.data, required this.onOpen});
  final Map<String, dynamic> data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final photos = _ListingCard._extractPhotoUrls(data).map(_ListingCard._maybeHiRes).toList();
    final url = photos.isEmpty ? null : photos.first;
    final price = _ListingCard._fmt(_ListingCard._num(data['price'])?.toInt() ?? 0);
    final addr = _ListingCard._composeAddress(data);

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 88,
                height: 72,
                child: url == null
                    ? Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.home_outlined),
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('\$$price', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
