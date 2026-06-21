class Chapter {
  final String title;
  final String htmlContent;
  final int order;

  /// URL halaman chapter di sumber asli. Dipakai untuk lazy-fetch htmlContent
  /// (lihat NovelService.loadChapterContent) saat chapter ini dibuka.
  final String url;

  /// Kapan halaman chapter ini TERAKHIR DI-UPDATE oleh penulis/admin sumber
  /// (dari dateModified). Lazy: null sampai chapter ini benar-benar dibuka
  /// (lewat /api/chapter) ATAU tanggalnya diambil massal lewat
  /// NovelService.loadChapterDatesBatch (lihat VolumePage).
  final DateTime? updatedAt;

  /// Kapan chapter ini PERTAMA KALI dipublikasikan (dari datePublished).
  final DateTime? publishedAt;

  Chapter({
    required this.title,
    this.htmlContent = '',
    required this.order,
    this.url = '',
    this.updatedAt,
    this.publishedAt,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] ?? '',
        htmlContent: json['htmlContent'] ?? '',
        order: json['order'] ?? 0,
        url: json['url'] ?? '',
        updatedAt: _parseDate(json['updatedAt']),
        publishedAt: _parseDate(json['publishedAt']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'htmlContent': htmlContent,
        'order': order,
        'url': url,
        'updatedAt': updatedAt?.toIso8601String(),
        'publishedAt': publishedAt?.toIso8601String(),
      };

  /// Salinan chapter ini dengan tanggal terisi (dipakai setelah
  /// loadChapterDatesBatch / loadChapterContent berhasil mengambil tanggal).
  Chapter copyWithDates({DateTime? updatedAt, DateTime? publishedAt}) => Chapter(
        title: title,
        htmlContent: htmlContent,
        order: order,
        url: url,
        updatedAt: updatedAt ?? this.updatedAt,
        publishedAt: publishedAt ?? this.publishedAt,
      );
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

  /// Salinan volume ini dengan chapters yang sudah disisipi tanggal
  /// (dipakai oleh VolumePage setelah batch-fetch tanggal selesai).
  Volume copyWithChapters(List<Chapter> newChapters) => Volume(
        number: number,
        name: name,
        cover: cover,
        chapters: newChapters,
      );
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

  /// Kapan novel ini TERAKHIR DI-UPDATE di sumber (chapter baru ditambahkan,
  /// atau halaman novel diedit). Dipakai untuk mengurutkan Explore &
  /// Bookmark dari yang terbaru. Diisi langsung dari index API
  /// (/api/novels), jadi SELALU tersedia tanpa request tambahan.
  final DateTime? updatedAt;

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
    this.updatedAt,
  });

  int get volumeCount => volumes.length;

  /// Index entry dari API (/api/novels) - ringan, dipakai di Explore.
  factory Novel.fromIndexJson(Map<String, dynamic> json) => Novel(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        alias: List<String>.from(json['alias'] ?? []),
        cover: json['cover'] ?? '',
        author: json['author'] ?? '',
        genres: List<String>.from(json['genres'] ?? []),
        dataPath: json['dataPath'] ?? '',
        updatedAt: _parseDate(json['updatedAt']),
      );

  /// Detail penuh dari API (/api/novels/:id).
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
        updatedAt: _parseDate(json['updatedAt']),
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
        updatedAt: detail.updatedAt ?? updatedAt,
      );

  /// Salinan novel ini dengan satu volume diganti (dipakai VolumePage
  /// setelah menyisipkan tanggal hasil batch-fetch ke chapter-chapternya).
  Novel copyWithVolume(Volume updatedVolume) => Novel(
        id: id,
        title: title,
        alias: alias,
        cover: cover,
        author: author,
        artist: artist,
        genres: genres,
        synopsis: synopsis,
        volumes: volumes
            .map((v) => v.number == updatedVolume.number ? updatedVolume : v)
            .toList(),
        dataPath: dataPath,
        updatedAt: updatedAt,
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

/// Parsing aman untuk tanggal ISO 8601 dari API (mis. "2026-06-14T20:53:05+07:00").
/// Mengembalikan null jika field kosong/null/format tidak valid, supaya UI
/// bisa menyembunyikan keterangan tanggal alih-alih crash.
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) return null;
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}
