// lib/visited_properties_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VisitedPropertiesScreen extends StatefulWidget {
  const VisitedPropertiesScreen({super.key});

  @override
  State<VisitedPropertiesScreen> createState() => _VisitedPropertiesScreenState();
}

class _VisitedPropertiesScreenState extends State<VisitedPropertiesScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  User? get _user => _auth.currentUser;

  // Track which cards are expanded
  final Map<String, bool> _expanded = {};

  // Default checklist items for first-time buyers
  static const List<_CheckItem> _defaultChecklist = [
    _CheckItem('Exterior/roof looks sound'),
    _CheckItem('Basement/Crawlspace moisture check'),
    _CheckItem('HVAC age/condition noted'),
    _CheckItem('Water pressure / hot water works'),
    _CheckItem('Electrical (outlets/switches) look safe'),
    _CheckItem('Windows open/close; drafts?'),
    _CheckItem('Signs of pests or odor'),
    _CheckItem('Noise levels acceptable'),
    _CheckItem('Natural light good'),
    _CheckItem('Parking/driveway fits needs'),
    _CheckItem('Cell reception works'),
    _CheckItem('Internet options available'),
    _CheckItem('HOA rules/fees reviewed'),
    _CheckItem('Appliances age/condition'),
    _CheckItem('Commute time tested'),
    _CheckItem('Neighborhood vibe fits'),
  ];

  Future<void> _toggleChecklist({
    required String listingId,
    required String key,
    required bool value,
  }) async {
    final uid = _user?.uid;
    if (uid == null) return;
    final ref = _fs.collection('visited').doc(uid).collection('listings').doc(listingId);
    await ref.set({
      'checklist': {key: value},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveNotes({
    required String listingId,
    String? notes,
    String? nextSteps,
    int? rating,
  }) async {
    final uid = _user?.uid;
    if (uid == null) return;
    final ref = _fs.collection('visited').doc(uid).collection('listings').doc(listingId);
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (notes != null) data['notes'] = notes;
    if (nextSteps != null) data['nextSteps'] = nextSteps;
    if (rating != null) data['rating'] = rating;
    await ref.set(data, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _deleteVisit(String listingId) async {
    final uid = _user?.uid;
    if (uid == null) return;
    await _fs.collection('visited').doc(uid).collection('listings').doc(listingId).delete();
  }

  Future<void> _pickVisitedDate({
    required String listingId,
    required DateTime initialDate,
  }) async {
    final uid = _user?.uid;
    if (uid == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    await _fs
        .collection('visited')
        .doc(uid)
        .collection('listings')
        .doc(listingId)
        .set({'visitedAt': Timestamp.fromDate(picked), 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Visited date updated to ${_fmtDate(picked)}')),
    );
  }

  void _openDetails(Map<String, dynamic> listing) {
    Navigator.pushNamed(context, '/listing-details', arguments: {'listing': listing});
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view visited properties.')),
      );
    }

    final visitsStream = _fs
        .collection('visited')
        .doc(uid)
        .collection('listings')
        .orderBy('visitedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Visited Properties')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: visitsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(child: Text('Error loading visited properties'));
          }
          final visits = snap.data?.docs ?? [];
          if (visits.isEmpty) {
            return const Center(child: Text('No visited properties yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: visits.length,
            itemBuilder: (context, i) {
              final visitDoc = visits[i];
              final listingId = visitDoc.id;

              // Mirrored listing doc (address/price/thumb)
              final listingStream = _fs.collection('listings').doc(listingId).snapshots();
              // Private visited doc (notes/checklist/rating)
              final privateStream = _fs
                  .collection('visited')
                  .doc(uid)
                  .collection('listings')
                  .doc(listingId)
                  .snapshots();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: listingStream,
                builder: (_, lsnap) {
                  final l = lsnap.data?.data() ?? {};

                  // HIDE legacy items (anything not explicitly sourced from Realtor)
                  if (l.isEmpty || (l['source'] ?? '') != 'realtor') {
                    return const SizedBox.shrink();
                  }

                  final addr = (l['address'] as Map?)?.cast<String, dynamic>() ?? const {};
                  final line = (addr['line'] ?? addr['street'] ?? '') as String;
                  final city = (addr['city'] ?? '') as String;
                  final state = (addr['state'] ?? addr['stateCode'] ?? '') as String;
                  final zip = (addr['postalCode'] ?? addr['zip'] ?? '') as String;
                  final price = l['price'] ?? l['listPrice'];
                  final beds = l['beds'] ?? l['bedrooms'];
                  final baths = l['baths'] ?? l['bathrooms'];
                  final sqft = l['sqft'] ?? l['squareFeet'];
                  final thumb = l['primaryPhoto'] as String?;

                  final detailsPayload = <String, dynamic>{
                    'id': listingId,
                    'listPrice': price,
                    'bedrooms': beds,
                    'bathrooms': baths,
                    'squareFeet': sqft,
                    'address': {
                      'line': line,
                      'city': city,
                      'state': state,
                      'postalCode': zip,
                    },
                    if (thumb != null) 'primaryPhoto': thumb,
                    if (thumb != null) 'photos': [thumb],
                  };

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: privateStream,
                    builder: (context, psnap) {
                      final p = psnap.data?.data() ?? {};
                      final notesCtrl =
                          TextEditingController(text: (p['notes'] ?? '') as String);
                      final nextCtrl =
                          TextEditingController(text: (p['nextSteps'] ?? '') as String);
                      final rating = (p['rating'] as num?)?.toInt() ?? 0;
                      final checklist =
                          (p['checklist'] as Map?)?.cast<String, dynamic>() ?? {};
                      final visitedAtTs = visitDoc.data()['visitedAt'];
                      final visitedAt = (visitedAtTs is Timestamp)
                          ? visitedAtTs.toDate()
                          : DateTime.now();

                      // Build merged checklist with defaults
                      final mergedChecklist = <String, bool>{};
                      for (final item in _defaultChecklist) {
                        mergedChecklist[item.label] =
                            (checklist[item.label] as bool?) ?? false;
                      }

                      final isExpanded = _expanded[listingId] ?? false;

                      // --- SWIPE-TO-DELETE WRAPPER ---
                      return Dismissible(
                        key: ValueKey('visit_$listingId'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(Icons.delete, color: Colors.red.shade700),
                        ),
                        confirmDismiss: (dir) async {
                          return await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Remove visited property?'),
                                  content: const Text('This will delete your notes, checklist, and rating for this home.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                        },
                        onDismissed: (_) async {
                          await _deleteVisit(listingId);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Removed from visited')),
                          );
                        },
                        child: Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              // HEADER (tappable -> opens details)
                              InkWell(
                                borderRadius:
                                    const BorderRadius.vertical(top: Radius.circular(16)),
                                onTap: () => _openDetails(detailsPayload),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Thumbnail
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 64,
                                          height: 64,
                                          child: (thumb == null || thumb.isEmpty)
                                              ? _ph()
                                              : Image.network(
                                                  thumb,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => _ph(),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Title + subtitle
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    price == null
                                                        ? 'Price unavailable'
                                                        : '\$${_fmtNum(price)}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // TAP TO CHANGE DATE
                                                InkWell(
                                                  borderRadius: BorderRadius.circular(999),
                                                  onTap: () => _pickVisitedDate(
                                                    listingId: listingId,
                                                    initialDate: visitedAt,
                                                  ),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blueGrey.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(999),
                                                      border: Border.all(
                                                          color: Colors.blueGrey.shade200),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.event,
                                                            size: 14,
                                                            color:
                                                                Colors.blueGrey.shade700),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Visited ${_fmtDate(visitedAt)}',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .blueGrey.shade700,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                if (line.trim().isNotEmpty) line,
                                                [city, state]
                                                    .where((s) => s
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty)
                                                    .join(', '),
                                              ]
                                                  .where((s) =>
                                                      s.toString().trim().isNotEmpty)
                                                  .join(' • '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(color: Colors.black54),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 10,
                                              runSpacing: 6,
                                              children: [
                                                _MiniFact(Icons.bed_outlined,
                                                    '${beds ?? '-'} bd'),
                                                _MiniFact(Icons.bathtub_outlined,
                                                    '${baths ?? '-'} ba'),
                                                if (sqft != null)
                                                  _MiniFact(Icons.square_foot,
                                                      '${_fmtNum(sqft)} sqft'),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Actions: open + expand
                                      Column(
                                        children: [
                                          IconButton(
                                            tooltip: 'Open listing',
                                            onPressed: () =>
                                                _openDetails(detailsPayload),
                                            icon: const Icon(Icons.open_in_new),
                                          ),
                                          IconButton(
                                            tooltip:
                                                ( _expanded[listingId] ?? false )
                                                    ? 'Collapse'
                                                    : 'Expand',
                                            onPressed: () => setState(() =>
                                                _expanded[listingId] =
                                                    !(_expanded[listingId] ?? false)),
                                            icon: AnimatedRotation(
                                              duration:
                                                  const Duration(milliseconds: 200),
                                              turns: (_expanded[listingId] ?? false)
                                                  ? 0.5
                                                  : 0,
                                              child: const Icon(Icons.expand_more),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // EXPANDED CONTENT
                              AnimatedCrossFade(
                                crossFadeState: (_expanded[listingId] ?? false)
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                duration: const Duration(milliseconds: 200),
                                firstChild: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Rating row
                                      Row(
                                        children: [
                                          const Text('Your rating: ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                          for (int s = 1; s <= 5; s++)
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: Icon(
                                                Icons.star,
                                                color: s <= rating
                                                    ? Colors.amber
                                                    : Colors.grey.shade400,
                                              ),
                                              onPressed: () => _saveNotes(
                                                  listingId: listingId,
                                                  rating: s),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Checklist
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border:
                                              Border.all(color: Colors.black12),
                                        ),
                                        child: Column(
                                          children: mergedChecklist.entries
                                              .map((e) {
                                            return CheckboxListTile(
                                              dense: true,
                                              title: Text(e.key),
                                              value: e.value,
                                              onChanged: (v) => _toggleChecklist(
                                                listingId: listingId,
                                                key: e.key,
                                                value: v ?? false,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Notes
                                      TextField(
                                        controller: notesCtrl,
                                        maxLines: 4,
                                        decoration: const InputDecoration(
                                          labelText: 'Your private notes',
                                          alignLabelWithHint: true,
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Next steps
                                      TextField(
                                        controller: nextCtrl,
                                        maxLines: 2,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Next steps (e.g., schedule inspection, request HOA docs)',
                                          alignLabelWithHint: true,
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Save actions
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () => _saveNotes(
                                                listingId: listingId,
                                                notes: notesCtrl.text.trim(),
                                                nextSteps:
                                                    nextCtrl.text.trim(),
                                              ),
                                              icon: const Icon(Icons.save),
                                              label: const Text('Save Notes'),
                                              style: ElevatedButton.styleFrom(
                                                minimumSize:
                                                    const Size.fromHeight(44),
                                                shape: const StadiumBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              _saveNotes(
                                                  listingId: listingId,
                                                  notes: '',
                                                  nextSteps: '');
                                            },
                                            icon: const Icon(Icons.clear),
                                            label: const Text('Clear'),
                                            style: OutlinedButton.styleFrom(
                                                shape:
                                                    const StadiumBorder()),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                secondChild: const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // placeholder image
  Widget _ph() => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.home_outlined),
      );

  String _fmtNum(dynamic v) {
    num? n;
    if (v is num) {
      n = v;
    } else {
      n = num.tryParse('$v');
    }
    if (n == null) return '$v';
    final s = n.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      b.write(s[i]);
      if (idx > 1 && idx % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  String _fmtDate(DateTime d) {
    // m/d/yy
    final m = d.month.toString();
    final day = d.day.toString();
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$m/$day/$yy';
  }
}

// Simple value class for checklist items
class _CheckItem {
  final String label;
  const _CheckItem(this.label);
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
