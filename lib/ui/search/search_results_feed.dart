// --- Feed Item ---
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/listing_format.dart';
import '../../services/fav_visit_store.dart';
import 'utils/listing_mapper.dart';
import '../../models/realtor_badge.dart';
import '../../widgets/tiktok_promo_card.dart';
// ...existing imports...

// --- Helper Widgets ---
class _PriceLine extends StatelessWidget {
  final String text;
  const _PriceLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  final String? tooltip;
  const _RoundIcon({required this.icon, this.filled = false, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final color = filled ? Colors.redAccent : Colors.white;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
      ),
    );
  }
}

// ...existing code...

typedef ShareToInbox = Future<void> Function({
  required Map<String, dynamic> listing,
  required String toUserId,
});

class SearchResultsFeed extends StatefulWidget {
  final List<Map<String, dynamic>> listings;
  final String? shareTargetUserId; // set if you want direct-share to a user

  const SearchResultsFeed({Key? key, required this.listings, this.shareTargetUserId}) : super(key: key);

  @override
  State<SearchResultsFeed> createState() => _SearchResultsFeedState();
}

class _SearchResultsFeedState extends State<SearchResultsFeed> {
  @override
  Widget build(BuildContext context) {
    final listings = widget.listings;
    if (listings.isEmpty) {
      return const Center(child: Text('No listings found'));
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: listings.length,
      itemBuilder: (context, i) {
        final l = listings[i];
        return _FeedItem(listing: l);
      },
    );
  }
}

// --- Feed Item ---
class _FeedItem extends StatefulWidget {
  const _FeedItem({required this.listing});
  final Map listing;
  @override
  State<_FeedItem> createState() => _FeedItemState();
}

class _FeedItemState extends State<_FeedItem> {
  late final String id = ListingFormat.listingId(widget.listing);
  late final String? tourUrl = ListingFormat.virtualTourUrl(widget.listing);
  late final List<String> photos = ListingFormat.photoUrls(widget.listing);
  late final RealtorBadge? realtorBadge = widget.listing['realtorBadge'] != null
      ? RealtorBadge.fromMap(Map<String, dynamic>.from(widget.listing['realtorBadge']))
      : null;
  late final List<String> tiktokVideoUrls = (widget.listing['tiktokVideoUrls'] as List?)?.cast<String>() ?? const [];

