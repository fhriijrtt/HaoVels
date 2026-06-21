/**
 * Scraper khusus KAITO NOVEL (zerokaito.blogspot.com) — axios + cheerio.
 *
 * MODE: EAGER + SCHEDULED CACHE.
 * Berbeda dari versi awal (lazy/on-demand), scraper ini SEKARANG berjalan
 * sendiri di background:
 *
 *   1. Saat proses start, langsung melakukan scrape penuh sekali (index +
 *      detail tiap novel), supaya saat app Flutter pertama kali memanggil
 *      /api/novels, data SUDAH SIAP di cache (tidak menunggu scrape).
 *   2. Setelah itu, scheduler berjalan tiap SCRAPE_INTERVAL_MS (default 15
 *      menit) untuk mengecek ulang seluruh list page. Untuk tiap novel,
 *      `dateModified` halaman novel dibandingkan dengan cache lama:
 *        - Jika SAMA  -> dilewati (tidak ada perubahan, hemat request).
 *        - Jika BEDA/baru -> detail novel (termasuk daftar chapter & volume)
 *          di-scrape ulang, sehingga chapter baru otomatis masuk ke cache.
 *   3. Endpoint /api/novels & /api/novels/:id HANYA membaca cache yang
 *      sudah ada (tidak memicu scrape baru) -> respons cepat ("satset").
 *      Pengecualian: jika novel benar-benar belum pernah ada di cache sama
 *      sekali (mis. baru ditambahkan sesaat sebelum index ter-refresh),
 *      /api/novels/:id akan fallback scrape sekali untuk novel itu saja.
 *
 *   GET /api/novels          -> index ringan (id, title, cover, author,
 *                               updatedAt), diurutkan TERBARU -> TERLAMA
 *                               berdasarkan updatedAt. Dipanggil saat
 *                               halaman Explore dibuka.
 *   GET /api/novels/:id      -> detail satu novel (synopsis, genres, author,
 *                               artist, updatedAt, daftar volume + cover
 *                               volume + daftar chapter per volume) — TANPA
 *                               isi/htmlContent chapter.
 *   GET /api/chapter?url=... -> isi HTML satu chapter + updatedAt/publishedAt
 *                               chapter tsb (dibersihkan lewat htmlCleaner).
 *                               Tetap LAZY: baru diambil saat chapter dibuka.
 *   POST /api/chapter-dates   -> body {urls:[...]}, balas tanggal
 *                               (updatedAt/publishedAt) BANYAK chapter
 *                               sekaligus tanpa htmlContent. Dipanggil saat
 *                               halaman Volume dibuka, supaya semua chapter
 *                               di volume itu langsung tampil keterangan
 *                               "terakhir update"-nya.
 *   GET /api/health           -> status scraper (kapan terakhir scan, jumlah
 *                               novel di cache, dll) — berguna untuk
 *                               memantau proses di Railway.
 *
 * Urutan chapter DI DALAM satu volume mengikuti urutan kemunculan pada
 * halaman sumber (tidak di-sort ulang), karena Flutter (flatChapters) hanya
 * mengandalkan urutan array untuk navigasi previous/next. Yang DIURUTKAN
 * ulang (terbaru -> terlama) hanya daftar NOVEL di /api/novels.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const { URL } = require('url');
const axios = require('axios');
const cheerio = require('cheerio');
const { extractChapterHtml } = require('./htmlCleaner');
const { extractDates } = require('./dateExtractor');

// ---------------------------------------------------------------------------
// KONFIGURASI
// ---------------------------------------------------------------------------

const BASE_URL = 'https://zerokaito.blogspot.com';

const LIST_PAGES = [
  `${BASE_URL}/p/on-going.html`,
  `${BASE_URL}/p/novel-tamat.html`,
];

const PORT = process.env.PORT || 3000;

// Interval scheduler: scrape ulang semua novel tiap 15 menit (lihat doc atas).
const SCRAPE_INTERVAL_MS = Number(process.env.SCRAPE_INTERVAL_MS) || 15 * 60 * 1000;

// Saat scheduler jalan, berapa banyak novel yang boleh di-scrape PARALEL
// sekaligus. Tidak unlimited supaya tetap "agak" sopan ke server Blogspot
// & tidak gampang kena rate-limit/blokir, tapi cukup cepat dibanding
// berurutan satu-satu.
const SCRAPE_CONCURRENCY = Number(process.env.SCRAPE_CONCURRENCY) || 5;

const REQUEST_DELAY_MS = 300; // jeda kecil antar 2 list page (on-going vs tamat)
const HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
};

const CONTENT_SELECTOR = '.post-body.entry-content';

// ---------------------------------------------------------------------------
// UTIL
// ---------------------------------------------------------------------------

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchHtml(url) {
  const res = await axios.get(url, { headers: HEADERS, timeout: 20000 });
  return res.data;
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

/** Hanya teks node langsung dari elemen (tidak termasuk teks anak-anaknya). */
function directText($, el) {
  return $(el)
    .contents()
    .filter(function () {
      return this.type === 'text';
    })
    .text()
    .trim();
}

