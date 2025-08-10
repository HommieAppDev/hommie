// lib/compare_listings_screen.dart
import 'dart:math' show cos, asin, sqrt, pi;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ----------------- Screen -----------------

class CompareListingsScreen extends StatefulWidget {
  const CompareListingsScreen({super.key});

  @override
  State<CompareListingsScreen> createState() => _CompareListingsScreenState();
}

class _CompareListingsScreenState extends State<CompareListingsScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<String> _ids = [];
  bool _diffOnly = false; // controls "Compare" (differences emphasis)

  User? get _user => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {};
      final idsArg = (args['ids'] as List?)?.map((e) => '$e').toList() ?? <String>[];
      final leftId = args['leftId']?.toString();
      final rightId = args['rightId']?.toString();
      final extraId = args['extraId']?.toString();

      final list = <String>[
        ...idsArg,
        if (leftId != null) leftId,
        if (rightId != null) rightId,
        if (extraId != null) extraId,
      ].where((s) => s.trim().isNotEmpty).toList();

      setState(() {
        _ids = list.take(3).toList(); // support up to 3 for now
      });
    });
  }

  void _removeAt(int index) {
    setState(() => _ids.removeAt(index));
  }

  Future<void> _addListingDialog() async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add listing by ID'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter listing ID'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;
    if (mounted) setState(() {
      if (_ids.length < 3 && !_ids.contains(id)) _ids.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ids.length < 2) {
      return const Scaffold(
        body: Center(child: Text('Pick at least two properties to compare.')),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final colWidth = math.max(340.0, screenWidth / 2 - 12);

    // Registry for comparison values, persists across rebuilds.
    final Map<String, Set<String>> _rowRegistryValues = {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare'),
        actions: [
          _DifferencesToggle(
            value: _diffOnly,
            onChanged: (v) => setState(() => _diffOnly = v),
          ),
        ],
      ),
      body: _RowRegistry(
        diffOnly: _diffOnly,
        values: _rowRegistryValues,
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(overscroll: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < _ids.length; i++) ...[
                  SizedBox(
                    width: colWidth,
                    child: _CompareColumn(
                      label: String.fromCharCode(65 + i), // A, B, C
                      listingId: _ids[i],
                      onRemove: () => _removeAt(i),
                    ),
                  ),
                  if (i != _ids.length - 1) const VerticalDivider(width: 1),
                ],
                if (_ids.length < 3) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: colWidth, child: _AddPropertyCard(onAdd: _addListingDialog)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------- Column (one property) -----------------

class _CompareColumn extends StatefulWidget {
  const _CompareColumn({
    required this.label,
    required this.listingId,
    required this.onRemove,
  });

  final String label;
  final String listingId;
  final VoidCallback onRemove;

  @override
  State<_CompareColumn> createState() => _CompareColumnState();
}

class _CompareColumnState extends State<_CompareColumn> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  User? get _user => _auth.currentUser;

  Map<String, Map<String, String>> _details = {};
  List<String> _photos = const [];
  double? _score;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final doc = await _fs.collection('listings').doc(widget.listingId).get();
    final data = doc.data() ?? {};

    final details = (data['details'] as List?) ?? const [];
    final photos = (data['photos'] as List?)?.cast<String>() ?? const <String>[];

    setState(() {
      _details = _parseDetails(details);
      _photos = photos;
    });

    _score = await _computeScore(data);
    if (mounted) setState(() {});
  }

  Future<double?> _computeScore(Map<String, dynamic> base) async {
    final u = _user;
    if (u == null) return null;

    final prefs = await _fs.collection('users').doc(u.uid).get();
    final p = (prefs.data()?['priorities'] as Map?) ?? {};

    final wBeds = _toDouble(p['beds'] ?? 0.20) ?? 0.20;
    final wBaths = _toDouble(p['baths'] ?? 0.15) ?? 0.15;
    final wSqft = _toDouble(p['sqft'] ?? 0.20) ?? 0.20;
    final wPricePSF = _toDouble(p['pricePerSqft'] ?? 0.25) ?? 0.25; // negative factor
    final wYear = _toDouble(p['year'] ?? 0.10) ?? 0.10;
    final wLot = _toDouble(p['lot'] ?? 0.10) ?? 0.10;

    double norm(num? v, num max, {bool inverse = false}) {
      if (v == null) return 0;
      final n = (v / (max == 0 ? 1 : max)).clamp(0, 1).toDouble();
      return inverse ? 1 - n : n;
    }

    num? beds = _n(base['beds']) ?? _n(base['bedrooms']);
    num? baths = _n(base['baths']) ?? _n(base['bathrooms']);
    num? sqft = _n(base['sqft']) ?? _n(base['squareFeet']);
    num? price = _n(base['price']) ?? _n(base['listPrice']);
    num? lotSqft = _n(base['lot_sqft']) ?? _n(base['lotSize']);
    num? year = _n(base['yearBuilt']) ?? _n(_details['Building and Construction']?['Year Built']);

    final pricePsf = (price != null && sqft != null && sqft > 0) ? (price / sqft) : null;

    const maxBeds = 6, maxBaths = 4, maxSqft = 4500, maxLot = 87120;
    const maxYear = 2026, maxPricePSF = 1200;

    final s =
        norm(beds, maxBeds) * wBeds +
        norm(baths, maxBaths) * wBaths +
        norm(sqft, maxSqft) * wSqft +
        norm(pricePsf, maxPricePSF, inverse: true) * wPricePSF +
        norm(year, maxYear) * wYear +
        norm(lotSqft, maxLot) * wLot;

    return s;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid;
    final listingRef = _fs.collection('listings').doc(widget.listingId);

    final notesRef = (uid == null)
        ? null
        : _fs.collection('favorites').doc(uid).collection('listings').doc(widget.listingId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: listingRef.snapshots(),
      builder: (context, snap) {
        final l = snap.data?.data() ?? {};

        final addr = (l['address'] as Map?)?.cast<String, dynamic>() ?? const {};
        final line = (addr['line'] ?? addr['street'] ?? '') as String;
        final city = (addr['city'] ?? '') as String;
        final state = (addr['state'] ?? addr['stateCode'] ?? '') as String;
        final zip = (addr['postalCode'] ?? addr['zip'] ?? '') as String;

        final price = _n(l['price']) ?? _n(l['listPrice']);
        final beds = _n(l['beds']) ?? _n(l['bedrooms']);
        final baths = _n(l['baths']) ?? _n(l['bathrooms']);
        final sqft = _n(l['sqft']) ?? _n(l['squareFeet']);
        final type = _pretty((l['type'] ?? l['propertyType'])?.toString());
        final primaryPhoto = (l['primaryPhoto'] ?? l['primaryPhotoUrl'] ?? l['imageUrl'])?.toString();

        final yearBuilt = _details['Building and Construction']?['Year Built'];
        final lotAcres = _details['Land Info']?['Lot Size Acres'];
        final lotSqft = _details['Land Info']?['Lot Size Square Feet'];
        final hoaMonthly = _details['Homeowners Association']?['Calculated Total Monthly Association Fees'];
        final garageSpaces = _details['Garage and Parking']?['Garage Spaces'];
        final parkingFeatures = _details['Garage and Parking']?['Parking Features'];
        final heating = _details['Heating and Cooling']?['Heating Features'];
        final cooling = _details['Heating and Cooling']?['Cooling Features'];
        final style = _details['Building and Construction']?['Architectural Style'];
        final levels = _details['Building and Construction']?['Levels'] ??
            _details['Building and Construction']?['Levels or Stories'];
        final taxes = _details['Other Property Info']?['Annual Tax Amount'];
        final status = _details['Other Property Info']?['Source Listing Status'];

        final photos = _photos.isNotEmpty
            ? _photos
            : (primaryPhoto != null ? [primaryPhoto] : const <String>[]);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row (label, title, actions)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: const Border(bottom: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  Semantics(
                    label: 'Column ${widget.label}',
                    child: CircleAvatar(
                      radius: 12,
                      child: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line.isEmpty ? 'Address unavailable' : line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ----- Photos (swipeable) -----
                    _PhotoStrip(urls: photos, heroTag: 'cmp-${widget.listingId}'),
                    const SizedBox(height: 12),

                    // ----- Price, address, score -----
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            price == null ? 'Price unavailable' : '\$${_fmtNum(price)}',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (_score != null) _ScorePill(score: _score!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text([city, state, zip].where((s) => (s ?? '').isNotEmpty).join(', '),
                        style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 10),

                    // ----- Quick facts chips -----
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ChipIcon(Icons.bed_outlined, '${_intOrDash(beds)} bd'),
                        _ChipIcon(Icons.bathtub_outlined, '${_intOrDash(baths)} ba'),
                        if (sqft != null) _ChipIcon(Icons.square_foot, '${_fmtNum(sqft)} sqft'),
                        if (type.isNotEmpty) _ChipIcon(Icons.home_work_outlined, type),
                        if (yearBuilt != null) _ChipIcon(Icons.calendar_today, 'Built $yearBuilt'),
                        if (lotAcres != null) _ChipIcon(Icons.terrain, '$lotAcres ac'),
                        if (lotAcres == null && lotSqft != null) _ChipIcon(Icons.terrain, '$lotSqft sqft lot'),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1),

                    // ----- Comparison matrix -----
                    const SizedBox(height: 12),
                    _SectionTitle('Key Details'),
                    _FactsTable(rows: [
                      _kv('Status', status),
                      _kv('Type', type),
                      _kv('Style', style),
                      _kv('Stories/Levels', levels),
                      _kv('Year Built', yearBuilt),
                      _kv('Beds', _intOrDash(beds)),
                      _kv('Baths (total)', _intOrDash(baths)),
                      _kv('\$/Sqft', (price != null && sqft != null && sqft > 0) ? _fmtNum(price / sqft) : null),
                      _kv('Square Feet', sqft != null ? _fmtNum(sqft) : null),
                      _kv('Lot Acres', lotAcres),
                      _kv('Lot Sqft', lotSqft),
                      _kv('Garage Spaces', garageSpaces),
                      _kv('Parking', parkingFeatures),
                      _kv('Heating', heating),
                      _kv('Cooling', cooling),
                      _kv('Taxes (yr)', taxes),
                      _kv('HOA (mo)', hoaMonthly),
                    ]),

                    const SizedBox(height: 12),
                    const Divider(height: 1),

                    // ----- Distances to saved places -----
                    const SizedBox(height: 12),
                    _SectionTitle('Distances to your saved places'),
                    _SavedPlacesDistances(
                      listingLat: _toDouble(l['lat']) ??
                          _toDouble(l['latitude']) ??
                          _toDouble((l['coordinates'] as Map?)?['latitude']) ??
                          _toDouble((addr['coordinate'] as Map?)?['lat']),
                      listingLng: _toDouble(l['lon']) ??
                          _toDouble(l['lng']) ??
                          _toDouble(l['longitude']) ??
                          _toDouble((l['coordinates'] as Map?)?['longitude']) ??
                          _toDouble((addr['coordinate'] as Map?)?['lon']),
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),

                    // ----- Notes (read-only with edit) -----
                    const SizedBox(height: 12),
                    if (notesRef != null) _NotesBlock(listingId: widget.listingId, notesRef: notesRef),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ----------------- Notes (read-only + edit sheet + @mentions) -----------------

class _NotesBlock extends StatelessWidget {
  const _NotesBlock({required this.listingId, required this.notesRef});

  final String listingId;
  final DocumentReference<Map<String, dynamic>> notesRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: notesRef.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() ?? {};
        final text = (data['note'] ?? data['notes'] ?? '').toString();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _SectionTitle('Your Notes'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openEditSheet(context, text),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ],
            ),
            if (text.trim().isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: _cardDecoration(context),
                child: const Text('No notes yet. Tap Edit to add thoughts.'),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: _cardDecoration(context),
                child: _MentionsText(text: text),
              ),
          ],
        );
      },
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      );

  Future<void> _openEditSheet(BuildContext context, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Edit Notes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    hintText: 'Jot down pros/cons, vibes, issues noticed… Use @<uid> to mention someone.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: const StadiumBorder()),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved == true) {
      await notesRef.set({
        'note': ctrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notes saved')));
      }
    }
  }
}

class _MentionsText extends StatelessWidget {
  const _MentionsText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'@([A-Za-z0-9_\-]{6,})');
    int idx = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, m.start)));
      }
      final uid = m.group(1)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: _MentionChip(uid: uid),
        ),
      ));
      idx = m.end;
    }
    if (idx < text.length) spans.add(TextSpan(text: text.substring(idx)));
    return SelectableText.rich(TextSpan(style: const TextStyle(height: 1.4), children: spans));
  }
}

