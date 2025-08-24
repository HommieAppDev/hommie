import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../utils/tiktok_oembed.dart';

Future<void> openTikTok(String url) async {
  final httpsUri = Uri.parse(url);
  final canHttps = await canLaunchUrl(httpsUri);
  if (canHttps) {
    await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
    return;
  }
}

class TikTokPromoCard extends StatefulWidget {
  final String videoUrl;
  final String? realtorAvatarUrl;
  final String? realtorName;

  const TikTokPromoCard({
    super.key,
    required this.videoUrl,
    this.realtorAvatarUrl,
    this.realtorName,
  });

  @override
  State<TikTokPromoCard> createState() => _TikTokPromoCardState();
}

class _TikTokPromoCardState extends State<TikTokPromoCard> {
  TikTokMeta? _meta;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meta = await TikTokOEmbed.fetch(widget.videoUrl);
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    return GestureDetector(
      onTap: () => openTikTok(widget.videoUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : CachedNetworkImage(
                      imageUrl: meta?.thumbnailUrl ?? '',
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: Icon(Icons.play_arrow, size: 48)),
                      ),
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.realtorAvatarUrl != null)
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: NetworkImage(widget.realtorAvatarUrl!),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meta?.title.isNotEmpty == true ? meta!.title : 'Watch on TikTok',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          widget.realtorName ?? meta?.authorName ?? '',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.video_library, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
