/// Util format tanggal ringan untuk menampilkan "terakhir update" di
/// berbagai layar (Explore, Bookmark, Volume, Reader), tanpa menambah
/// dependency `intl` (yang butuh inisialisasi locale tambahan).

const List<String> _monthNamesId = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Format lengkap, mis. "14 Jun 2026, 20:53". Dipakai di halaman Reader &
/// Volume yang punya cukup ruang untuk tanggal lengkap.
String formatDate(DateTime date) {
  final local = date.toLocal();
  final day = local.day.toString();
  final month = _monthNamesId[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day $month ${local.year}, $hour:$minute';
}

/// Format relatif singkat untuk kartu/list yang ruangnya terbatas (Explore,
/// Bookmark), mis. "Baru saja", "5 menit lalu", "3 jam lalu", "2 hari lalu",
/// lalu jatuh ke tanggal singkat ("14 Jun 2026") setelah lebih dari 7 hari.
String formatRelative(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date.toLocal());

  if (diff.inSeconds < 60) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';

  final local = date.toLocal();
  final day = local.day.toString();
  final month = _monthNamesId[local.month - 1];
  return '$day $month ${local.year}';
}