/** Slug terakhir dari URL Blogspot, dipakai sebagai id novel. */
function slugFromUrl(url) {
  const clean = url.split('?')[0].split('#')[0];
  const parts = clean.split('/').filter(Boolean);
  const last = parts[parts.length - 1] || '';
  return last.replace(/\.html$/i, '');
}

/** Apakah href ini terlihat seperti halaman post Blogspot (novel/chapter)? */
function isPostUrl(href) {
  if (!href) return false;
  if (!href.includes('zerokaito.blogspot.com')) return false;
  if (!href.endsWith('.html')) return false;
  // halaman statis seperti /p/on-going.html bukan post novel
  if (href.includes('/p/')) return false;
  return true;
}

/**
 * Menjalankan banyak task async dengan batas concurrency, supaya tidak
 * menembak ratusan request ke Blogspot dalam satu waktu (Promise.all polos)
 * tapi juga tidak berurutan satu-satu (lambat).
 *
 * @param {Array} items - daftar item yang akan diproses.
 * @param {number} limit - maksimum task berjalan bersamaan.
 * @param {(item: any, index: number) => Promise<any>} worker
 */
async function runWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;

  async function runNext() {
    while (cursor < items.length) {
      const current = cursor;
      cursor += 1;
      try {
        results[current] = await worker(items[current], current);
      } catch (err) {
        results[current] = { __error: err };
      }
    }
  }

  const workers = Array.from({ length: Math.min(limit, items.length) }, runNext);
  await Promise.all(workers);
  return results;
}

// ---------------------------------------------------------------------------
// CACHE SEDERHANA (di memori + persist ke disk sebagai JSON)
// ---------------------------------------------------------------------------
//
// 3 "tabel" cache:
//   index.json    -> { entries: [{id,title,cover,author,updatedAt}] (sudah
//                      diurutkan terbaru->terlama), urlMap: {id: url},
//                      lastScrapedAt }
//   novels.json   -> { [id]: detailNovelTanpaHtmlContent (termasuk updatedAt) }
//   chapters.json -> { [chapterUrl]: { htmlContent, updatedAt, publishedAt } }
//
// Dibaca sekali saat server start, lalu di-update (dan ditulis ulang) setiap
// kali ada data baru/berubah yang berhasil di-scrape.

const CACHE_DIR = path.join(__dirname, 'cache');

function loadJsonCache(filename, fallback) {
  try {
    const file = path.join(CACHE_DIR, filename);
    if (fs.existsSync(file)) {
      return JSON.parse(fs.readFileSync(file, 'utf-8'));
    }
  } catch (err) {
    console.error(`[cache] Gagal membaca ${filename}: ${err.message}`);
  }
  return fallback;
}

