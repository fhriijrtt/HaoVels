import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/novel_service.dart';
import '../services/prefs_service.dart';

final novelServiceProvider = Provider<NovelService>((ref) => NovelService());
final prefsServiceProvider = Provider<PrefsService>((ref) => PrefsService());

/// All novels (index/light entries) used in Explore page.
/// Sudah terurut TERBARU -> TERLAMA langsung dari server (lihat
/// NovelService.loadIndex), JANGAN di-sort ulang di UI.
final novelIndexProvider = FutureProvider<List<Novel>>((ref) async {
  final service = ref.read(novelServiceProvider);
  return service.loadIndex();
});

/// Full detail (with volumes/chapters) for a given novel id.
final novelDetailProvider =
    FutureProvider.family<Novel?, String>((ref, novelId) async {
  final service = ref.read(novelServiceProvider);
  return service.loadDetailById(novelId);
});

/// Hasil memuat satu chapter: { htmlContent, updatedAt, publishedAt }.
/// Lazy: baru fetch saat chapter ini benar-benar dibuka (lihat ReaderPage),
/// hasilnya di-cache di NovelService sehingga tidak request ulang.
final chapterContentProvider =
    FutureProvider.family<ChapterContentResult, String>((ref, chapterUrl) async {
  final service = ref.read(novelServiceProvider);
  return service.loadChapterContent(chapterUrl);
});

/// Tanggal (updatedAt/publishedAt) SEMUA chapter di satu volume sekaligus,
/// key = daftar URL chapter (digabung jadi satu string supaya bisa dipakai
/// sebagai family key). Dipanggil saat VolumePage dibuka.
final chapterDatesBatchProvider =
    FutureProvider.family<Map<String, ChapterDates>, List<String>>((ref, urls) async {
  final service = ref.read(novelServiceProvider);
  return service.loadChapterDatesBatch(urls);
});

/// Search query state for Explore page.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Bookmark list, digabung dengan `updatedAt` TERBARU dari index API (bukan
/// snapshot lama di local storage), lalu diurutkan TERBARU -> TERLAMA —
/// sama seperti Explore. Jika index API belum pernah ter-load (mis. baru
/// buka app langsung ke tab Bookmark dalam keadaan offline), provider ini
/// akan memuat index terlebih dahulu; jika itu pun gagal, bookmark tetap
/// ditampilkan memakai snapshot `updatedAt` lokal sebagai fallback.
final bookmarkListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final prefs = ref.read(prefsServiceProvider);
  final service = ref.read(novelServiceProvider);
  final bookmarks = await prefs.getBookmarks();
  if (bookmarks.isEmpty) return bookmarks;

  // Pastikan index sudah ada supaya updatedAt-nya terbaru. Tidak masalah
  // kalau ini gagal (mis. offline) -> tetap lanjut pakai snapshot lokal.
  List<Novel>? index = service.cachedIndex;
  if (index == null) {
    try {
      index = await service.loadIndex();
    } catch (_) {
      index = null;
    }
  }

  final merged = bookmarks.map((b) {
    final id = b['id'] as String?;
    final fresh = id == null ? null : service.indexEntryFor(id);
    return {
      ...b,
      // updatedAt TERBARU dari server jika tersedia, kalau tidak pakai
      // snapshot yang disimpan saat bookmark dibuat.
      'updatedAt': fresh?.updatedAt?.toIso8601String() ?? b['updatedAt'],
    };
  }).toList();

  merged.sort((a, b) {
    final aDate = a['updatedAt'] as String?;
    final bDate = b['updatedAt'] as String?;
    final aTime = aDate != null ? (DateTime.tryParse(aDate)?.millisecondsSinceEpoch ?? 0) : 0;
    final bTime = bDate != null ? (DateTime.tryParse(bDate)?.millisecondsSinceEpoch ?? 0) : 0;
    return bTime.compareTo(aTime); // terbaru dulu
  });

  return merged;
});

/// Reader font size.
final fontSizeProvider = StateProvider<double>((ref) => 18.0);

/// Current bottom nav index.
final navIndexProvider = StateProvider<int>((ref) => 0);
