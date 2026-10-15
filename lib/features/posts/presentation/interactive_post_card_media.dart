import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/youtube_helper.dart';

class InteractivePostCardMedia extends StatefulWidget {
  const InteractivePostCardMedia({
    required this.coverImageUrl,
    this.youtubeUrl,
    this.title,
    this.subtitle,
    super.key,
  });

  final String? coverImageUrl;
  final String? youtubeUrl;
  final String? title;
  final String? subtitle;

  @override
  State<InteractivePostCardMedia> createState() => _InteractivePostCardMediaState();
}

class _InteractivePostCardMediaState extends State<InteractivePostCardMedia> {
  Future<void> _launchVideo(String videoId) async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Impossible d’ouvrir le lien vidéo : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final youtubeId = YoutubeHelper.extractVideoId(widget.youtubeUrl);
    final hasVideo = youtubeId != null;
    final coverUrl = widget.coverImageUrl ?? (hasVideo ? YoutubeHelper.getThumbnailUrl(widget.youtubeUrl) : null);

    return GestureDetector(
      onTap: () {
        if (hasVideo) {
          _launchVideo(youtubeId);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF16162D),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF2B1C52),
              width: 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Base Cover Image / Poster with blur effect
              if (coverUrl != null && coverUrl.isNotEmpty) ...[
                Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, _) => const SizedBox.shrink(),
                ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.65),
                          Colors.black.withValues(alpha: 0.90),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // 2. UI Overlay: Title, Subtitle, Play Indicator
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (widget.title != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xE618102C),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: const Color(0x668E51FF)),
                            ),
                            child: Text(
                              widget.title!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFD6C2FF),
                              ),
                            ),
                          ),
                        if (hasVideo)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.pink.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.pink),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Lancer vidéo',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