function saveJsonCache(filename, data) {
  try {
    ensureDir(CACHE_DIR);
    fs.writeFileSync(path.join(CACHE_DIR, filename), JSON.stringify(data, null, 2), 'utf-8');
  } catch (err) {
    console.error(`[cache] Gagal menyimpan ${filename}: ${err.message}`);
  }
}

// index.json sekarang juga punya `lastScrapedAt` di root, dan tiap entry
// punya `updatedAt`. null = belum pernah ada cache sama sekali (proses baru
// pertama kali start dan belum sempat scrape).
let indexCache = loadJsonCache('index.json', null);
const novelCache = loadJsonCache('novels.json', {});
const chapterCache = loadJsonCache('chapters.json', {});

// Status untuk /api/health
const scraperStatus = {
  isScraping: false,
  lastScrapeStartedAt: null,
  lastScrapeFinishedAt: null,
  lastScrapeError: null,
};

// ---------------------------------------------------------------------------
// 1. EXPLORE — index ringan (title, cover, author, updatedAt, id) dari
//    halaman daftar
// ---------------------------------------------------------------------------

/**
 * Mem-parsing satu halaman daftar (on-going / tamat) menjadi entry ringan.
 * Setiap entry novel pada halaman daftar biasanya berupa: link judul,
 * thumbnail cover di dekatnya, dan kadang baris "Author: ...". Parser ini
 * mengelompokkan ketiganya berdasarkan novel (id) yang sama.
 */
function parseListPage(html) {
  const $ = cheerio.load(html);
  const content = $(CONTENT_SELECTOR).first();
  const map = new Map(); // id -> { id, title, cover, author, url }

  function entryFor(url) {
    const id = slugFromUrl(url);
    if (!map.has(id)) {
      map.set(id, { id, title: '', cover: '', author: '', url });
    }
    return map.get(id);
  }

  content.find('*').each((_, el) => {
    const $el = $(el);
    const tag = el.tagName ? el.tagName.toLowerCase() : '';

    // --- Link ke halaman novel -> judul --------------------------------
    if (tag === 'a') {
      const href = $el.attr('href');
      if (!isPostUrl(href)) return;
      const url = href.split('?')[0].split('#')[0];
      const title = $el.text().trim();
      const entry = entryFor(url);
      if (title && !entry.title) entry.title = title;
      return;
    }

    // --- Gambar di dalam/dekat link novel -> cover ----------------------
    if (tag === 'img') {
      const parentLink = $el.closest('a[href]');
      const href = parentLink.attr('href');
      if (!isPostUrl(href)) return;
      const url = href.split('?')[0].split('#')[0];
      const src = $el.attr('src') || $el.attr('data-src') || '';
      if (!src) return;
      const entry = entryFor(url);
      if (!entry.cover) entry.cover = src;
      return;
    }

    // --- Baris "Author: ..." / "Penulis: ..." di dekat entry terakhir --
    if (['p', 'div', 'span', 'li'].includes(tag)) {
      const txt = directText($, el);
      const match = txt.match(/^(author|penulis)\s*:\s*(.+)$/i);
      if (!match) return;
      const lastEntry = Array.from(map.values()).pop();
      if (lastEntry && !lastEntry.author) lastEntry.author = match[2].trim();
    }
  });

  return Array.from(map.values());
}

/** Mengambil & menggabungkan entry novel dari SEMUA halaman daftar. */
async function scrapeListPages() {
  const merged = new Map();

  for (const listUrl of LIST_PAGES) {
    console.log(`[list] Mengambil daftar novel: ${listUrl}`);
    const html = await fetchHtml(listUrl);
    const entries = parseListPage(html);

    entries.forEach((entry) => {
      const existing = merged.get(entry.id);
      if (!existing) {
        merged.set(entry.id, entry);
      } else {
        if (!existing.cover && entry.cover) existing.cover = entry.cover;
        if (!existing.author && entry.author) existing.author = entry.author;
      }
    });

    await sleep(REQUEST_DELAY_MS);
  }

  return Array.from(merged.values());
}

