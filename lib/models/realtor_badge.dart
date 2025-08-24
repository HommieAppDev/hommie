class RealtorBadge {
  final bool isVerified;
  final String? tiktokHandle;
  final String? tiktokProfileUrl;

  const RealtorBadge({
    required this.isVerified,
    this.tiktokHandle,
    this.tiktokProfileUrl,
  });

  factory RealtorBadge.fromMap(Map<String, dynamic> m) => RealtorBadge(
    isVerified: m['isVerified'] == true,
    tiktokHandle: m['tiktokHandle'],
    tiktokProfileUrl: m['tiktokProfileUrl'],
  );

  Map<String, dynamic> toMap() => {
    'isVerified': isVerified,
    'tiktokHandle': tiktokHandle,
    'tiktokProfileUrl': tiktokProfileUrl,
  };
}
