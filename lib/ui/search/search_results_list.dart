import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/listing_format.dart';

class SearchResultsList extends StatelessWidget {
  final List<Map<String, dynamic>> listings;
  final void Function(Map<String, dynamic> listing)? onTap;

  const SearchResultsList({
    super.key,
    required this.listings,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) return const Center(child: Text('No listings found'));

  final items = listings;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
  final listing = items[i];
  final photo = ListingFormat.photoUrls(listing).isNotEmpty ? ListingFormat.photoUrls(listing).first : null;
  final price = ListingFormat.price(listing);
  final addr = ListingFormat.address(listing);
  final details = ListingFormat.details(listing);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTap?.call(listing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: photo == null
                      ? const ColoredBox(color: Color(0x11000000))
                      : CachedNetworkImage(
                          imageUrl: photo,
                          fit: BoxFit.cover,
                          placeholder: (c, _) => const ColoredBox(color: Color(0x11000000)),
                          errorWidget: (c, _, __) =>
                              const Center(child: Icon(Icons.broken_image)),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.dehaze_rounded, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        price,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    addr,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Text(
                    details,
                    style: const TextStyle(fontSize: 15, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x0F000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