/** Mengurutkan entry index terbaru -> terlama berdasarkan updatedAt (ISO string). */
function sortEntriesByUpdatedAtDesc(entries) {
  return [...entries].sort((a, b) => {
    const aTime = a.updatedAt ? new Date(a.updatedAt).getTime() : 0;
    const bTime = b.updatedAt ? new Date(b.updatedAt).getTime() : 0;
    return bTime - aTime; // terbaru dulu
  });
}

// ---------------------------------------------------------------------------
// 2. DETAIL NOVEL — synopsis, genres, author, artist, volume, cover volume,
//    updatedAt, dan daftar chapter per volume (TANPA isi/htmlContent chapter)
// ---------------------------------------------------------------------------

/**
 * Mem-parsing satu halaman novel Kaito Novel.
 * Mengembalikan metadata novel + struktur volume->chapter. Tiap chapter
 * hanya berisi {title, url, order} — isi (htmlContent) BELUM diambil di
 * sini, baru diambil saat chapter itu sendiri dibuka (lihat getChapterContent).
 */
function parseNovelPage(html, novelUrl) {
  const { updatedAt, publishedAt } = extractDates(html);

  const $ = cheerio.load(html);
  const content = $(CONTENT_SELECTOR).first();

  const title =
    $('h1.entry-title').first().text().trim() ||
    $('h3.post-title.entry-title').first().text().trim() ||
    $('meta[property="og:title"]').attr('content') ||
    '';

  // Field metadata yang dicari berdasarkan label umum di body novel.
  let author = '';
  let artist = '';
  let genres = [];
  let synopsisParts = [];
  let mainCover = '';

  let volumes = [];
  let currentVolume = null;
  let beforeFirstVolume = true; // dipakai untuk membedakan cover utama vs sinopsis
  let synopsisStarted = false;

  const LABEL_PATTERNS = {
    author: /^(author\(s\)|author|penulis)\s*:\s*/i,
    artist: /^(artist\(s\)|artist|illustrator)\s*:\s*/i,
    genre: /^(genre|genres)\s*:\s*/i,
    synopsis: /^(synopsis|sinopsis)\s*:\s*/i,
  };

  // Walk seluruh elemen `.post-body.entry-content` secara document-order.
  content.find('*').each((_, el) => {
    const $el = $(el);
    const tag = el.tagName ? el.tagName.toLowerCase() : '';

    // --- Deteksi marker "Volume xx" -------------------------------------
    if (['p', 'div', 'span', 'b', 'strong', 'h3', 'h4', 'li'].includes(tag)) {
      const txt = directText($, el) || $el.text().trim();
      if (/^volume\s*\d+/i.test(txt)) {
        const match = txt.match(/volume\s*0*(\d+)/i);
        const number = match ? parseInt(match[1], 10) : volumes.length + 1;
        currentVolume = {
          number,
          name: txt.trim() || `Volume ${number}`,
          cover: '',
          chapters: [],
        };
        volumes.push(currentVolume);
        beforeFirstVolume = false;
        return; // marker volume bukan chapter/cover, lanjut elemen berikutnya
      }
    }

    // --- Metadata berlabel (Author:, Artist:, Genre:, Synopsis:) --------
    if (beforeFirstVolume && ['p', 'div', 'span'].includes(tag)) {
      const txt = $el.text().trim();

      if (LABEL_PATTERNS.author.test(txt)) {
        author = txt.replace(LABEL_PATTERNS.author, '').trim();
        return;
      }
      if (LABEL_PATTERNS.artist.test(txt)) {
        artist = txt.replace(LABEL_PATTERNS.artist, '').trim();
        return;
      }
      if (LABEL_PATTERNS.genre.test(txt)) {
        genres = txt
          .replace(LABEL_PATTERNS.genre, '')
          .split(/[,|·]/)
          .map((g) => g.trim())
          .filter(Boolean);
        return;
      }
      if (LABEL_PATTERNS.synopsis.test(txt)) {
        synopsisStarted = true;
        const rest = txt.replace(LABEL_PATTERNS.synopsis, '').trim();
        if (rest) synopsisParts.push(rest);
        return;
      }
      // Paragraf teks biasa sebelum volume pertama & setelah label sinopsis
      // ditemukan -> dianggap bagian dari sinopsis.
      if (synopsisStarted && tag === 'p' && txt) {
        synopsisParts.push(txt);
      }
    }

    // --- Gambar: cover utama (sebelum volume pertama) atau cover volume -
    if (tag === 'img') {
      const src = $el.attr('src') || $el.attr('data-src') || '';
      if (!src) return;

      if (beforeFirstVolume) {
        if (!mainCover) mainCover = src;
        return;
      }
      if (currentVolume && !currentVolume.cover && currentVolume.chapters.length === 0) {
        currentVolume.cover = src;
      }
      return;
    }

    // --- Link chapter di bawah volume yang sedang aktif -----------------
    if (tag === 'a') {
      const href = $el.attr('href');
      const linkText = $el.text().trim();
      if (!href || !linkText) return;
      if (!currentVolume) return; // link sebelum volume pertama (mis. navigasi) -> abaikan

      currentVolume.chapters.push({
        title: linkText,
        url: href.split('?')[0].split('#')[0],
        order: currentVolume.chapters.length,
      });
    }
  });

  const id = slugFromUrl(novelUrl);

  return {
    id,
    title,
    cover: mainCover,
    author,
    artist,
    genres,
    synopsis: synopsisParts.join('\n\n').trim(),
    volumes,
    updatedAt,
    publishedAt,
  };
}

