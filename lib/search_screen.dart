// lib/search_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // --- Location & basics ---
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();

  int? _beds;          // min
  double? _baths;      // min
  double _radius = 10; // miles

  // Advanced filters (round-tripped from /advanced-search)
  Map<String, dynamic> _filters = {};

  // ---------- Helpers ----------
  int? _parseInt(String s) {
    final v = int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '').trim());
    return (v == null || v <= 0) ? null : v;
  }

  int _activeFilterCount() {
    final f = {
      'beds': _beds,
      'baths': _baths,
      'minPrice': _parseInt(_minPriceCtrl.text),
      'maxPrice': _parseInt(_maxPriceCtrl.text),
      // advanced:
      ..._filters,
    };
    int n = 0;
    for (final e in f.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is bool && v == false) continue;
      n++;
    }
    return n;
  }

  // ---------- Navigation ----------
  Future<void> _openAdvanced() async {
    final res = await Navigator.pushNamed(
      context,
      '/advanced-search',
      arguments: _filters,
    );
    if (!mounted) return;
    if (res is Map<String, dynamic>) {
      setState(() {
        _filters = res;
        // If user set beds/baths/min/max in Advanced, reflect here too
        _beds  = res['beds'] as int? ?? _beds;
        _baths = (res['baths'] as num?)?.toDouble() ?? _baths;
        final minP = res['minPrice'] as int?;
        final maxP = res['maxPrice'] as int?;
        if (minP != null) _minPriceCtrl.text = minP.toString();
        if (maxP != null) _maxPriceCtrl.text = maxP.toString();
      });
    }
  }

  void _runSearch() {
    Navigator.pushNamed(
      context,
      '/results', // keep consistent with your SearchResultsScreen
      arguments: {
        'city'  : _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'state' : _stateCtrl.text.trim().isEmpty
            ? null
            : _stateCtrl.text.trim().toUpperCase(),
        'zip'   : _zipCtrl.text.trim().isEmpty ? null : _zipCtrl.text.trim(),
        'radiusMiles': _radius,
        'beds'  : _beds,
        'baths' : _baths,
        'minPrice': _parseInt(_minPriceCtrl.text),
        'maxPrice': _parseInt(_maxPriceCtrl.text),
        // everything from Advanced (propertyType, garage, pool, etc.)
        ..._filters,
      },
    );
  }

  // ---------- Lifecycle ----------
  @override
  void dispose() {
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = _activeFilterCount();

    return Scaffold(
      appBar: AppBar(title: const Text('Search Listings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Location',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'City',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _stateCtrl,
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]'))],
                        decoration: const InputDecoration(
                          labelText: 'State',
                          counterText: '',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _zipCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'ZIP (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                _LabeledRow(
                  label: 'Search Radius',
                  child: Column(
                    children: [
                      Slider(
                        value: _radius,
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '${_radius.toStringAsFixed(0)} mi',
                        onChanged: (v) => setState(() => _radius = v),
                      ),
                      Text('${_radius.toStringAsFixed(0)} miles',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _SectionCard(
            title: 'Basics',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minPriceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Min Price',
                          prefixText: '\$',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _maxPriceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Max Price',
                          prefixText: '\$',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _beds,
                        decoration: const InputDecoration(
                          labelText: 'Bedrooms',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: <int?>[null, 1, 2, 3, 4, 5, 6].map((v) {
                          return DropdownMenuItem<int?>(
                            value: v,
                            child: Text(v == null ? 'Any' : '${v}+'),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _beds = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<double?>(
                        value: _baths,
                        decoration: const InputDecoration(
                          labelText: 'Bathrooms',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: <double?>[null, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5].map((v) {
                          final label = v == null ? 'Any' : (v % 1 == 0 ? '${v.toInt()}+' : '${v}+');
                          return DropdownMenuItem<double?>(
                            value: v,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _baths = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _SectionCard(
            title: 'More Filters',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openAdvanced,
                    icon: const Icon(Icons.tune),
                    label: Text(
                      activeCount > 0 ? 'Advanced ($activeCount)' : 'Advanced',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _runSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Pretty little helpers ----------
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }
}
