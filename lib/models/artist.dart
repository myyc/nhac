class Artist {
  final String id;
  final String name;
  final int? albumCount;
  final String? coverArt;
  final DateTime? starred;

  Artist({
    required this.id,
    required this.name,
    this.albumCount,
    this.coverArt,
    this.starred,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'],
      name: json['name'],
      albumCount: json['albumCount'],
      coverArt: json['coverArt'],
      starred: json['starred'] != null 
          ? DateTime.parse(json['starred']) 
          : null,
    );
  }
}