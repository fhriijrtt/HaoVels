# LN Reader

Aplikasi pembaca Light Novel berbasis Flutter (Web + Android), tanpa backend — seluruh data berasal dari file JSON hasil scraping.

## Struktur Proyek

```
lnreader/              -> Flutter app
  lib/
    core/
      models/models.dart        (Novel, Volume, Chapter)
      services/novel_service.dart   (load JSON dari assets)
      services/prefs_service.dart   (bookmark, progress, font size via shared_preferences)
      providers/providers.dart      (Riverpod providers)
      theme/app_theme.dart           (Material 3 dark theme)
    pages/
      explore/explore_page.dart
      novel_detail/novel_detail_page.dart
      volume/volume_page.dart
      reader/reader_page.dart
      bookmark/bookmark_page.dart
      placeholder_pages.dart    (Home & Account - belum aktif)
    widgets/
      novel_card.dart
      volume_card.dart
      chapter_tile.dart
      bottom_navbar.dart
    app_router.dart      (go_router)
    main.dart
  assets/
    data/novels.json     (index seluruh novel)
    novels/*.json         (detail tiap novel: volume + chapter)

scraper/               -> Scraper Node.js (axios + cheerio)
  index.js
  htmlCleaner.js
  package.json
```

## Menjalankan Flutter App

```bash
cd lnreader
flutter pub get
flutter run -d chrome      # untuk Web
flutter build apk          # untuk Android APK (di masa depan)
```

## Cara Kerja Data

- `assets/data/novels.json` = index ringan (id, title, alias, cover, author, genres, dataPath) — dipakai di halaman Explore & search.
- `assets/novels/<id>.json` = detail penuh novel (author, artist, genre, sinopsis, daftar volume & chapter dengan `htmlContent`) — di-load lazy saat user membuka detail novel (`novelDetailProvider`).
- Tidak ada backend/API — semua dibaca dari `rootBundle` (assets) lewat `NovelService`.

## Model Data

```dart
class Novel {
  String id, title, author, artist, synopsis, cover;
  List<String> alias, genres;
  List<Volume> volumes;
}

class Volume {
  int number;
  String name, cover;
  List<Chapter> chapters;
}

class Chapter {
  String title, htmlContent;
  int order; // urutan chapter di dalam volume, sesuai sumber asli
}
```

## Navigasi Chapter (Previous/Next)

`Novel.flatChapters` meratakan SEMUA chapter dari SEMUA volume menjadi satu list linear,
diurutkan berdasarkan `volume.number` lalu `chapter.order`. Reader page mencari index chapter
saat ini di list tersebut, sehingga:

- Di akhir Volume 2 ("Kata Penutup") -> Next otomatis lompat ke Volume 3 "Ilustrasi".
- Previous/Next murni berdasarkan posisi pada list gabungan, bukan per-volume.

## Reader

- Menggunakan `flutter_html` untuk merender HTML chapter (paragraf, bold, italic, alignment via `style="text-align:..."`, `<br>`).
- `<img>` di-render ulang via `cached_network_image` (custom `HtmlExtension`) supaya ilustrasi di dalam chapter tampil dengan caching yang baik di Web & Android.
- Font: Georgia, ukuran dapat diubah (+/- pada AppBar), disimpan di `shared_preferences`.

## Bookmark & Continue Reading

- `PrefsService` (shared_preferences) menyimpan:
  - Daftar bookmark (id, title, cover).
  - Progress per novel (volume, chapter, judul chapter terakhir dibaca) — disimpan otomatis tiap kali ReaderPage dibuka.

## Search (Explore)

Search bar di Explore memfilter berdasarkan `title`, `alias`, dan `author` (case-insensitive, di sisi client karena tidak ada backend).

## Bottom Navigation

4 menu: Home (nonaktif), Explore (aktif), Bookmark (aktif), Account (nonaktif).
Menekan Home/Account menampilkan snackbar "Segera hadir". Navbar selalu tampil via `Scaffold.bottomNavigationBar` di tiap halaman utama.

## State Management

Riverpod (`flutter_riverpod`) — providers di `lib/core/providers/providers.dart`:
- `novelIndexProvider` — daftar novel (Explore)
- `novelDetailProvider(id)` — detail + volume/chapter (lazy load & cache)
- `bookmarkListProvider` — daftar bookmark
- `searchQueryProvider`, `fontSizeProvider`, `navIndexProvider`

## Catatan Penting

1. **`flutter_html` versi**: proyek ini menggunakan `flutter_html: ^3.0.0-beta.2`. API `HtmlExtension` di `reader_page.dart` mengikuti versi tersebut — jika Anda memutuskan memakai versi stable yang berbeda, sesuaikan signature `HtmlExtension`/`ExtensionContext` sesuai dokumentasi versi yang dipasang (`flutter pub get` lalu cek breaking changes).
2. **URL gambar contoh** (`example.com`) di `assets/data/novels.json` & `assets/novels/roshidere.json` adalah placeholder — ganti dengan URL asli hasil scraping, atau host gambar Anda sendiri.
3. **Selector scraper** (`.post-body.entry-content`, `.novel-cover`, `.chapter-list`, dll) di `scraper/index.js` adalah placeholder yang harus disesuaikan dengan markup HTML situs sumber yang sebenarnya — lihat komentar di file tersebut.

## Scraper (Node.js)

```bash
cd scraper
npm install
# edit SOURCES & selector di index.js sesuai situs sumber
npm run scrape
```

Output:
```
scraper/output/novels.json
scraper/output/novels/<id>.json
```

Salin isi `output/novels.json` -> `lnreader/assets/data/novels.json`
dan isi `output/novels/*.json` -> `lnreader/assets/novels/`.

### Pembersihan HTML Chapter (`htmlCleaner.js`)

- Mengambil konten dari selector `.post-body.entry-content`.
- Mempertahankan tag: `p`, `div`, `img`, `b`, `i`, `span`, `br` (juga `strong`/`em`).
- Menghapus: `script`, `iframe`, `style`, elemen iklan (`.adsbygoogle`, `[class*="ads"]`, dll), widget blogger, dan section komentar.
- Mempertahankan atribut `src` pada `<img>` dan properti `text-align` pada `style` (untuk alignment), atribut lain dibuang.