class _MentionChip extends StatelessWidget {
  const _MentionChip({required this.uid});
  final String uid;

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

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (uid == me) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (_, snap) {
        final name = (snap.data?.data()?['displayName'] ?? uid).toString();
        return InkWell(
          onTap: () => _openDM(context, uid),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text('@$name', style: const TextStyle(fontSize: 12, color: Colors.blue)),
          ),
        );
      },
    );
  }
}

// ----------------- Distances to saved places -----------------

class _SavedPlacesDistances extends StatelessWidget {
  const _SavedPlacesDistances({required this.listingLat, required this.listingLng});

  final double? listingLat;
  final double? listingLng;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Text('Sign in to see distances to your saved places.');
    }
    if (listingLat == null || listingLng == null) {
      return const Text('No location for this property.');
    }

    final q = FirebaseFirestore.instance.collection('users').doc(uid).collection('places');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (_, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Text(
            'Add saved places in your profile to see commute distance (e.g., work, school).',
            style: TextStyle(color: Colors.grey.shade700),
          );
        }

        final items = docs.map((d) {
          final m = d.data();
          final name = (m['name'] ?? 'Place').toString();
          final lat = _toDouble(m['lat']);
          final lng = _toDouble(m['lng']);
          final double? miles = (lat == null || lng == null)
              ? null
              : _haversineMiles(listingLat!, listingLng!, lat, lng);
          return MapEntry(name, miles);
        }).toList()
          ..sort((a, b) => (a.value ?? 1e9).compareTo(b.value ?? 1e9));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.take(5).map((e) {
            final dist = e.value == null ? '—' : '${e.value!.toStringAsFixed(1)} mi';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.key)),
                  Text(dist, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ----------------- UI bits -----------------

class _AddPropertyCard extends StatelessWidget {
  const _AddPropertyCard({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add property'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16));
  }
}

class _ChipIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipIcon(this.icon, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
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
}

class _FactsTable extends StatelessWidget {
  const _FactsTable({required this.rows});
  final List<MapEntry<String, String?>> rows;

  @override
  Widget build(BuildContext context) {
    final reg = _RowRegistry.of(context);
    final diffOnly = reg?.diffOnly ?? false;

    final visible = rows.where((r) => r.value != null && r.value!.trim().isNotEmpty).toList();
    if (visible.isEmpty) {
      return Text('No details available.', style: TextStyle(color: Colors.grey.shade700));
    }

    return Column(
      children: visible.map((kv) {
        final showedDiff = reg?.register(kv.key, kv.value!) ?? false;
        final isDiff = reg?.isDifferent(kv.key) == true;
        final dim = diffOnly && !isDiff;
        return Opacity(
          opacity: dim ? 0.45 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(kv.key, style: const TextStyle(color: Colors.black54))),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    kv.value!,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: isDiff ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});
  final double score;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Match score based on your priorities',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border.all(color: Colors.green.shade200),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('${(score * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _PhotoStrip extends StatefulWidget {
  const _PhotoStrip({required this.urls, required this.heroTag});
  final List<String> urls;
  final String heroTag;

  @override
  State<_PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<_PhotoStrip> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls.map(_hiResUrl).toList();
    if (urls.isEmpty) {
      return Container(
        height: 170,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      );
    }

    return Column(
      children: [
        Hero(
          tag: widget.heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: GestureDetector(
                onTap: () => _openGallery(context, urls, widget.heroTag, _idx),
                child: PageView.builder(
                  itemCount: urls.length,
                  onPageChanged: (i) => setState(() => _idx = i),
                  itemBuilder: (_, i) => Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Dots(count: urls.length, index: _idx),
      ],
    );
  }
}

// ----------------- Differences toggle infra -----------------

class _DifferencesToggle extends StatelessWidget {
  const _DifferencesToggle({required this.value, required this.onChanged, super.key});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Compare'),
        Switch(
          value: value,
          onChanged: onChanged,
          thumbIcon: MaterialStateProperty.resolveWith<Icon?>(
            (s) => Icon(value ? Icons.filter_alt : Icons.filter_alt_off, size: 14),
          ),
        ),
      ],
    );
  }
}

class _RowRegistry extends InheritedWidget {
  const _RowRegistry({
    required super.child,
    required this.diffOnly,
    required this.values,
    super.key,
  });

  final bool diffOnly;
  final Map<String, Set<String>> values;

  static _RowRegistry? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowRegistry>();

  bool register(String label, String value) {
    (values[label] ??= <String>{}).add(value.trim());
    return values[label]!.length > 1;
    // note: first column may not know final state until siblings also register.
  }

  bool isDifferent(String label) => (values[label] ?? {}).length > 1;

  @override
  bool updateShouldNotify(covariant _RowRegistry oldWidget) =>
      oldWidget.diffOnly != diffOnly || oldWidget.values != values;
}

// ----------------- Small helpers -----------------

MapEntry<String, String?> _kv(String k, dynamic v) =>
    MapEntry(k, v?.toString().trim().isEmpty == true ? null : v?.toString());

String _pretty(String? s) {
  if (s == null || s.trim().isEmpty) return '';
  final t = s.replaceAll('_', ' ');
  return t.split(' ').map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1))).join(' ');
}

num? _n(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse('$v');
}

double? _toDouble(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v');

String _fmtNum(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idx = s.length - i;
    b.write(s[i]);
    if (idx > 1 && idx % 3 == 1) b.write(',');
  }
  return b.toString();
}

String _intOrDash(num? n) => (n == null) ? '-' : (n % 1 == 0 ? n.toInt().toString() : n.toString());

Map<String, Map<String, String>> _parseDetails(List details) {
  final out = <String, Map<String, String>>{};
  for (final sec in details) {
    final cat = (sec is Map ? sec['category'] : null)?.toString().trim() ?? '';
    final list = (sec is Map ? sec['text'] : null);
    if (cat.isEmpty || list is! List) continue;
    for (final line in list) {
      if (line is! String) continue;
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      (out[cat] ??= {})[k] = v;
    }
  }
  return out;
}

double _haversineMiles(double lat1, double lon1, double lat2, double lon2) {
  double d2r(double d) => d * (pi / 180.0);
  final p = 0.5 - cos(d2r(lat2 - lat1)) / 2 +
      cos(d2r(lat1)) * cos(d2r(lat2)) *
          (1 - cos(d2r(lon2 - lon1))) / 2;
  return 3958.8 * 2 * asin(sqrt(p));
}

String _hiResUrl(String url) {
  var u = url.trim();
  if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');
  u = u.replaceAll(RegExp(r'-m\d+s\.jpg$'), '.jpg');
  return u;
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;
  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
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
    );
  }
}

// Fullscreen gallery
void _openGallery(BuildContext context, List<String> urls, String hero, int initial) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, __, ___) => _FullGallery(heroTag: hero, urls: urls, initial: initial),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _FullGallery extends StatefulWidget {
  const _FullGallery({required this.heroTag, required this.urls, required this.initial});
  final String heroTag;
  final List<String> urls;
  final int initial;
  @override
  State<_FullGallery> createState() => _FullGalleryState();
}

class _FullGalleryState extends State<_FullGallery> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  int _i = 0;
  @override
  void initState() { super.initState(); _i = widget.initial; }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text('${_i + 1}/${widget.urls.length}'),
      ),
      body: Hero(
        tag: widget.heroTag,
        child: PageView.builder(
          controller: _pc,
          onPageChanged: (i) => setState(() => _i = i),
          itemCount: widget.urls.length,
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1, maxScale: 4,
            child: Center(
              child: Image.network(
                widget.urls[i],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
