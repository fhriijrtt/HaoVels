const cheerio = require('cheerio');
const { extractDates } = require('./dateExtractor');

/**
 * Tag yang dipertahankan saat membersihkan isi chapter.
 * Struktur paragraf, gambar, bold/italic, alignment, dan break line
 * harus tetap utuh agar flutter_html bisa merendernya dengan benar.
 */
const ALLOWED_TAGS = ['p', 'div', 'img', 'b', 'i', 'span', 'br', 'strong', 'em'];

/**
 * Tag yang harus dihapus total (termasuk isinya) karena tidak relevan
 * atau berpotensi berbahaya/mengganggu (iklan, widget blogger, komentar, script).
 */
const REMOVE_SELECTORS = [
  'script',
  'iframe',
  'style',
  'noscript',
  // Iklan & widget umum pada blogspot/blogger
  '.adsbygoogle',
  'ins.adsbygoogle',
  '[id*="ads"]',
  '[class*="ads"]',
  '[id*="banner"]',
  '.widget',
  '#comments',
  '.comments',
  '.comment-section',
  '.blogger-comments',
  '.related-posts',
  '.share-buttons',
  '.post-share',
  '.post-nav',
  '.sharethis',
  'form',
];

/**
 * Mengambil & membersihkan HTML dari elemen `.post-body.entry-content`,
 * mempertahankan struktur paragraf/format dan menghapus elemen yang tidak diinginkan.
 *
 * PENTING: tanggal (updatedAt/publishedAt) diambil dari `rawHtml` SEBELUM
 * elemen-elemen dibuang, karena blok JSON-LD ada di luar `.post-body` dan
 * fungsi ini hanya bekerja di dalam `.post-body` untuk pembersihan konten.
 *
 * @param {string} rawHtml - HTML mentah dari halaman chapter.
 * @returns {{ htmlContent: string, updatedAt: string|null, publishedAt: string|null }}
 */
function extractChapterHtml(rawHtml) {
  const { updatedAt, publishedAt } = extractDates(rawHtml);

  const $ = cheerio.load(rawHtml);
  const content = $('.post-body.entry-content').first();

  if (content.length === 0) {
    // Fallback: jika selector tidak ditemukan, kembalikan body apa adanya
    // (lebih baik daripada gagal total saat struktur halaman sedikit berbeda).
    return { htmlContent: '', updatedAt, publishedAt };
  }

  // Hapus elemen yang tidak diinginkan: script, iklan, widget, komentar, dll.
  REMOVE_SELECTORS.forEach((selector) => {
    content.find(selector).remove();
  });

  // Hapus semua atribut kecuali src (untuk img) dan style (untuk alignment)
  // agar output tetap ramping namun mempertahankan alignment & gambar.
  content.find('*').each((_, el) => {
    const $el = $(el);
    const tag = el.tagName ? el.tagName.toLowerCase() : '';

    if (!ALLOWED_TAGS.includes(tag)) {
      // Tag tidak dikenal -> unwrap (pertahankan isinya, buang wrapper-nya)
      $el.replaceWith($el.html() || '');
      return;
    }

    const attribs = { ...el.attribs };
    Object.keys(attribs).forEach((attr) => {
      if (tag === 'img' && attr === 'src') return;
      if (attr === 'style') {
        // Pertahankan hanya properti alignment dari style asli
        const style = attribs.style || '';
        const match = style.match(/text-align\s*:\s*(left|right|center|justify)/i);
        if (match) {
          $el.attr('style', `text-align:${match[1]}`);
          return;
        }
      }
      $el.removeAttr(attr);
    });
  });

  // Hapus paragraf/div kosong sisa pembersihan
  content.find('p, div').each((_, el) => {
    const $el = $(el);
    if ($el.find('img').length === 0 && $el.text().trim() === '') {
      $el.remove();
    }
  });

  const htmlContent = content.html() ? content.html().trim() : '';

  return { htmlContent, updatedAt, publishedAt };
}

module.exports = { extractChapterHtml };
