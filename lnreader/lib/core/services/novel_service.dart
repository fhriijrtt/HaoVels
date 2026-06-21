import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Klien untuk server scraper lokal (lihat scraper/index.js).
///
/// Lazy scraping: tidak ada data yang diambil "di depan". NovelService hanya
/// memanggil server saat data itu benar-benar dibutuhkan oleh UI:
///   - loadIndex()          dipanggil saat halaman Explore dibuka
///                          -> hanya title, cover, author, id.
///   - loadDetailById(id)   dipanggil saat user membuka detail novel
///                          -> synopsis, genres, author, artist, volume,
///                             cover volume, dan daftar chapter (TANPA isi).
///   - loadChapterContent() dipanggil saat user membuka chapter tertentu
///                          -> htmlContent chapter tersebut saja.
///
/// Cache sederhana di memori (Map) mencegah novel/chapter yang sudah pernah
/// diambil di-request ulang selama app berjalan. Server scraper juga punya
/// cache sendiri (lihat scraper/index.js), jadi data tetap aman dari
/// scraping berulang walau cache di app ini hilang (mis. setelah hot-restart).
class NovelService {
  /// Alamat server scraper lokal (`npm start` di folder scraper/).
  /// - Web/desktop (chrome, dst): biarkan default ini.
  /// - Android emulator: ganti jadi 'http://10.0.2.2:3000'.
  /// - Device fisik / server scraper di mesin lain: ganti ke IP/host yang sesuai.
  static const String baseUrl = 'http://localhost:3000';

  List<Novel>? _indexCache;
  final Map<String, Novel> _detailCache = {};
  final Map<String, String> _chapterCache = {};

  /// Index ringan untuk Explore: title, cover, author, id saja.
  Future<List<Novel>> loadIndex() async {
    if (_indexCache != null) return _indexCache!;

    final res = await http.get(Uri.parse('$baseUrl/api/novels'));
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat daftar novel (${res.statusCode})');
    }
    final List data = jsonDecode(res.body);
    _indexCache =
        data.map((e) => Novel.fromIndexJson(e as Map<String, dynamic>)).toList();
    return _indexCache!;
  }

  /// Detail novel (synopsis, genres, author, artist, volume + daftar chapter).
  /// Baru di-scrape oleh server saat pertama kali dipanggil untuk [id] ini,
  /// lalu hasilnya di-cache di sini supaya pembukaan berikutnya instan.
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
    final indexEntry = _indexCache?.where((n) => n.id == id);
    if (indexEntry != null && indexEntry.isNotEmpty) {
      merged = indexEntry.first.copyWithDetail(detail);
    }

    _detailCache[id] = merged;
    return merged;
  }

  /// htmlContent satu chapter saja. Baru di-request ke server (yang akan
  /// fetch halaman chapter + jalankan htmlCleaner) saat chapter ini dibuka.
  Future<String> loadChapterContent(String chapterUrl) async {
    final cached = _chapterCache[chapterUrl];
    if (cached != null) return cached;

    final uri = Uri.parse('$baseUrl/api/chapter')
        .replace(queryParameters: {'url': chapterUrl});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat isi chapter (${res.statusCode})');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    final content = data['htmlContent'] as String? ?? '';
    _chapterCache[chapterUrl] = content;
    return content;
  }
}
