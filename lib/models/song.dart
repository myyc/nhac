class Song {
  final String id;
  final String title;
  final String? album;
  final String? albumId;
  final String? artist;
  final String? artistId;
  final int? track;
  final int? year;
  final String? genre;
  final String? coverArt;
  final int? size;
  final String? contentType;
  final String? suffix;
  final int? duration;
  final int? bitRate;
  final String? path;
  final int? playCount;
  final int? discNumber;
  final DateTime? created;
  final DateTime? starred;
  final String? type;
  final int? bookmarkPosition;

  Song({
    required this.id,
    required this.title,
    this.album,
    this.albumId,
    this.artist,
    this.artistId,
    this.track,
    this.year,
    this.genre,
    this.coverArt,
    this.size,
    this.contentType,
    this.suffix,
    this.duration,
    this.bitRate,
    this.path,
    this.playCount,
    this.discNumber,
    this.created,
    this.starred,
    this.type,
    this.bookmarkPosition,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'],
      title: json['title'],
      album: json['album'],
      albumId: json['albumId'],
      artist: json['artist'],
      artistId: json['artistId'],
      track: json['track'],
      year: json['year'],
      genre: json['genre'],
      coverArt: json['coverArt'],
      size: json['size'],
      contentType: json['contentType'],
      suffix: json['suffix'],
      duration: json['duration'],
      bitRate: json['bitRate'],
      path: json['path'],
      playCount: json['playCount'],
      discNumber: json['discNumber'],
      created: json['created'] != null 
          ? DateTime.parse(json['created']) 
          : null,
      starred: json['starred'] != null 
          ? DateTime.parse(json['starred']) 
          : null,
      type: json['type'],
      bookmarkPosition: json['bookmarkPosition'],
    );
  }

  String get formattedDuration {
    if (duration == null) return '';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}