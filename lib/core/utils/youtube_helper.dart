class YoutubeHelper {
  /// Extracts 11-character YouTube video ID from various YouTube URL formats.
  static String? extractVideoId(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final clean = url.trim();

    final RegExp regExp = RegExp(
      r'^(?:https?:\/\/)?(?:www\.)?(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([\w-]{11})',
      caseSensitive: false,
      multiLine: false,
    );

    final match = regExp.firstMatch(clean);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }

    // Direct 11-character video ID fallback
    if (RegExp(r'^[\w-]{11}$').hasMatch(clean)) {
      return clean;
    }

    return null;
  }

  /// Constructs an embed URL suitable for minimal bandwidth (muted autoplay loop)
  static String? getEmbedUrl(String? url) {
    final videoId = extractVideoId(url);
    if (videoId == null) return null;
    return 'https://www.youtube.com/embed/$videoId?autoplay=1&mute=1&loop=1&playlist=$videoId&controls=0&modestbranding=1&rel=0&vq=small';
  }

  /// Gets high-quality or medium-quality thumbnail for YouTube video
  static String? getThumbnailUrl(String? url) {
    final videoId = extractVideoId(url);
    if (videoId == null) return null;
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }
}
