import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/novel_service.dart';
import '../services/prefs_service.dart';

final novelServiceProvider = Provider<NovelService>((ref) => NovelService());
final prefsServiceProvider = Provider<PrefsService>((ref) => PrefsService());

/// All novels (index/light entries) used in Explore page.
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

/// htmlContent satu chapter, key = URL chapter tersebut.
/// Lazy: baru fetch saat chapter ini benar-benar dibuka (lihat ReaderPage),
/// hasilnya di-cache di NovelService sehingga tidak request ulang.
final chapterContentProvider =
    FutureProvider.family<String, String>((ref, chapterUrl) async {
  final service = ref.read(novelServiceProvider);
  return service.loadChapterContent(chapterUrl);
});

/// Search query state for Explore page.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Bookmark list, refreshable.
final bookmarkListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final prefs = ref.read(prefsServiceProvider);
  return prefs.getBookmarks();
});

/// Reader font size.
final fontSizeProvider = StateProvider<double>((ref) => 18.0);

/// Current bottom nav index.
final navIndexProvider = StateProvider<int>((ref) => 0);