/**
 * Scrape detail satu novel langsung dari sumber (tanpa cek cache).
 * Dipakai oleh scheduler maupun fallback lazy.
 */
async function scrapeNovelDetail(novelUrl) {
  console.log(`[novel] Scraping detail: ${novelUrl}`);
  const html = await fetchHtml(novelUrl);
  return parseNovelPage(html, novelUrl);
}

/**
 * Fallback lazy: dipanggil dari endpoint /api/novels/:id ketika novel
 * BENAR-BENAR belum ada di cache sama sekali (mis. baru muncul di list page
 * tapi scheduler belum sempat memprosesnya). Hasilnya langsung disimpan ke
 * cache supaya request berikutnya tidak perlu scrape ulang.
 */
const novelDetailPromises = new Map();
async function getNovelDetailWithFallback(id) {
  if (novelCache[id]) return novelCache[id];
  if (novelDetailPromises.has(id)) return novelDetailPromises.get(id);

  const promise = (async () => {
    if (!indexCache || !indexCache.urlMap[id]) return null;
    const novelUrl = indexCache.urlMap[id];

    const detail = await scrapeNovelDetail(novelUrl);
    novelCache[id] = detail;
    saveJsonCache('novels.json', novelCache);
    return detail;
  })().finally(() => {
    novelDetailPromises.delete(id);
  });

  novelDetailPromises.set(id, promise);
  return promise;
}

// ---------------------------------------------------------------------------
// 3. ISI CHAPTER — tetap LAZY, baru diambil & dibersihkan (htmlCleaner) saat
//    chapter benar-benar dibuka oleh user. Sekalian mengembalikan tanggal
//    update/publish chapter itu untuk ditampilkan di UI.
// ---------------------------------------------------------------------------

