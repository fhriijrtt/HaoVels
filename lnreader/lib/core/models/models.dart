class Chapter {
  final String title;
  final String htmlContent;
  final int order;

  /// URL halaman chapter di sumber asli. Dipakai untuk lazy-fetch htmlContent
  /// (lihat NovelService.loadChapterContent) saat chapter ini dibuka.
  final String url;

  Chapter({
    required this.title,
    this.htmlContent = '',
    required this.order,
    this.url = '',
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] ?? '',
        htmlContent: json['htmlContent'] ?? '',
        order: json['order'] ?? 0,
        url: json['url'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'htmlContent': htmlContent,
        'order': order,
        'url': url,
      };
}

class Volume {
  final int number;
  final String name;
  final String cover;
  final List<Chapter> chapters;

  Volume({
    required this.number,
    required this.name,
    required this.cover,
    required this.chapters,
  });

  factory Volume.fromJson(Map<String, dynamic> json) => Volume(
        number: json['number'] ?? 0,
        name: json['name'] ?? 'Volume ${json['number'] ?? 0}',
        cover: json['cover'] ?? '',
        chapters: ((json['chapters'] as List?) ?? [])
            .map((e) => Chapter.fromJson(e))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'name': name,
        'cover': cover,
        'chapters': chapters.map((e) => e.toJson()).toList(),
      };
}

class Novel {
  final String id;
  final String title;
  final List<String> alias;
  final String cover;
  final String author;
  final String artist;
  final List<String> genres;
  final String synopsis;
  final List<Volume> volumes;
  /// path to the detail json file (assets/novels/xxx.json), used for lazy loading
  final String dataPath;

  Novel({
    required this.id,
    required this.title,
    this.alias = const [],
    required this.cover,
    this.author = '',
    this.artist = '',
    this.genres = const [],
    this.synopsis = '',
    this.volumes = const [],
    this.dataPath = '',
  });

  int get volumeCount => volumes.length;

  /// Index entry (from novels.json) - lightweight
  factory Novel.fromIndexJson(Map<String, dynamic> json) => Novel(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        alias: List<String>.from(json['alias'] ?? []),
        cover: json['cover'] ?? '',
        author: json['author'] ?? '',
        genres: List<String>.from(json['genres'] ?? []),
        dataPath: json['dataPath'] ?? '',
      );

  /// Full detail json (assets/novels/xxx.json)
  factory Novel.fromDetailJson(Map<String, dynamic> json) => Novel(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        alias: List<String>.from(json['alias'] ?? []),
        cover: json['cover'] ?? '',
        author: json['author'] ?? '',
        artist: json['artist'] ?? '',
        genres: List<String>.from(json['genres'] ?? []),
        synopsis: json['synopsis'] ?? '',
        volumes: ((json['volumes'] as List?) ?? [])
            .map((e) => Volume.fromJson(e))
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number)),
        dataPath: json['dataPath'] ?? '',
      );

  Novel copyWithDetail(Novel detail) => Novel(
        id: detail.id.isNotEmpty ? detail.id : id,
        title: detail.title.isNotEmpty ? detail.title : title,
        alias: detail.alias.isNotEmpty ? detail.alias : alias,
        cover: detail.cover.isNotEmpty ? detail.cover : cover,
        author: detail.author,
        artist: detail.artist,
        genres: detail.genres.isNotEmpty ? detail.genres : genres,
        synopsis: detail.synopsis,
        volumes: detail.volumes,
        dataPath: dataPath,
      );

  /// A flattened, linear list of (volume, chapter) across ALL volumes,
  /// used for previous/next navigation.
  List<FlatChapterRef> get flatChapters {
    final List<FlatChapterRef> list = [];
    for (final v in volumes) {
      for (final c in v.chapters) {
        list.add(FlatChapterRef(volume: v, chapter: c));
      }
    }
    return list;
  }
}

class FlatChapterRef {
  final Volume volume;
  final Chapter chapter;
  FlatChapterRef({required this.volume, required this.chapter});
}
