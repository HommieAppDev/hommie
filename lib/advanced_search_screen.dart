import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdvancedSearchScreen extends StatefulWidget {
  final Map<String, dynamic>? existingFilters;
  const AdvancedSearchScreen({super.key, this.existingFilters});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  // ---- Core ----
  int? beds;                 // min
  double? baths;             // min (supports halves)
  final minPriceCtrl = TextEditingController();
  final maxPriceCtrl = TextEditingController();
  int minSqft = 1000;
  String? propertyTypeCode;  // API code (e.g., single_family)
  bool hasGarage = false;    // client-side fallback

  // ---- Extras (now working) ----
  bool hasPool = false;
  bool petsAllowed = false;
  bool waterfront = false;
  bool hasViews = false;
  bool hasBasement = false;

  // ---- “More” filters ----
  int? domMax;               // days on market max
  int? yearBuiltMin;         // >=
  double? lotAcresMin;       // >=
  int? hoaMax;               // monthly max
  bool hasOpenHouse = false;

  // UI helpers
  final List<int?> bedOptions = const [null, 1, 2, 3, 4, 5, 6];
  final List<double?> bathOptions = const [null, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5];
  static const Map<String, String> _typeLabelToCode = {
    'Any'            : '',
    'Single Family'  : 'single_family',
    'Condo'          : 'condo',
    'Townhouse'      : 'townhomes',
    'Multi-Family'   : 'multi_family',
    'Manufactured'   : 'manufactured',
    'Land'           : 'lots_land',
  };
  String? propertyTypeLabel;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingFilters != null) {
      _applyIncoming(widget.existingFilters!);
      _hydrated = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _applyIncoming(args);
      _hydrated = true;
      setState(() {});
    }
  }

  void _applyIncoming(Map<String, dynamic> f) {
    // core
    beds = f['beds'] as int?;
    final b = f['baths'];
    baths = (b is int) ? b.toDouble() : (b as num?)?.toDouble();
    minPriceCtrl.text = (f['minPrice'] ?? '').toString().replaceAll('null', '');
    maxPriceCtrl.text = (f['maxPrice'] ?? '').toString().replaceAll('null', '');
    minSqft = (f['minSqft'] as int?) ?? 1000;
    hasGarage = (f['hasGarage'] as bool?) ?? false;

    // property type (label or code accepted)
    final incomingType = f['propertyType'];
    if (incomingType is String && incomingType.isNotEmpty) {
      if (_typeLabelToCode.values.contains(incomingType)) {
        propertyTypeCode = incomingType;
        propertyTypeLabel = _typeLabelToCode.entries
            .firstWhere((e) => e.value == incomingType,
                orElse: () => const MapEntry('Any', ''))
            .key;
      } else {
        propertyTypeLabel = incomingType;
        propertyTypeCode = _typeLabelToCode[incomingType] ?? '';
      }
    }

    // extras
    hasPool      = (f['pool'] as bool?) ?? false;
    petsAllowed  = (f['pets'] as bool?) ?? false;
    waterfront   = (f['waterfront'] as bool?) ?? false;
    hasViews     = (f['views'] as bool?) ?? false;
    hasBasement  = (f['basement'] as bool?) ?? false;

    // more
    domMax        = f['domMax'] as int?;
    yearBuiltMin  = f['yearBuiltMin'] as int?;
    lotAcresMin   = (f['lotAcresMin'] as num?)?.toDouble();
    hoaMax        = f['hoaMax'] as int?;
    hasOpenHouse  = (f['hasOpenHouse'] as bool?) ?? false;
  }

  @override
  void dispose() {
    minPriceCtrl.dispose();
    maxPriceCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(String s) {
    final v = int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '').trim());
    return (v == null || v <= 0) ? null : v;
  }

  double? _parseDouble(String s) {
    final v = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '').trim());
    return (v == null || v <= 0) ? null : v;
  }

  void _reset() {
    setState(() {
      beds = null;
      baths = null;
      minPriceCtrl.clear();
      maxPriceCtrl.clear();
      minSqft = 1000;
      hasGarage = false;
      propertyTypeLabel = null;
      propertyTypeCode = '';

      hasPool = petsAllowed = waterfront = hasViews = hasBasement = false;
      domMax = yearBuiltMin = hoaMax = null;
      lotAcresMin = null;
      hasOpenHouse = false;
    });
  }

  void _apply() {
    Navigator.pop(context, {
      // server params (if supported) or client-side fallbacks in Results screen
      'beds'          : beds,          // -> beds_min
      'baths'         : baths,         // -> baths_min
      'minPrice'      : _parseInt(minPriceCtrl.text), // client-side if server doesn’t support
      'maxPrice'      : _parseInt(maxPriceCtrl.text),
      'minSqft'       : minSqft,       // client-side
      'propertyType'  : (propertyTypeCode ?? '').isEmpty ? null : propertyTypeCode,
      'hasGarage'     : hasGarage,     // client-side

      // extras (now applied client-side in Results)
      'pool'          : hasPool,
      'pets'          : petsAllowed,
      'waterfront'    : waterfront,
      'views'         : hasViews,
      'basement'      : hasBasement,

      // more (client-side; some providers may support server params)
      'domMax'        : domMax,
      'yearBuiltMin'  : yearBuiltMin,
      'lotAcresMin'   : lotAcresMin,
      'hoaMax'        : hoaMax,
      'hasOpenHouse'  : hasOpenHouse,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('Reset', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(title: 'Bedrooms & Bathrooms', child: Column(
            children: [
              _Row(label: 'Bedrooms', child: Wrap(
                spacing: 8,
                children: bedOptions.map((v) => ChoiceChip(
                  label: Text(v == null ? 'Any' : '${v}+'),
                  selected: (v == null && beds == null) || beds == v,
                  onSelected: (_) => setState(() => beds = v),
                )).toList(),
              )),
              const SizedBox(height: 12),
              _Row(label: 'Bathrooms', child: Wrap(
                spacing: 8,
                children: bathOptions.map((v) {
                  final label = (v == null) ? 'Any' : (v % 1 == 0 ? '${v!.toInt()}+' : '${v}+');
                  return ChoiceChip(
                    label: Text(label),
                    selected: (v == null && baths == null) || baths == v,
                    onSelected: (_) => setState(() => baths = v),
                  );
                }).toList(),
              )),
            ],
          )),

          const SizedBox(height: 12),
          _Card(title: 'Price', child: Row(
            children: [
              Expanded(child: TextField(
                controller: minPriceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Min', prefixText: '\$', border: OutlineInputBorder(), isDense: true),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: maxPriceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Max', prefixText: '\$', border: OutlineInputBorder(), isDense: true),
              )),
            ],
          )),

          const SizedBox(height: 12),
          _Card(title: 'Property', child: Column(
            children: [
              _Row(label: 'Type', child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _typeLabelToCode.keys.map((label) {
                  if (label == 'Any') {
                    return ChoiceChip(
                      label: const Text('Any'),
                      selected: propertyTypeLabel == null || propertyTypeLabel == 'Any',
                      onSelected: (_) => setState(() { propertyTypeLabel = null; propertyTypeCode = ''; }),
                    );
                  }
                  final selected = propertyTypeLabel == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      propertyTypeLabel = label;
                      propertyTypeCode = _typeLabelToCode[label];
                    }),
                  );
                }).toList(),
              )),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: hasGarage,
                onChanged: (v) => setState(() => hasGarage = v),
                title: const Text('Has Garage'),
              ),
              const SizedBox(height: 12),
              _Row(label: 'Min Sq Ft', child: Slider(
                value: minSqft.toDouble(), min: 500, max: 10000, divisions: 19,
                label: minSqft >= 10000 ? '10,000+' : '$minSqft',
                onChanged: (v) => setState(() => minSqft = v.round()),
              )),
            ],
          )),

          const SizedBox(height: 12),
          _Card(title: 'Amenities', child: Wrap(
            spacing: 12, runSpacing: 6,
            children: [
              FilterChip(label: const Text('Pool'),        selected: hasPool,       onSelected: (v) => setState(() => hasPool = v)),
              FilterChip(label: const Text('Pets Allowed'),selected: petsAllowed,   onSelected: (v) => setState(() => petsAllowed = v)),
              FilterChip(label: const Text('Waterfront'),  selected: waterfront,    onSelected: (v) => setState(() => waterfront = v)),
              FilterChip(label: const Text('Views'),       selected: hasViews,      onSelected: (v) => setState(() => hasViews = v)),
              FilterChip(label: const Text('Basement'),    selected: hasBasement,   onSelected: (v) => setState(() => hasBasement = v)),
              FilterChip(label: const Text('Open House'),  selected: hasOpenHouse,  onSelected: (v) => setState(() => hasOpenHouse = v)),
            ],
          )),

          const SizedBox(height: 12),
          _Card(title: 'More', child: Column(
            children: [
              _Row(label: 'Max DOM', child: _IntBox(
                value: domMax, hint: 'e.g. 14', onChanged: (v) => setState(() => domMax = v),
              )),
              const SizedBox(height: 8),
              _Row(label: 'Min Year Built', child: _IntBox(
                value: yearBuiltMin, hint: 'e.g. 1990', onChanged: (v) => setState(() => yearBuiltMin = v),
              )),
              const SizedBox(height: 8),
              _Row(label: 'Min Lot (acres)', child: _DoubleBox(
                value: lotAcresMin, hint: 'e.g. 0.25', onChanged: (v) => setState(() => lotAcresMin = v),
              )),
              const SizedBox(height: 8),
              _Row(label: 'Max HOA (\$/mo)', child: _IntBox(
                value: hoaMax, hint: 'e.g. 300', onChanged: (v) => setState(() => hoaMax = v),
              )),
            ],
          )),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _reset, icon: const Icon(Icons.refresh), label: const Text('Reset'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(
                onPressed: _apply, icon: const Icon(Icons.check), label: const Text('Apply'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- UI bits ----------
class _Card extends StatelessWidget {
  final String title; final Widget child;
  const _Card({required this.title, required this.child});
  @override Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12), child,
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label; final Widget child;
  const _Row({required this.label, required this.child});
  @override Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      const SizedBox(width: 12), Expanded(child: child)
    ]);
  }
}

class _IntBox extends StatelessWidget {
  final int? value; final String hint; final ValueChanged<int?> onChanged;
  const _IntBox({required this.value, required this.hint, required this.onChanged});
  @override Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: value?.toString() ?? '');
    return TextField(
      controller: ctrl, keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder(), isDense: true),
      onChanged: (s) => onChanged(int.tryParse(s)),
    );
  }
}

class _DoubleBox extends StatelessWidget {
  final double? value; final String hint; final ValueChanged<double?> onChanged;
  const _DoubleBox({required this.value, required this.hint, required this.onChanged});
  @override Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: value?.toString() ?? '');
    return TextField(
      controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder(), isDense: true),
      onChanged: (s) => onChanged(double.tryParse(s)),
    );
  }
}
