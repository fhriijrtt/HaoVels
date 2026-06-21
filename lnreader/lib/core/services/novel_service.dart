import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Hasil memuat isi satu chapter: HTML yang sudah dibersihkan + tanggal
/// terakhir update/publish chapter tersebut (dari JSON-LD halaman sumber).
class ChapterContentResult {
  final String htmlContent;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  ChapterContentResult({
    required this.htmlContent,
    this.updatedAt,
    this.publishedAt,
  });

  factory ChapterContentResult.fromJson(Map<String, dynamic> json) =>
      ChapterContentResult(
        htmlContent: json['htmlContent'] as String? ?? '',
        updatedAt: _parseDate(json['updatedAt']),
        publishedAt: _parseDate(json['publishedAt']),
      );
}

/// Klien untuk server scraper (lihat scraper/index.js), di-deploy di Railway.
///
/// MODE: eager + scheduled cache di sisi server. Server scraper sendiri yang
/// menjalankan scraping berkala di background (lihat doc index.js), jadi
/// NovelService di sini HANYA bertugas memanggil endpoint dan menyimpan
/// cache ringan di memori app supaya tidak request berulang dalam satu sesi:
///   - loadIndex()              dipanggil saat halaman Explore dibuka
///                              -> title, cover, author, id, updatedAt.
///                              Sudah terurut TERBARU -> TERLAMA dari server,
///                              JANGAN di-sort ulang di sisi app.
///   - loadDetailById(id)       dipanggil saat user membuka detail novel
///                              -> synopsis, genres, author, artist,
///                                 updatedAt, volume + daftar chapter
///                                 (TANPA isi chapter).
///   - loadChapterContent()     dipanggil saat user membuka chapter tertentu
///                              -> htmlContent + updatedAt/publishedAt
///                                 chapter tersebut saja.
///   - loadChapterDatesBatch()  dipanggil saat halaman Volume dibuka
///                              -> tanggal SEMUA chapter di volume itu
///                                 sekaligus (tanpa htmlContent), supaya
///                                 daftar chapter bisa langsung menampilkan
///                                 keterangan "terakhir update".
class NovelService {
  /// Alamat server scraper. Sudah di-deploy & berjalan terus-menerus di
  /// Railway (eager + scheduled scraping, lihat scraper/index.js), BUKAN
  /// lagi server lokal — jadi harus selalu pakai URL publik ini, baik saat
  /// development maupun production, di semua platform (Android, iOS, web,
  /// desktop).
  static const String baseUrl = 'https://haovels-production.up.railway.app';

  List<Novel>? _indexCache;
  final Map<String, Novel> _detailCache = {};
  final Map<String, ChapterContentResult> _chapterCache = {};

  /// Index ringan untuk Explore: title, cover, author, id, updatedAt.
  /// Sudah terurut TERBARU -> TERLAMA langsung dari server.
  Future<List<Novel>> loadIndex({bool forceRefresh = false}) async {
    if (!forceRefresh && _indexCache != null) return _indexCache!;

    final res = await http.get(Uri.parse('$baseUrl/api/novels'));
    if (res.statusCode == 503) {
      // Server baru saja start & belum selesai scrape awal -> bukan error
      // permanen, app sebaiknya mencoba lagi sebentar (lihat ExplorePage).
      throw Exception(
          'Data belum siap, server sedang menyiapkan daftar novel. Coba lagi sebentar.');
    }
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat daftar novel (${res.statusCode})');
    }
    final List data = jsonDecode(res.body);
    _indexCache =
        data.map((e) => Novel.fromIndexJson(e as Map<String, dynamic>)).toList();
    return _indexCache!;
  }

  /// Entry index (ringan) untuk satu novel tertentu, jika sudah pernah
  /// dimuat lewat loadIndex(). Dipakai BookmarkPage untuk menggabungkan
  /// bookmark lokal dengan `updatedAt` terbaru dari server tanpa request
  /// tambahan per-item.
  Novel? indexEntryFor(String id) {
    try {
      return _indexCache?.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Novel>? get cachedIndex => _indexCache;

  /// Detail novel (synopsis, genres, author, artist, updatedAt, volume +
  /// daftar chapter). Server sudah menyimpan ini di cache (di-refresh
  /// berkala oleh scheduler), jadi respons biasanya cepat. Hasilnya
  /// di-cache juga di sisi app supaya pembukaan berikutnya instan.
  Future<Novel?> loadDetailById(String id) async {
    final cached = _detailCache[id];
    if (cached != null) return cached;

    final res = await http.get(Uri.parse('$baseUrl/api/novels/$id'));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat detail novel (${res.statusCode})');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    final detail = Novel.fromDetailJson(data);

    // Jika entry index untuk novel ini sudah pernah di-load, gabungkan supaya
    // field ringan (cover/title dari index) tetap konsisten.
    Novel merged = detail;
    final indexEntry = indexEntryFor(id);
    if (indexEntry != null) {
      merged = indexEntry.copyWithDetail(detail);
    }

    _detailCache[id] = merged;
    return merged;
  }

  /// htmlContent + updatedAt/publishedAt satu chapter. Tetap LAZY: baru
  /// di-request ke server (yang akan fetch halaman chapter + jalankan
  /// htmlCleaner) saat chapter ini dibuka.
  Future<ChapterContentResult> loadChapterContent(String chapterUrl) async {
    final cached = _chapterCache[chapterUrl];
    if (cached != null) return cached;

    final uri = Uri.parse('$baseUrl/api/chapter')
        .replace(queryParameters: {'url': chapterUrl});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat isi chapter (${res.statusCode})');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    final result = ChapterContentResult.fromJson(data);
    _chapterCache[chapterUrl] = result;
    return result;
  }

  /// Tanggal (updatedAt/publishedAt) untuk BANYAK chapter sekaligus, tanpa
  /// htmlContent. Dipanggil saat halaman Volume dibuka supaya semua chapter
  /// di volume itu langsung menampilkan keterangan "terakhir update".
  ///
  /// Mengembalikan map url -> {updatedAt, publishedAt}. Chapter yang gagal
  /// diambil tanggalnya akan punya value {null, null} (bukan exception),
  /// supaya satu chapter gagal tidak menggagalkan seluruh daftar.
  Future<Map<String, ChapterDates>> loadChapterDatesBatch(
      List<String> chapterUrls) async {
    if (chapterUrls.isEmpty) return {};

    final res = await http.post(
      Uri.parse('$baseUrl/api/chapter-dates'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'urls': chapterUrls}),
    );
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat tanggal chapter (${res.statusCode})');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    return data.map((url, value) => MapEntry(
          url,
          ChapterDates(
            updatedAt: _parseDate(value['updatedAt']),
            publishedAt: _parseDate(value['publishedAt']),
          ),
        ));
  }
}

class ChapterDates {
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  ChapterDates({this.updatedAt, this.publishedAt});
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) return null;
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}
