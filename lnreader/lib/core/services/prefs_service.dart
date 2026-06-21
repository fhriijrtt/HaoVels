import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores bookmarks and "continue reading" progress on-device.
/// No backend involved — pure local persistence.
class PrefsService {
  static const _bookmarkKey = 'bookmarks_v1';
  static const _progressKey = 'progress_v1';

  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_bookmarkKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<bool> isBookmarked(String novelId) async {
    final list = await getBookmarks();
    return list.any((e) => e['id'] == novelId);
  }

  /// [updatedAt] (ISO 8601 string, opsional) disimpan sebagai SNAPSHOT
  /// terakhir diketahui dari `Novel.updatedAt` saat bookmark dibuat. Ini
  /// hanya FALLBACK untuk sorting saat index API belum sempat di-load (mis.
  /// offline) — begitu index API tersedia, BookmarkPage selalu memakai
  /// updatedAt TERBARU dari server, bukan snapshot ini.
  Future<void> toggleBookmark({
    required String id,
    required String title,
    required String cover,
    String? updatedAt,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final list = await getBookmarks();
    final exists = list.indexWhere((e) => e['id'] == id);
    if (exists >= 0) {
      list.removeAt(exists);
    } else {
      list.add({
        'id': id,
        'title': title,
        'cover': cover,
        'updatedAt': updatedAt,
      });
    }
    await sp.setString(_bookmarkKey, jsonEncode(list));
  }

  /// progress map: novelId -> {volumeNumber, chapterOrder, chapterTitle, novelTitle, cover}
  Future<Map<String, dynamic>> getAllProgress() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_progressKey);
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> getProgress(String novelId) async {
    final all = await getAllProgress();
    return all[novelId] as Map<String, dynamic>?;
  }

  Future<void> saveProgress({
    required String novelId,
    required String novelTitle,
    required String cover,
    required int volumeNumber,
    required String volumeName,
    required int chapterOrder,
    required String chapterTitle,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final all = await getAllProgress();
    all[novelId] = {
      'novelId': novelId,
      'novelTitle': novelTitle,
      'cover': cover,
      'volumeNumber': volumeNumber,
      'volumeName': volumeName,
      'chapterOrder': chapterOrder,
      'chapterTitle': chapterTitle,
    };
    await sp.setString(_progressKey, jsonEncode(all));
  }

  /// Font size preference for the reader (Georgia family, adjustable size)
  Future<double> getFontSize() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble('reader_font_size') ?? 18.0;
  }

  Future<void> setFontSize(double size) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('reader_font_size', size);
  }
}