const chapterPromises = new Map();
async function getChapterContent(chapterUrl) {
  if (Object.prototype.hasOwnProperty.call(chapterCache, chapterUrl)) {
    return chapterCache[chapterUrl];
  }
  if (chapterPromises.has(chapterUrl)) return chapterPromises.get(chapterUrl);

  const promise = (async () => {
    console.log(`[chapter] Mengambil isi: ${chapterUrl}`);
    const html = await fetchHtml(chapterUrl);
    const result = extractChapterHtml(html); // { htmlContent, updatedAt, publishedAt }

    chapterCache[chapterUrl] = result;
    saveJsonCache('chapters.json', chapterCache);
    return result;
  })().finally(() => {
    chapterPromises.delete(chapterUrl);
  });

  chapterPromises.set(chapterUrl, promise);
  return promise;
}

/**
 * Ambil HANYA tanggal (updatedAt/publishedAt) untuk SEKUMPULAN chapter
 * sekaligus — dipakai saat halaman Volume dibuka di Flutter, supaya semua
 * chapter di volume itu bisa langsung menampilkan keterangan "terakhir
 * update" tanpa user harus membuka satu-satu.
 *
 * - Chapter yang SUDAH ada di chapterCache (pernah dibuka sebelumnya)
 *   langsung dipakai dari cache, TANPA request baru sama sekali.
 * - Chapter yang belum ada di cache di-fetch paralel (dibatasi
 *   SCRAPE_CONCURRENCY) — TAPI tidak memakai htmlCleaner (kita tidak butuh
 *   htmlContent di sini), hanya extractDates dari HTML mentah. Hasilnya
 *   TIDAK ditulis ke chapterCache (karena tidak punya htmlContent lengkap),
 *   supaya saat chapter itu nanti benar-benar dibuka, getChapterContent
 *   tetap mengambil & membersihkan HTML penuh seperti biasa.
 *
 * @param {string[]} chapterUrls
 * @returns {Promise<Record<string, {updatedAt: string|null, publishedAt: string|null}>>}
 */
async function getChapterDatesBatch(chapterUrls) {
  const result = {};
  const needFetch = [];

  for (const url of chapterUrls) {
    if (Object.prototype.hasOwnProperty.call(chapterCache, url)) {
      const cached = chapterCache[url];
      result[url] = { updatedAt: cached.updatedAt, publishedAt: cached.publishedAt };
    } else {
      needFetch.push(url);
    }
  }

  if (needFetch.length > 0) {
    console.log(`[chapter-dates] Mengambil tanggal ${needFetch.length} chapter (paralel)...`);
    await runWithConcurrency(needFetch, SCRAPE_CONCURRENCY, async (url) => {
      try {
        const html = await fetchHtml(url);
        result[url] = extractDates(html);
      } catch (err) {
        console.error(`[chapter-dates] Gagal mengambil tanggal ${url}: ${err.message}`);
        result[url] = { updatedAt: null, publishedAt: null };
      }
    });
  }

  return result;
}

// ---------------------------------------------------------------------------
// 4. SCHEDULER — scrape penuh berkala (index + detail novel yang berubah)
// ---------------------------------------------------------------------------

/**
 * Satu siklus penuh scraping:
 *   1. Ambil semua list page -> dapat daftar novel + URL-nya.
 *   2. Untuk tiap novel, scrape detail (paralel, dibatasi concurrency).
 *      - Kalau novel SUDAH ada di cache DAN updatedAt halaman novel SAMA
 *        dengan cache lama -> data lama dipertahankan (hemat penulisan).
 *      - Kalau BEDA (atau novel baru) -> cache ditimpa dengan detail baru,
 *        sehingga chapter baru otomatis ikut masuk.
 *   3. Bangun ulang index.json dari novelCache, urutkan terbaru->terlama,
 *      lalu simpan ke disk.
 *
 * Dipanggil sekali saat start, lalu diulang tiap SCRAPE_INTERVAL_MS oleh
 * setInterval di bagian bawah file ini.
 */
