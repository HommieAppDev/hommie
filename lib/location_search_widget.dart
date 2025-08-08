import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationSearchWidget extends StatefulWidget {
  final Function(String, double, Position?) onSearch;

  const LocationSearchWidget({super.key, required this.onSearch});

  @override
  State<LocationSearchWidget> createState() => _LocationSearchWidgetState();
}

class _LocationSearchWidgetState extends State<LocationSearchWidget> {
  final TextEditingController _locationController = TextEditingController();
  double _radius = 10; // miles
  Position? _currentPosition;
  bool _locating = false;

  Future<void> _getCurrentLocation() async {
    setState(() => _locating = true);
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      setState(() => _locating = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        setState(() => _locating = false);
        return;
      }
    }

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = position;
      _locating = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location retrieved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text("Search Location", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(
            labelText: 'Enter ZIP code or city',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.my_location),
                label: _locating ? const Text("Locating...") : const Text("Locate Me"),
                onPressed: _locating ? null : _getCurrentLocation,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text("Search radius: ${_radius.toInt()} miles"),
        Slider(
          value: _radius,
          min: 5,
          max: 100,
          divisions: 19,
          label: "${_radius.toInt()} mi",
          onChanged: (value) => setState(() => _radius = value),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.search),
          label: const Text('Search'),
          onPressed: () {
            final query = _locationController.text.trim();
            widget.onSearch(query, _radius, _currentPosition);
          },
        ),
      ],
    );
  }
}
