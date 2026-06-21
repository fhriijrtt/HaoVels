/**
 * Scraper khusus KAITO NOVEL (zerokaito.blogspot.com) — axios + cheerio.
 *
 * MODE: LAZY SCRAPING (on-demand, lewat HTTP server lokal).
 * Scraper ini TIDAK LAGI menjalankan satu batch besar yang mengambil semua
 * novel + semua chapter sekaligus. Sebagai gantinya, ia berjalan sebagai
 * server HTTP kecil yang hanya men-scrape sesuatu ketika benar-benar
 * dibutuhkan oleh app Flutter:
 *
 *   GET /api/novels          -> index ringan (id, title, cover, author) dari
 *                               halaman daftar on-going + tamat. Dipanggil
 *                               saat halaman Explore dibuka.
 *   GET /api/novels/:id      -> detail satu novel (synopsis, genres, author,
 *                               artist, daftar volume + cover volume + daftar
 *                               chapter per volume) — TANPA isi/htmlContent
 *                               chapter. Dipanggil saat user membuka detail
 *                               novel tersebut.
 *   GET /api/chapter?url=... -> isi HTML satu chapter (dibersihkan lewat
 *                               htmlCleaner). Dipanggil saat user membuka
 *                               chapter tersebut.
 *
 * Hasil tiap endpoint disimpan ke cache sederhana (lihat bagian CACHE) agar
 * novel/chapter yang sudah pernah diambil tidak perlu di-request ulang ke
 * Blogspot setiap saat — cache dipegang di memori dan juga ditulis ke disk
 * (folder cache/) supaya tetap ada walau server di-restart.
 *
 * Karena Kaito Novel adalah blog Blogspot tanpa elemen semantik khusus
 * (tidak ada <div class="volume">, <div class="chapter-list">, dst),
 * parser di bawah membaca konten `.post-body.entry-content` secara LINEAR
 * (document order) dan mengklasifikasikan setiap elemen. Selector di bawah
 * adalah pendekatan umum untuk halaman blog seperti ini — sesuaikan jika
 * markup situs sumber sebenarnya sedikit berbeda.
 *
 * Urutan chapter & volume MENGIKUTI urutan kemunculan pada halaman sumber
 * (tidak di-sort ulang), karena Flutter (flatChapters) hanya mengandalkan
 * urutan array untuk navigasi previous/next.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const { URL } = require('url');
const axios = require('axios');
const cheerio = require('cheerio');
const { extractChapterHtml } = require('./htmlCleaner');

// ---------------------------------------------------------------------------
// KONFIGURASI
// ---------------------------------------------------------------------------

const BASE_URL = 'https://zerokaito.blogspot.com';

const LIST_PAGES = [
  `${BASE_URL}/p/on-going.html`,
  `${BASE_URL}/p/novel-tamat.html`,
];

const PORT = process.env.PORT || 3000;
const REQUEST_DELAY_MS = 800; // sopan terhadap server Blogspot (dipakai antar 2 list page saja)
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

// ---------------------------------------------------------------------------
// CACHE SEDERHANA (di memori + persist ke disk sebagai JSON)
// ---------------------------------------------------------------------------
//
// 3 "tabel" cache:
//   index.json    -> { entries: [{id,title,cover,author}], urlMap: {id: url} }
//   novels.json   -> { [id]: detailNovelTanpaHtmlContent }
//   chapters.json -> { [chapterUrl]: htmlContent }
//
// Dibaca sekali saat server start, lalu di-update (dan ditulis ulang) setiap
// kali ada data baru yang berhasil di-scrape.

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

let indexCache = loadJsonCache('index.json', null); // null = belum pernah di-scrape
const novelCache = loadJsonCache('novels.json', {});
const chapterCache = loadJsonCache('chapters.json', {});

// ---------------------------------------------------------------------------
// 1. EXPLORE — index ringan (title, cover, author, id) dari halaman daftar
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

/**
 * Index ringan untuk Explore — lazy: hanya di-scrape sekali (request pertama),
 * lalu dipakai dari cache untuk request-request berikutnya.
 * `indexPromise` mencegah scrape ganda jika ada 2 request datang bersamaan
 * sebelum scrape pertama selesai (masih bagian dari "tidak request ulang").
 */
let indexPromise = null;
async function getNovelIndex() {
  if (indexCache) return indexCache;
  if (!indexPromise) {
    indexPromise = (async () => {
      const rawEntries = await scrapeListPages();
      const urlMap = {};
      const entries = rawEntries.map(({ id, title, cover, author, url }) => {
        urlMap[id] = url;
        return { id, title, cover, author };
      });
      indexCache = { entries, urlMap };
      saveJsonCache('index.json', indexCache);
      return indexCache;
    })().finally(() => {
      indexPromise = null;
    });
  }
  return indexPromise;
}

// ---------------------------------------------------------------------------
// 2. DETAIL NOVEL — synopsis, genres, author, artist, volume, cover volume,
//    dan daftar chapter per volume (TANPA isi/htmlContent chapter)
// ---------------------------------------------------------------------------

/**
 * Mem-parsing satu halaman novel Kaito Novel.
 * Mengembalikan metadata novel + struktur volume->chapter. Tiap chapter
 * hanya berisi {title, url, order} — isi (htmlContent) BELUM diambil di
 * sini, baru diambil saat chapter itu sendiri dibuka (lihat getChapterContent).
 */
