import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../listing_view_helpers.dart';

typedef ListingTap = void Function(String listingId);

class ListingFeedItem extends StatelessWidget {
  final Map<String, dynamic> rawListing;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final ListingTap onOpenDetails;

  const ListingFeedItem({
    super.key,
    required this.rawListing,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final vm = ListingVM.fromMap(rawListing);
    final imageUrl = vm.photos.isNotEmpty ? vm.photos.first : null;

    return Stack(
      children: [
        // FULLSCREEN MEDIA
        Positioned.fill(
          child: imageUrl == null
              ? Container(color: Colors.black12)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.black12),
                  errorWidget: (_, __, ___) => Container(color: Colors.black12),
                ),
        ),

        // DARK GRADIENT for readability
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.55),
                  ],
                ),
              ),
            ),
          ),
        ),

        // RIGHT BUTTONS
        Positioned(
          right: 12,
          bottom: 110,
          child: Column(
            children: [
              _circleBtn(Icons.favorite_border, onLike),
              const SizedBox(height: 16),
              _circleBtn(Icons.chat_bubble_outline, onComment),
              const SizedBox(height: 16),
              _circleBtn(Icons.share, onShare),
            ],
          ),
        ),

        // BOTTOM DETAILS
        Positioned(
          left: 12,
          right: 72,
          bottom: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenDetails(vm.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.priceText.isEmpty ? '' : vm.priceText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtAddress(vm),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _pill(vm.bedsText),
                    const SizedBox(width: 8),
                    _pill(vm.bathsText),
                    if (vm.sqftText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _pill(vm.sqftText),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _fmtAddress(ListingVM vm) {
    final sb = StringBuffer(vm.addressLine);
    if (vm.city.isNotEmpty) sb.write(', ${vm.city}');
    if (vm.state.isNotEmpty) sb.write(', ${vm.state}');
    return sb.toString();
  }

  static Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }

  static Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