  bool fav = false;
  bool visited = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final f = await FavVisitStore.isFavorite(id);
    final v = await FavVisitStore.isVisited(id);
    if (mounted) setState(() { fav = f; visited = v; });
  }

  Future<void> _toggleFav() async {
    await FavVisitStore.toggleFavorite(id);
    final f = await FavVisitStore.isFavorite(id);
    if (mounted) setState(() => fav = f);
  }

  Future<void> _toggleVisited() async {
    await FavVisitStore.toggleVisited(id);
    final v = await FavVisitStore.isVisited(id);
    if (mounted) setState(() => visited = v);
  }

  Widget _buildTourOrFirstPhoto() {
    if (tourUrl != null) {
      try {
        return _TourView(url: tourUrl);
      } catch (_) {
        return _HeroImage(url: photos.isNotEmpty ? photos.first : null);
      }
    }
    final img = photos.isNotEmpty ? photos.first : null;
    return _HeroImage(url: img);
  }

  List<Widget> _buildMediaPages() {
    final pages = <Widget>[];
    final hasTikTok = (realtorBadge?.isVerified ?? false) && tiktokVideoUrls.isNotEmpty;
    if (hasTikTok) {
      pages.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AspectRatio(
            aspectRatio: 9/16,
            child: TikTokPromoCard(
              videoUrl: tiktokVideoUrls.first,
              realtorAvatarUrl: null, // Add avatar if available
              realtorName: realtorBadge?.tiktokHandle,
            ),
          ),
        ),
      );
    }
    if (tourUrl != null) pages.add(_buildTourOrFirstPhoto());
    for (final p in photos) {
      pages.add(_HeroImage(url: p));
    }
    if (pages.isEmpty) {
      pages.add(Container(color: Colors.grey.shade300));
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final price = ListingFormat.price(widget.listing);
    final addr = ListingFormat.address(widget.listing);
    final details = ListingFormat.details(widget.listing);
    final mediaPages = _buildMediaPages();

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView(
          controller: PageController(),
          children: mediaPages,
        ),
        const _BottomFade(),
        Positioned(
          left: 16,
          right: 120,
          bottom: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PriceLine(text: price),
              const SizedBox(height: 6),
              Text(
                addr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black38)],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundIcon(
                icon: fav ? Icons.favorite : Icons.favorite_border,
                filled: fav,
                onTap: _toggleFav,
                tooltip: 'Favorite',
              ),
              const SizedBox(height: 14),
              _RoundIcon(
                icon: visited ? Icons.check_circle : Icons.check_circle_outline,
                filled: visited,
                onTap: _toggleVisited,
                tooltip: 'Visited',
              ),
              const SizedBox(height: 14),
              _RoundIcon(
                icon: Icons.chat_bubble_outline,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Open compose to send listing…')),
                  );
                },
                tooltip: 'Message',
              ),
              const SizedBox(height: 14),
              _RoundIcon(
                icon: Icons.share,
                onTap: () async {
                  final text = '${ListingFormat.address(widget.listing)} • ${ListingFormat.price(widget.listing)}';
                  // TODO: wire to Share.share(text) if share_plus is available
                },
                tooltip: 'Share',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TourView extends StatelessWidget {
  final String? url;
  const _TourView({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const ColoredBox(color: Colors.black12);
    }
    return WebViewWidget(
      controller: WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(true)
        ..loadRequest(Uri.parse(url!)),
    );
  }
}

class _PhotoCarousel extends StatelessWidget {
  final List<String> photos;
  final ValueChanged<int>? onPage;

  const _PhotoCarousel({required this.photos, this.onPage});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const ColoredBox(color: Colors.black12);
    }
    return PageView.builder(
      onPageChanged: onPage,
      itemCount: photos.length,
      itemBuilder: (_, i) => AspectRatio(
        aspectRatio: 16 / 9,
        child: CachedNetworkImage(
          imageUrl: photos[i],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (c, _) => const ColoredBox(color: Color(0x11000000)),
          errorWidget: (c, _, __) =>
              const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.white70)),
        ),
      ),
    );
  }
}

class _BottomFade extends StatelessWidget {
  const _BottomFade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(0, 0.4),
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xAA000000)],
          ),
        ),
      ),
    );
  }
}

class _ListingOverlayInfo extends StatelessWidget {
  final ListingView lv;
  const _ListingOverlayInfo({required this.lv});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textBig = theme.textTheme.headlineSmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );
    final textMed = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // price
        Row(
          children: [
            const Icon(Icons.dehaze_rounded, color: Colors.white, size: 30),
            const SizedBox(width: 8),
            Text(lv.priceLabel, style: textBig),
          ],
        ),
        const SizedBox(height: 8),
        Text(lv.addressLine, style: textMed),
        if (lv.addressCityState.isNotEmpty)
          Text(lv.addressCityState,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _chip(Icons.bed_outlined, lv.bedsLabel),
            _chip(Icons.bathtub_outlined, lv.bathsLabel),
            _chip(Icons.space_dashboard_outlined, lv.sqftLabel),
          ],
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            )),
      ]),
    );
  }
}

class _ActionRail extends StatelessWidget {
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  const _ActionRail({required this.onLike, required this.onComment, required this.onShare});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String semantics, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: Colors.white24,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(icon, color: Colors.white, size: 26, semanticLabel: semantics),
              ),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.favorite_border_rounded, 'Save', onLike),
        btn(Icons.mode_comment_outlined, 'Comment', onComment),
        btn(Icons.share_rounded, 'Share', onShare),
      ],
    );
  }
}

class _PagerDots extends StatelessWidget {
  final int count;
  final int index;
  const _PagerDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: List.generate(
        count,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: i == index ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == index ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(color: Colors.grey.shade300);
    }

    final size = MediaQuery.of(context).size;
    final dpr  = MediaQuery.of(context).devicePixelRatio;
    final targetW = (size.width  * dpr).round();
    final targetH = (size.height * dpr).round();

    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      // Ask the cache for full device-pixel resolution
      memCacheWidth: targetW,
      memCacheHeight: targetH,
      // Render with high quality to avoid shimmer blur during transitions
      imageBuilder: (context, provider) => Image(
        image: provider,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
      placeholder: (_, __) => Container(color: Colors.black12),
      errorWidget: (_, __, ___) => Container(color: Colors.black26),
    );
  }
}
