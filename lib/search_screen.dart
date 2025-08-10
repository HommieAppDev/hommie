// lib/search_screen.dart
import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();

  int? _beds;              // nullable => “Any”
  double? _baths;          // nullable => “Any”
  int _radius = 10;        // miles
  final _radiusOptions = const [5, 10, 25, 50, 75, 100];

  // advanced filters (come back from Advanced screen)
  Map<String, dynamic>? _advanced;

  @override
  void dispose() {
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(String s) {
    final v = int.tryParse(s.replaceAll(',', '').trim());
    return (v == null || v <= 0) ? null : v;
    // returns null for blank/invalid so we don’t send bad numbers
  }

  Future<void> _openAdvanced() async {
    // NOTE: do NOT call Navigator in initState — only from button taps like this
    final result = await Navigator.pushNamed(context, '/advanced-search',
        arguments: _advanced);
    if (!mounted) return;
    if (result is Map<String, dynamic>) {
      setState(() => _advanced = result);
      // reflect beds/baths locally if user chose them in advanced
      _beds  = result['beds'] as int? ?? _beds;
      _baths = (result['baths'] as num?)?.toDouble() ?? _baths;
      // optional: mirror min/max price if user used Advanced fields
      if ((result['minPrice'] ?? result['maxPrice']) != null) {
        _minPriceCtrl.text = (result['minPrice'] ?? '').toString();
        _maxPriceCtrl.text = (result['maxPrice'] ?? '').toString();
      }
    }
  }

  void _goSearch() {
    final args = <String, dynamic>{
      'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      'state': _stateCtrl.text.trim().isEmpty
          ? null
          : _stateCtrl.text.trim().toUpperCase(),
      'zip': _zipCtrl.text.trim().isEmpty ? null : _zipCtrl.text.trim(),
      'radiusMiles': _radius.toDouble(),
      'beds': _beds,
      'baths': _baths,
      'minPrice': _parseInt(_minPriceCtrl.text),
      'maxPrice': _parseInt(_maxPriceCtrl.text),
      // pass through anything from Advanced
      ...?_advanced,
    };

    Navigator.pushNamed(context, '/search-results', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Listings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _cityCtrl,
                decoration: const InputDecoration(labelText: 'City'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _stateCtrl,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'State', counterText: ''),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _zipCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Zip (optional)'),
          ),
          const SizedBox(height: 16),

          const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minPriceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min Price'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maxPriceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max Price'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: _beds,
                items: <int?>[null, 1, 2, 3, 4, 5].map((v) {
                  return DropdownMenuItem<int?>(
                    value: v,
                    child: Text(v == null ? 'Any Beds' : '$v+ Beds'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _beds = v),
                decoration: const InputDecoration(labelText: 'Bedrooms'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<double?>(
                value: _baths,
                items: <double?>[null, 1, 1.5, 2, 2.5, 3, 4].map((v) {
                  return DropdownMenuItem<double?>(
                    value: v,
                    child: Text(v == null ? 'Any Baths' : '$v+ Baths'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _baths = v),
                decoration: const InputDecoration(labelText: 'Bathrooms'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Radius:'),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _radius,
              items: _radiusOptions
                  .map((r) =>
                      DropdownMenuItem<int>(value: r, child: Text('$r mi')))
                  .toList(),
              onChanged: (v) => setState(() => _radius = v ?? _radius),
            ),
          ]),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _goSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _openAdvanced,
                child: const Text('Advanced'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
