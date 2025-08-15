import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ---- Price formatting that fixes "24448K" etc.
String formatListingPrice(dynamic price, {String? fallback}) {
  if (price == null) return fallback ?? '';
  num? n;
  if (price is num) {
    n = price;
  } else if (price is String) {
    final cleaned = price.replaceAll(RegExp(r'[^\d.]'), '');
    n = num.tryParse(cleaned);
  }
  if (n == null) return fallback ?? '';
  // Heuristic: sometimes price comes in **cents** (x100). If absurdly large, scale down.
  if (n > 10000000 && n % 100 == 0) n = n / 100;
  return NumberFormat.compactCurrency(symbol: '\$').format(n);
}

// ---- Choose a good, high-res URL and normalize to https
String? pickBestPhotoUrl(List<String>? urls) {
  if (urls == null || urls.isEmpty) return null;
  final candidates = urls.where((u) {
    final s = u.toLowerCase();
    final bad = s.contains('nophoto') || s.contains('comingsoon') || s.contains('placeholder');
    final okExt = s.endsWith('.jpg') || s.endsWith('.jpeg') || s.endsWith('.png') || s.contains('/photo') || s.contains('/image');
    return !bad && okExt;
  }).toList();
  candidates.sort((a, b) {
    int score(String s) =>
      (s.contains('thumb') || s.contains('thumbnail') || s.contains('small') || s.contains('w=') || s.contains('h=')) ? 1 : 0;
    return score(a) - score(b);
  });
  final chosen = (candidates.isNotEmpty ? candidates.first : urls.first);
  final u = Uri.tryParse(chosen);
  return (u != null && u.scheme == 'http') ? u.replace(scheme: 'https').toString() : chosen;
}

// ---- Full-screen/hero image (feed) and card image (list)
class ListingImage extends StatelessWidget {
  final List<String> photos;
  final String priceLabel;     // already formatted string (use formatListingPrice)
  final bool fullScreen;       // true for feed, false for cards
  const ListingImage({super.key, required this.photos, required this.priceLabel, this.fullScreen = false});

  @override
  Widget build(BuildContext context) {
    final url = pickBestPhotoUrl(photos);
    final size = MediaQuery.sizeOf(context);
    final dpr  = MediaQuery.devicePixelRatioOf(context);

    final img = url == null
        ? const ColoredBox(color: Color(0xFFEEEEEE))
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,                // crop edges, never stretch
            width: double.infinity,
            height: double.infinity,
            memCacheWidth:  (size.width  * dpr).round(),
            memCacheHeight: (size.height * (fullScreen ? dpr : dpr * 0.8)).round(),
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) => const ColoredBox(color: Color(0xFFE8E8E8)),
            errorWidget:   (_, __, ___) => const Center(child: Icon(Icons.image_not_supported_outlined)),
          );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          img,
          // top/bottom gradients for readability
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black26, Colors.transparent, Colors.transparent, Colors.black38],
                    stops: const [0.0, 0.25, 0.75, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // price badge (top-left). move to bottom by changing 'top'->'bottom'
          if (priceLabel.isNotEmpty)
            Positioned(
              left: 12, top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(priceLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
            ),
        ],
      ),
    );
  }
}
