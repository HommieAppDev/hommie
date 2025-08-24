import 'realtor_badge.dart';

class Listing {
  // Identifiers
  final String propertyId;
  final String? listingId;
  final String? mlsId;

  // Address & Location
  final String fullAddress;
  final String city;
  final String stateCode;
  final String postalCode;
  final String? county;
  final List<String> neighborhoods;
  final double? lat;
  final double? lon;
  final String? streetViewUrl;

  // Price & Value
  final double? listPrice;
  final double? listPriceMin;
  final double? listPriceMax;
  final double? estimate;          // AVM/Zestimate-like value
  final double? lastSoldPrice;
  final DateTime? lastSoldDate;
  final List<Map<String, dynamic>> priceHistory;

  // Home Facts
  final int? beds;
  final double? baths;             // allow 3.5 baths
  final int? sqft;
  final int? lotSqft;
  final int? yearBuilt;
  final String? propertyType;      // condo, sfh, land, etc.
  final int? stories;
  final String? buildingName;

  // Financials
  final double? hoaFee;
  final double? annualTax;
  final bool? rentControl;

  // Status & Flags
  final String? status;            // for_sale, pending, etc.
  final bool isNewListing;
  final bool isPriceReduced;
  final bool isForeclosure;
  final bool isPending;
  final bool isContingent;

  // Media
  final String? primaryPhoto;
  final List<String> photos;
  final List<String> virtualTours;
  final bool matterport;

  // Branding / Agents
  final String? officeName;
  final String? agentName;
  final RealtorBadge? realtorBadge;
  final List<String> tiktokVideoUrls;

  // Extras
  final bool? catsAllowed;
  final bool? dogsAllowed;
  final List<Map<String, dynamic>> details; // raw extra details if you want them

  Listing({
    required this.propertyId,
    this.listingId,
    this.mlsId,
    required this.fullAddress,
    required this.city,
    required this.stateCode,
    required this.postalCode,
    this.county,
    this.neighborhoods = const [],
    this.lat,
    this.lon,
    this.streetViewUrl,
    this.listPrice,
    this.listPriceMin,
    this.listPriceMax,
    this.estimate,
    this.lastSoldPrice,
    this.lastSoldDate,
    this.priceHistory = const [],
    this.beds,
    this.baths,
    this.sqft,
    this.lotSqft,
    this.yearBuilt,
    this.propertyType,
    this.stories,
    this.buildingName,
    this.hoaFee,
    this.annualTax,
    this.rentControl,
    this.status,
    this.isNewListing = false,
    this.isPriceReduced = false,
    this.isForeclosure = false,
    this.isPending = false,
    this.isContingent = false,
    this.primaryPhoto,
    this.photos = const [],
    this.virtualTours = const [],
    this.matterport = false,
    this.officeName,
    this.agentName,
    this.realtorBadge,
    this.tiktokVideoUrls = const [],
    this.catsAllowed,
    this.dogsAllowed,
    this.details = const [],
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
  return Listing(
    propertyId: json['property_id'] ?? '',
    listingId: json['listing_id'],
    mlsId: json['mls_id'],
    fullAddress: json['address']?['line'] ?? '',
    city: json['address']?['city'] ?? '',
    stateCode: json['address']?['state_code'] ?? '',
    postalCode: json['address']?['postal_code'] ?? '',
    county: json['location']?['county']?['name'],
    neighborhoods: (json['location']?['neighborhoods'] as List? ?? [])
      .map((n) => n['name']?.toString() ?? '')
      .toList(),
    lat: (json['coordinate']?['lat'] as num?)?.toDouble(),
    lon: (json['coordinate']?['lon'] as num?)?.toDouble(),
    streetViewUrl: json['coordinate']?['street_view_url'],
    listPrice: (json['list_price'] as num?)?.toDouble(),
    listPriceMin: (json['list_price_min'] as num?)?.toDouble(),
    listPriceMax: (json['list_price_max'] as num?)?.toDouble(),
    estimate: (json['estimate']?['estimate'] as num?)?.toDouble(),
    lastSoldPrice: (json['last_sold_price'] as num?)?.toDouble(),
    lastSoldDate: json['last_sold_date'] != null
      ? DateTime.tryParse(json['last_sold_date'])
      : null,
    priceHistory: (json['price_history'] as List? ?? [])
      .map((e) => e as Map<String, dynamic>)
      .toList(),
    beds: json['beds'],
    baths: (json['baths'] as num?)?.toDouble(),
    sqft: json['sqft'],
    lotSqft: json['lot_sqft'],
    yearBuilt: int.tryParse(
      _extractDetail(json, 'Year Built') ?? ''), // from details
    propertyType: json['type'],
    stories: int.tryParse(
      _extractDetail(json, 'Levels or Stories') ?? ''),
    buildingName: _extractDetail(json, 'Building Name'),
    hoaFee: double.tryParse(
      _extractDetail(json, 'Association Fee') ?? ''),
    annualTax: double.tryParse(
      _extractDetail(json, 'Annual Tax Amount') ?? ''),
    rentControl: _extractDetail(json, 'Rent Control') == 'Yes',
    status: json['status'],
    isNewListing: json['flags']?['is_new_listing'] == true,
    isPriceReduced: json['flags']?['is_price_reduced'] == true,
    isForeclosure: json['flags']?['is_foreclosure'] == true,
    isPending: json['flags']?['is_pending'] == true,
    isContingent: json['flags']?['is_contingent'] == true,
    primaryPhoto: json['primary_photo']?['href'],
    photos: (json['photos'] as List? ?? [])
      .map((p) => p['href'].toString())
      .toList(),
    virtualTours: (json['virtual_tours'] as List? ?? [])
      .map((v) => v['href'].toString())
      .toList(),
    matterport: json['matterport'] == true,
    officeName: json['branding']?[0]?['name'],
    agentName: json['agents']?[0]?['agent_name'],
    realtorBadge: json['realtorBadge'] != null
      ? RealtorBadge.fromMap(Map<String, dynamic>.from(json['realtorBadge']))
      : null,
    tiktokVideoUrls: (json['tiktokVideoUrls'] as List?)?.cast<String>() ?? const [],
    catsAllowed: json['pet_policy']?['cats'],
    dogsAllowed: json['pet_policy']?['dogs'],
    details: (json['details'] as List? ?? [])
      .map((d) => d as Map<String, dynamic>)
      .toList(),
  );
  }

  static String? _extractDetail(Map<String, dynamic> json, String key) {
    final details = json['details'] as List? ?? [];
    for (final cat in details) {
      final texts = cat['text'] as List? ?? [];
      for (final t in texts) {
        if (t.toString().contains(key)) {
          return t.toString().split(':').last.trim();
        }
      }
    }
    return null;
  }
}