function parseNovelPage(html, novelUrl) {
  const $ = cheerio.load(html);
  const content = $(CONTENT_SELECTOR).first();

  const title =
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
    author: /^(author|penulis)\s*:\s*/i,
    artist: /^(artist|illustrator)\s*:\s*/i,
    genre: /^(genre|genres)\s*:\s*/i,
    synopsis: /^(synopsis|sinopsis)\s*:\s*/i,
  };

  // Walk seluruh elemen `.post-body.entry-content` secara document-order.
  content.find('*').each((_, el) => {
    const $el = $(el);
    const tag = el.tagName ? el.tagName.toLowerCase() : '';

    // --- Deteksi marker "Volume xx" -------------------------------------
    if (['p', 'div', 'span', 'b', 'strong', 'h3', 'h4', 'li'].includes(tag)) {
      const txt = directText($, el);
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
  };
}

/**
 * Detail satu novel — lazy: baru di-scrape saat pertama kali diminta untuk
 * [id] tersebut, lalu dipakai dari cache untuk request-request berikutnya.
 * `novelDetailPromises` mencegah scrape ganda untuk [id] yang sama jika ada
 * 2 request datang bersamaan sebelum scrape pertama selesai.
 */
const novelDetailPromises = new Map();
async function getNovelDetail(id) {
  if (novelCache[id]) return novelCache[id];
  if (novelDetailPromises.has(id)) return novelDetailPromises.get(id);

  const promise = (async () => {
    // Pastikan index (& url novel) sudah ada — jika belum, bangun dulu (self-heal),
    // supaya /api/novels/:id tetap bisa dipanggil duluan tanpa /api/novels.
    const { urlMap } = await getNovelIndex();
    const novelUrl = urlMap[id];
    if (!novelUrl) return null;

    console.log(`[novel] Scraping detail: ${novelUrl}`);
    const html = await fetchHtml(novelUrl);
    const detail = parseNovelPage(html, novelUrl);

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
// 3. ISI CHAPTER — baru diambil & dibersihkan (htmlCleaner) saat chapter dibuka
// ---------------------------------------------------------------------------

/**
 * Isi HTML satu chapter — lazy: baru di-fetch + dibersihkan saat pertama kali
 * diminta untuk [chapterUrl] tersebut, lalu dipakai dari cache setelahnya.
 * `chapterPromises` mencegah fetch ganda untuk [chapterUrl] yang sama jika
 * ada 2 request datang bersamaan sebelum fetch pertama selesai.
 */
const chapterPromises = new Map();
async function getChapterContent(chapterUrl) {
  if (Object.prototype.hasOwnProperty.call(chapterCache, chapterUrl)) {
    return chapterCache[chapterUrl];
  }
  if (chapterPromises.has(chapterUrl)) return chapterPromises.get(chapterUrl);

  const promise = (async () => {
    console.log(`[chapter] Mengambil isi: ${chapterUrl}`);
    const html = await fetchHtml(chapterUrl);
    const htmlContent = extractChapterHtml(html);

    chapterCache[chapterUrl] = htmlContent;
    saveJsonCache('chapters.json', chapterCache);
    return htmlContent;
  })().finally(() => {
    chapterPromises.delete(chapterUrl);
  });

  chapterPromises.set(chapterUrl, promise);
  return promise;
}

// ---------------------------------------------------------------------------
// SERVER HTTP — endpoint lazy untuk dipanggil dari app Flutter
// ---------------------------------------------------------------------------

function sendJson(res, status, data) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': '*',
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': '*',
    });
    return res.end();
  }

  const requestUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = requestUrl.pathname;

  try {
    // GET /api/novels -> index ringan (Explore)
    if (pathname === '/api/novels' && req.method === 'GET') {
      const { entries } = await getNovelIndex();
      return sendJson(res, 200, entries);
    }

    // GET /api/novels/:id -> detail novel (dibuka saat user masuk halaman detail)
    const detailMatch = pathname.match(/^\/api\/novels\/([^/]+)$/);
    if (detailMatch && req.method === 'GET') {
      const id = decodeURIComponent(detailMatch[1]);
      const detail = await getNovelDetail(id);
      if (!detail) return sendJson(res, 404, { error: 'Novel tidak ditemukan' });
      return sendJson(res, 200, detail);
    }

    // GET /api/chapter?url=... -> isi chapter (dibuka saat user membuka chapter)
    if (pathname === '/api/chapter' && req.method === 'GET') {
      const chapterUrl = requestUrl.searchParams.get('url');
      if (!chapterUrl) {
        return sendJson(res, 400, { error: 'Parameter "url" wajib diisi' });
      }
      const htmlContent = await getChapterContent(chapterUrl);
      return sendJson(res, 200, { htmlContent });
    }

    return sendJson(res, 404, { error: 'Endpoint tidak ditemukan' });
  } catch (err) {
    console.error('[error]', err.message);
    return sendJson(res, 500, { error: err.message });
  }
});

server.listen(PORT, () => {
  console.log(`[lazy-scraper] Server berjalan di http://localhost:${PORT}`);
  console.log('Endpoint:');
  console.log('  GET /api/novels            -> index ringan (id, title, cover, author)');
  console.log('  GET /api/novels/:id        -> detail novel (synopsis, genres, author, artist, volumes+chapters tanpa htmlContent)');
  console.log('  GET /api/chapter?url=...   -> htmlContent satu chapter (dibersihkan via htmlCleaner)');
  console.log(`Cache disimpan di: ${CACHE_DIR}`);
});