async function runFullScrapeCycle() {
  if (scraperStatus.isScraping) {
    console.log('[scheduler] Scrape sebelumnya masih berjalan, lewati siklus ini.');
    return;
  }

  scraperStatus.isScraping = true;
  scraperStatus.lastScrapeStartedAt = new Date().toISOString();
  scraperStatus.lastScrapeError = null;

  try {
    console.log('[scheduler] Mulai siklus scraping penuh...');
    const listEntries = await scrapeListPages(); // [{id, title, cover, author, url}]

    let changedCount = 0;
    let skippedCount = 0;

    await runWithConcurrency(listEntries, SCRAPE_CONCURRENCY, async (entry) => {
      const cached = novelCache[entry.id];

      let detail;
      try {
        detail = await scrapeNovelDetail(entry.url);
      } catch (err) {
        console.error(`[scheduler] Gagal scrape "${entry.title || entry.id}": ${err.message}`);
        // Kalau gagal & sebelumnya sudah ada cache, pertahankan cache lama
        // supaya app tidak kehilangan data hanya karena 1x gagal fetch.
        if (cached) skippedCount += 1;
        return;
      }

      const isNew = !cached;
      const isChanged = cached && cached.updatedAt !== detail.updatedAt;

      if (isNew || isChanged) {
        novelCache[entry.id] = detail;
        changedCount += 1;
        console.log(
          `[scheduler] ${isNew ? 'Novel baru' : 'Update terdeteksi'}: ${detail.title || entry.id}`
        );
      } else {
        skippedCount += 1;
      }
    });

    saveJsonCache('novels.json', novelCache);

    // Bangun ulang index ringan dari novelCache (sumber kebenaran utama),
    // supaya cover/author/title/updatedAt selalu sinkron dengan detail.
    const urlMap = {};
    const entries = listEntries.map((listEntry) => {
      urlMap[listEntry.id] = listEntry.url;
      const detail = novelCache[listEntry.id];
      return {
        id: listEntry.id,
        title: (detail && detail.title) || listEntry.title,
        cover: (detail && detail.cover) || listEntry.cover,
        author: (detail && detail.author) || listEntry.author,
        updatedAt: (detail && detail.updatedAt) || null,
      };
    });

    indexCache = {
      entries: sortEntriesByUpdatedAtDesc(entries),
      urlMap,
      lastScrapedAt: new Date().toISOString(),
    };
    saveJsonCache('index.json', indexCache);

    scraperStatus.lastScrapeFinishedAt = indexCache.lastScrapedAt;
    console.log(
      `[scheduler] Siklus selesai. ${changedCount} novel diperbarui, ${skippedCount} tidak berubah, total ${entries.length} novel.`
    );
  } catch (err) {
    scraperStatus.lastScrapeError = err.message;
    console.error(`[scheduler] Siklus scraping gagal: ${err.message}`);
  } finally {
    scraperStatus.isScraping = false;
  }
}

// ---------------------------------------------------------------------------
// SERVER HTTP — endpoint dipanggil dari app Flutter
// ---------------------------------------------------------------------------

