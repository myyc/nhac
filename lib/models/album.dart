class Album {
  final String id;
  final String name;
  final String? artist;
  final String? artistId;
  final String? coverArt;
  final int? songCount;
  final int? duration;
  final int? playCount;
  final DateTime? created;
  final DateTime? starred;
  final int? year;
  final String? genre;

  Album({
    required this.id,
    required this.name,
    this.artist,
    this.artistId,
    this.coverArt,
    this.songCount,
    this.duration,
    this.playCount,
    this.created,
    this.starred,
    this.year,
    this.genre,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'],
      name: json['name'],
      artist: json['artist'],
      artistId: json['artistId'],
      coverArt: json['coverArt'],
      songCount: json['songCount'],
      duration: json['duration'],
      playCount: json['playCount'],
      created: json['created'] != null 
          ? DateTime.parse(json['created']) 
          : null,
      starred: json['starred'] != null 
          ? DateTime.parse(json['starred']) 
          : null,
      year: json['year'],
      genre: json['genre'],
    );
  }
}