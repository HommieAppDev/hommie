// listing_card_item.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../listing_view_helpers.dart' as helpers;
import '../../models/listing_vm.dart' as models;
import 'package:hommie/models/listing.dart';
import 'package:hommie/models/listing_vm.dart';
import 'package:hommie/ui/listing_view_helpers.dart'
    hide ListingVM; // hide the conflicting VM

class ListingCardItem extends StatelessWidget {
  final Map<String, dynamic> rawListing;
  final VoidCallback onTap;
  final Widget? trailing; // optional actions (heart/menu/etc.)

  const ListingCardItem({
    super.key,
    required this.rawListing,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = models.ListingVM(
        Listing.fromJson(Map<String, dynamic>.from(rawListing)));

    final imageUrl = vm.primaryImageUrl;
    final priceText = (vm.priceText.isNotEmpty) ? vm.priceText : 'Price TBD';
    final addressText = _fmtAddress(vm);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                        color:
                            theme.colorScheme.surfaceVariant.withOpacity(0.5)),
                    errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: text block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          priceText,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (addressText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            addressText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _chip(context, Icons.bed_outlined, vm.bedroomText),
                            _chip(
                                context, Icons.bathtub_outlined, vm.bathsText),
                            if (vm.sqftText.isNotEmpty)
                              _chip(context, Icons.straighten, vm.sqftText),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Right: optional trailing actions
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtAddress(models.ListingVM vm) {
    final parts = <String>[];
    if (vm.addressLine.isNotEmpty) parts.add(vm.addressLine);
    final cityState = [vm.city, vm.state].where((s) => s.isNotEmpty).join(', ');
    if (cityState.isNotEmpty) parts.add(cityState);
    if (vm.zip.isNotEmpty) parts.add(vm.zip);
    return parts.join(' • ');
  }

  static Widget _chip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurface),
          const SizedBox(width: 6),
          Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
