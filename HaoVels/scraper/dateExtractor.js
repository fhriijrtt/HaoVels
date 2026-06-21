const cheerio = require('cheerio');

/**
 * Mengambil `dateModified` dan `datePublished` dari blok JSON-LD
 * (<script type="application/ld+json">) yang disisipkan Blogspot di setiap
 * halaman post (baik halaman novel maupun halaman chapter). Formatnya selalu
 * ISO 8601 dengan offset timezone, contoh: "2026-06-14T20:53:05+07:00".
 *
 * Kenapa ambil dari sini (bukan dari elemen <time>):
 *  - `dateModified` BERUBAH OTOMATIS setiap kali pemilik blog meng-edit
 *    halaman tsb (mis. menambahkan link chapter baru ke halaman novel).
 *    Ini dipakai scraper untuk mendeteksi "ada yang berubah, perlu
 *    di-scrape ulang" tanpa harus membaca isi/membandingkan teks.
 *  - Presisinya sampai detik & punya timezone eksplisit, lebih konsisten
 *    untuk dibandingkan/diurutkan daripada teks tanggal yang dilokalisasi
 *    (mis. "Maret 13, 2021").
 *
 * @param {string} html - HTML mentah satu halaman (novel atau chapter).
 * @returns {{ updatedAt: string|null, publishedAt: string|null }}
 */
function extractDates(html) {
  const $ = cheerio.load(html);
  let updatedAt = null;
  let publishedAt = null;

  $('script[type="application/ld+json"]').each((_, el) => {
    if (updatedAt && publishedAt) return; // sudah ketemu keduanya, berhenti

    const raw = $(el).contents().text();
    if (!raw || !raw.includes('dateModified') && !raw.includes('datePublished')) return;

    try {
      const json = JSON.parse(raw);
      const candidates = Array.isArray(json) ? json : [json];

      for (const item of candidates) {
        if (!item || typeof item !== 'object') continue;
        if (!updatedAt && typeof item.dateModified === 'string') {
          updatedAt = item.dateModified;
        }
        if (!publishedAt && typeof item.datePublished === 'string') {
          publishedAt = item.datePublished;
        }
      }
    } catch (err) {
      // JSON-LD kadang malformed (mis. terpotong) -> abaikan, lanjut ke script lain
    }
  });

  // Fallback: kalau dateModified tidak ada tapi datePublished ada (jarang
  // terjadi di Blogspot, tapi untuk jaga-jaga), pakai datePublished sebagai
  // updatedAt supaya field "terakhir update" tetap terisi.
  if (!updatedAt && publishedAt) updatedAt = publishedAt;

  return { updatedAt, publishedAt };
}

module.exports = { extractDates };