function sendJson(res, status, data) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': '*',
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': '*',
    });
    return res.end();
  }

  const requestUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = requestUrl.pathname;

  try {
    // GET /api/novels -> index ringan, langsung dari cache (sudah terurut
    // terbaru->terlama). TIDAK memicu scrape baru -> respons cepat.
    if (pathname === '/api/novels' && req.method === 'GET') {
      if (!indexCache) {
        // Proses baru saja start & scrape pertama belum selesai sama sekali.
        return sendJson(res, 503, {
          error: 'Data belum siap, scraper sedang melakukan scrape awal. Coba lagi sebentar lagi.',
        });
      }
      return sendJson(res, 200, indexCache.entries);
    }

    // GET /api/novels/:id -> detail novel dari cache (di-refresh scheduler).
    // Fallback lazy-scrape hanya jika novel belum pernah ada di cache sama sekali.
    const detailMatch = pathname.match(/^\/api\/novels\/([^/]+)$/);
    if (detailMatch && req.method === 'GET') {
      const id = decodeURIComponent(detailMatch[1]);
      const detail = novelCache[id] || (await getNovelDetailWithFallback(id));
      if (!detail) return sendJson(res, 404, { error: 'Novel tidak ditemukan' });
      return sendJson(res, 200, detail);
    }

    // GET /api/chapter?url=... -> isi chapter + updatedAt/publishedAt
    // (tetap lazy, dibuka saat user membuka chapter).
    if (pathname === '/api/chapter' && req.method === 'GET') {
      const chapterUrl = requestUrl.searchParams.get('url');
      if (!chapterUrl) {
        return sendJson(res, 400, { error: 'Parameter "url" wajib diisi' });
      }
      const result = await getChapterContent(chapterUrl); // { htmlContent, updatedAt, publishedAt }
      return sendJson(res, 200, result);
    }

    // POST /api/chapter-dates -> tanggal (updatedAt/publishedAt) untuk BANYAK
    // chapter sekaligus. Body: { "urls": ["...", "...", ...] }.
    // Dipanggil saat halaman Volume dibuka, supaya semua chapter di volume
    // itu bisa langsung menampilkan keterangan "terakhir update".
    if (pathname === '/api/chapter-dates' && req.method === 'POST') {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      let body;
      try {
        body = JSON.parse(Buffer.concat(chunks).toString('utf-8') || '{}');
      } catch (err) {
        return sendJson(res, 400, { error: 'Body harus berupa JSON valid' });
      }

      const urls = Array.isArray(body.urls) ? body.urls.filter((u) => typeof u === 'string') : [];
      if (urls.length === 0) {
        return sendJson(res, 400, { error: 'Field "urls" wajib diisi dan berupa array string' });
      }

      const dates = await getChapterDatesBatch(urls);
      return sendJson(res, 200, dates);
    }

    // GET /api/health -> status scraper, berguna untuk memantau di Railway.
    if (pathname === '/api/health' && req.method === 'GET') {
      return sendJson(res, 200, {
        ok: true,
        novelCount: indexCache ? indexCache.entries.length : 0,
        lastScrapedAt: indexCache ? indexCache.lastScrapedAt : null,
        isScraping: scraperStatus.isScraping,
        lastScrapeStartedAt: scraperStatus.lastScrapeStartedAt,
        lastScrapeFinishedAt: scraperStatus.lastScrapeFinishedAt,
        lastScrapeError: scraperStatus.lastScrapeError,
        scrapeIntervalMs: SCRAPE_INTERVAL_MS,
      });
    }

    return sendJson(res, 404, { error: 'Endpoint tidak ditemukan' });
  } catch (err) {
    console.error('[error]', err.message);
    return sendJson(res, 500, { error: err.message });
  }
});

server.listen(PORT, () => {
  console.log(`[scraper] Server berjalan di http://localhost:${PORT}`);
  console.log('Endpoint:');
  console.log('  GET /api/novels            -> index ringan, terurut terbaru->terlama (dari cache)');
  console.log('  GET /api/novels/:id        -> detail novel (dari cache, fallback lazy jika belum ada)');
  console.log('  GET /api/chapter?url=...   -> htmlContent + updatedAt/publishedAt chapter (lazy)');
  console.log('  POST /api/chapter-dates    -> tanggal banyak chapter sekaligus (untuk halaman Volume)');
  console.log('  GET /api/health            -> status scraper');
  console.log(`Cache disimpan di: ${CACHE_DIR}`);
  console.log(`Interval scrape otomatis: ${Math.round(SCRAPE_INTERVAL_MS / 60000)} menit, concurrency: ${SCRAPE_CONCURRENCY}`);

  // Scrape penuh pertama langsung saat start, supaya data sudah siap
  // sebelum request pertama dari app datang.
  runFullScrapeCycle();

  // Lalu ulangi tiap SCRAPE_INTERVAL_MS untuk mendeteksi novel/chapter baru.
  setInterval(runFullScrapeCycle, SCRAPE_INTERVAL_MS);
});
