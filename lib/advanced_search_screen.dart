// lib/advanced_search_screen.dart
import 'package:flutter/material.dart';

class AdvancedSearchScreen extends StatefulWidget {
  /// You can pass filters either by constructor **or** via
  /// Navigator.pushNamed(context, '/advanced-search', arguments: <map>).
  final Map<String, dynamic>? existingFilters;
  const AdvancedSearchScreen({super.key, this.existingFilters});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  // -------- Core filters (wire to API) --------
  int? beds;                 // exact bedrooms
  double? baths;             // can be 1.5, 2.5, etc.
  final minPriceCtrl = TextEditingController();
  final maxPriceCtrl = TextEditingController();
  int minSqft = 1000;
  bool hasGarage = false;
  String? propertyType;      // "Single Family", "Condo", ...

  // -------- Optional extras (saved/returned; can be wired later) --------
  bool hasPool = false;
  bool petsAllowed = false;
  bool waterfront = false;
  bool hasViews = false;
  bool hasBasement = false;
  int maxAge = 100;          // upper bound
  double lotSizeAcres = 0.25;

  // UI options (keep types strictly nullable where needed)
  final List<int?> bedOptions = const [null, 1, 2, 3, 4, 5, 6];
  final List<double?> bathOptions = const [null, 1, 1.5, 2, 2.5, 3, 3.5, 4];

  final List<String> propertyTypes = const [
    'Single Family',
    'Condo',
    'Townhouse',
    'Multi-Family',
    'Manufactured',
    'Land',
  ];

  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    // If constructed with filters, hydrate immediately
    if (widget.existingFilters != null) {
      _applyIncoming(widget.existingFilters!);
      _hydrated = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If launched via pushNamed with arguments, hydrate once here
    if (_hydrated) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _applyIncoming(args);
      _hydrated = true;
      setState(() {}); // reflect incoming values
    }
  }

  void _applyIncoming(Map<String, dynamic> f) {
    beds = f['beds'] as int?;
    final b = f['baths'];
    baths = (b is int) ? b.toDouble() : (b as num?)?.toDouble();

    minPriceCtrl.text = (f['minPrice'] ?? f['priceMin'] ?? '').toString();
    maxPriceCtrl.text = (f['maxPrice'] ?? f['priceMax'] ?? '').toString();

    minSqft = (f['minSqft'] as int?) ??
        (f['squareFootage'] as int?) ??
        1000;

    hasGarage = (f['hasGarage'] as bool?) ??
        (f['garage'] as bool?) ??
        false;

    propertyType = f['propertyType'] as String?;

    // extras
    hasPool = (f['pool'] as bool?) ?? false;
    petsAllowed = (f['pets'] as bool?) ?? false;
    waterfront = (f['waterfront'] as bool?) ?? false;
    hasViews = (f['views'] as bool?) ?? false;
    hasBasement = (f['basement'] as bool?) ?? false;
    maxAge = (f['maxAge'] as int?) ?? (f['age'] as int?) ?? 100;
    lotSizeAcres = (f['lotSize'] as num?)?.toDouble() ?? 0.25;
  }

  @override
  void dispose() {
    minPriceCtrl.dispose();
    maxPriceCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(String s) {
    final v = int.tryParse(s.replaceAll(',', '').trim());
    return (v == null || v <= 0) ? null : v;
  }

  void _apply() {
    Navigator.pop(context, {
      // API-ready
      'beds': beds,
      'baths': baths,
      'minPrice': _parseInt(minPriceCtrl.text),
      'maxPrice': _parseInt(maxPriceCtrl.text),
      'minSqft': minSqft,
      'hasGarage': hasGarage,
      'propertyType': propertyType,

      // extras (persist for future use)
      'pool': hasPool,
      'pets': petsAllowed,
      'waterfront': waterfront,
      'views': hasViews,
      'basement': hasBasement,
      'maxAge': maxAge,
      'lotSize': lotSizeAcres,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Search')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Bedrooms & Bathrooms'),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: beds,
                  decoration: const InputDecoration(labelText: 'Bedrooms'),
                  items: bedOptions.map((v) {
                    return DropdownMenuItem<int?>(
                      value: v,
                      child: Text(v == null ? 'Any' : '$v+'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => beds = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<double?>(
                  value: baths,
                  decoration: const InputDecoration(labelText: 'Bathrooms'),
                  items: bathOptions.map((v) {
                    final label = (v == null)
                        ? 'Any'
                        : (v % 1 == 0 ? '${v.toInt()}+' : '${v}+');
                    return DropdownMenuItem<double?>(
                      value: v,
                      child: Text(label),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => baths = v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Price'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: minPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min Price'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: maxPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max Price'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Property'),
          DropdownButtonFormField<String?>(
            value: propertyType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: <String?>[null, ...propertyTypes].map((t) {
              return DropdownMenuItem<String?>(
                value: t,
                child: Text(t ?? 'Any'),
              );
            }).toList(),
            onChanged: (v) => setState(() => propertyType = v),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: hasGarage,
            onChanged: (v) => setState(() => hasGarage = v),
            title: const Text('Has Garage'),
          ),

          const SizedBox(height: 8),
          const _SectionTitle('Minimum Square Footage'),
          Slider(
            value: minSqft.toDouble(),
            min: 500,
            max: 10000,
            divisions: 19,
            label: minSqft >= 10000 ? '10,000+' : '$minSqft sq ft',
            onChanged: (v) => setState(() => minSqft = v.round()),
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Optional Amenities'),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('Pool'),
                selected: hasPool,
                onSelected: (v) => setState(() => hasPool = v),
              ),
              FilterChip(
                label: const Text('Pets Allowed'),
                selected: petsAllowed,
                onSelected: (v) => setState(() => petsAllowed = v),
              ),
              FilterChip(
                label: const Text('Waterfront'),
                selected: waterfront,
                onSelected: (v) => setState(() => waterfront = v),
              ),
              FilterChip(
                label: const Text('Views'),
                selected: hasViews,
                onSelected: (v) => setState(() => hasViews = v),
              ),
              FilterChip(
                label: const Text('Basement'),
                selected: hasBasement,
                onSelected: (v) => setState(() => hasBasement = v),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Age & Lot (optional)'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Max Age: ${maxAge == 100 ? '100+' : '$maxAge'} yrs'),
            subtitle: Slider(
              value: maxAge.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => maxAge = v.round()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Lot Size: ${lotSizeAcres == 10 ? '10+' : lotSizeAcres.toStringAsFixed(1)} acres',
            ),
            subtitle: Slider(
              value: lotSizeAcres,
              min: 0.1,
              max: 10,
              divisions: 20,
              onChanged: (v) =>
                  setState(() => lotSizeAcres = double.parse(v.toStringAsFixed(1))),
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
