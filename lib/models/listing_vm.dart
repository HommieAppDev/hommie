import 'listing.dart';

class ListingVM {
  final Listing listing;
  ListingVM(this.listing);

  // ---- Address & location ----
  String get addressLine => listing.fullAddress;

  String get city => listing.city;

  // Your model uses stateCode; provide both for compatibility
  String get stateCode => listing.stateCode;
  String get state => listing.stateCode; // alias (some UI calls vm.state)

  String get postalCode => listing.postalCode; // camelCase in Dart
  String get zip => listing.postalCode; // alias so vm.zip still works

  String get cityStateZip {
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (stateCode.isNotEmpty) parts.add(stateCode);
    if (postalCode.isNotEmpty) parts.add(postalCode);
    return parts.join(', ');
  }

  // ---- Media convenience ----
  String? get primaryImageUrl =>
      listing.primaryPhoto ??
      (listing.photos.isNotEmpty ? listing.photos.first : null);

  // Some places still use vm.photos
  List<String> get photos => listing.photos;

  // ---- Basic facts (used by cards/helpers) ----
  int? get beds => listing.beds;
  double? get baths => listing.baths;
  int? get sqft => listing.sqft;

  // UI text helpers used by ListingCardItem
  String get bedroomText {
    final b = beds;
    if (b == null) return '';
    if (b <= 0) return 'Studio';
    return '$b ${b == 1 ? 'Bed' : 'Beds'}';
  }

  String get bathsText {
    final b = baths;
    if (b == null) return '';
    final isInt = (b % 1) == 0;
    final numStr = isInt
        ? b.toInt().toString()
        : b.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '$numStr ${b == 1 ? 'Bath' : 'Baths'}';
  }

  String get sqftText {
    final s = sqft;
    if (s == null || s <= 0) return '';
    return '$s sqft';
  }

  // ---- Pricing ----
  String get priceText {
    final p = listing.listPrice;
    if (p == null) return '';
    // keep simple formatting to avoid extra deps
    return '\$${p.toStringAsFixed(0)}';
  }
}
