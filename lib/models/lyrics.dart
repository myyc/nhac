class LyricsLine {
  final Duration? start;
  final String text;

  LyricsLine({this.start, required this.text});
}

class Lyrics {
  final bool synced;
  final String? lang;
  final String? displayArtist;
  final String? displayTitle;
  final List<LyricsLine> lines;

  Lyrics({
    required this.synced,
    this.lang,
    this.displayArtist,
    this.displayTitle,
    required this.lines,
  });

  bool get isEmpty => lines.isEmpty || lines.every((l) => l.text.trim().isEmpty);

  /// Parse an OpenSubsonic `structuredLyrics` entry.
  factory Lyrics.fromStructured(Map<String, dynamic> json) {
    final synced = json['synced'] == true;
    final linesJson = (json['line'] as List?) ?? const [];
    final lines = <LyricsLine>[];
    for (final l in linesJson) {
      if (l is! Map) continue;
      final value = (l['value'] ?? '').toString();
      Duration? start;
      final rawStart = l['start'];
      if (synced && rawStart != null) {
        final ms = rawStart is int
            ? rawStart
            : int.tryParse(rawStart.toString()) ?? 0;
        start = Duration(milliseconds: ms);
      }
      lines.add(LyricsLine(start: start, text: value));
    }
    return Lyrics(
      synced: synced,
      lang: json['lang']?.toString(),
      displayArtist: json['displayArtist']?.toString(),
      displayTitle: json['displayTitle']?.toString(),
      lines: lines,
    );
  }

  /// Parse the legacy Subsonic `getLyrics` response (plain text only).
  factory Lyrics.fromPlain(Map<String, dynamic> json) {
    final text = (json['value'] ?? '').toString();
    final lines = text
        .split('\n')
        .map((l) => LyricsLine(text: l))
        .toList();
    return Lyrics(
      synced: false,
      displayArtist: json['artist']?.toString(),
      displayTitle: json['title']?.toString(),
      lines: lines,
    );
  }
}
