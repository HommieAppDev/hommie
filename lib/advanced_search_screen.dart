// advanced_search_screen.dart
import 'package:flutter/material.dart';

class AdvancedSearchScreen extends StatefulWidget {
  final Map<String, dynamic>? existingFilters;
  const AdvancedSearchScreen({super.key, this.existingFilters});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  int? selectedBeds;
  int? selectedBaths;
  bool hasGarage = false;
  bool hasPool = false;
  bool petsAllowed = false;
  bool waterfront = false;
  bool hasViews = false;
  bool hasBasement = false;

  double ageOfHome = 0;
  double squareFootage = 1000;
  double lotSize = 0.25;

  final List<int> options = List.generate(10, (i) => i + 1)..add(11);

  @override
  void initState() {
    super.initState();
    final filters = widget.existingFilters;
    if (filters != null) {
      selectedBeds = filters['beds'];
      selectedBaths = filters['baths'];
      hasGarage = filters['garage'] ?? false;
      hasPool = filters['pool'] ?? false;
      petsAllowed = filters['pets'] ?? false;
      waterfront = filters['waterfront'] ?? false;
      hasViews = filters['views'] ?? false;
      hasBasement = filters['basement'] ?? false;
      ageOfHome = (filters['age'] ?? 0).toDouble();
      squareFootage = (filters['squareFootage'] ?? 1000).toDouble();
      lotSize = (filters['lotSize'] ?? 0.25).toDouble();
    }
  }

  void _applyFilters() {
    Navigator.pop(context, {
      'beds': selectedBeds,
      'baths': selectedBaths,
      'garage': hasGarage,
      'pool': hasPool,
      'pets': petsAllowed,
      'waterfront': waterfront,
      'views': hasViews,
      'basement': hasBasement,
      'age': ageOfHome.round(),
      'squareFootage': squareFootage.round(),
      'lotSize': lotSize
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Search')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bedrooms'),
            DropdownButton<int>(
              value: selectedBeds,
              hint: const Text('Select'),
              onChanged: (val) => setState(() => selectedBeds = val),
              items: options.map((val) => DropdownMenuItem(
                value: val,
                child: Text(val == 11 ? '10+' : '$val'),
              )).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Bathrooms'),
            DropdownButton<int>(
              value: selectedBaths,
              hint: const Text('Select'),
              onChanged: (val) => setState(() => selectedBaths = val),
              items: options.map((val) => DropdownMenuItem(
                value: val,
                child: Text(val == 11 ? '10+' : '$val'),
              )).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Garage'),
            Switch(value: hasGarage, onChanged: (val) => setState(() => hasGarage = val)),
            const Text('Pool'),
            Switch(value: hasPool, onChanged: (val) => setState(() => hasPool = val)),
            const Text('Pets Allowed'),
            Switch(value: petsAllowed, onChanged: (val) => setState(() => petsAllowed = val)),
            const Text('Waterfront'),
            Switch(value: waterfront, onChanged: (val) => setState(() => waterfront = val)),
            const Text('Views'),
            Switch(value: hasViews, onChanged: (val) => setState(() => hasViews = val)),
            const Text('Basement'),
            Switch(value: hasBasement, onChanged: (val) => setState(() => hasBasement = val)),
            const SizedBox(height: 16),
            const Text('Age of Home'),
            Slider(
              value: ageOfHome,
              min: 0,
              max: 100,
              divisions: 20,
              label: ageOfHome == 100 ? '100+ yrs' : '${ageOfHome.round()} yrs',
              onChanged: (val) => setState(() => ageOfHome = val),
            ),
            const Text('Square Footage'),
            Slider(
              value: squareFootage,
              min: 500,
              max: 10000,
              divisions: 19,
              label: squareFootage == 10000 ? '10,000+' : '${squareFootage.round()} sq ft',
              onChanged: (val) => setState(() => squareFootage = val),
            ),
            const Text('Lot Size (acres)'),
            Slider(
              value: lotSize,
              min: 0.1,
              max: 10,
              divisions: 20,
              label: lotSize == 10 ? '10+ acres' : '${lotSize.toStringAsFixed(1)} acres',
              onChanged: (val) => setState(() => lotSize = val),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _applyFilters,
              child: const Text('Apply Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
