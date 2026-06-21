import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/providers.dart';
import '../../core/models/models.dart';
import '../../widgets/chapter_tile.dart';

class VolumePage extends ConsumerWidget {
  final String novelId;
  final int volumeNumber;

  const VolumePage({
    super.key,
    required this.novelId,
    required this.volumeNumber,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(novelDetailProvider(novelId));

    return Scaffold(
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Gagal memuat: $e')),
        data: (novel) {
          if (novel == null) return const Center(child: Text('Tidak ditemukan'));
          final volume = novel.volumes.firstWhere(
            (v) => v.number == volumeNumber,
            orElse: () => novel.volumes.first,
          );

          // Begitu halaman Volume dibuka, minta tanggal SEMUA chapter di
          // volume ini sekaligus (satu request batch ke server), supaya
          // tiap ChapterTile bisa langsung menampilkan "terakhir update"
          // tanpa harus membuka chapter satu-satu.
          final urls = volume.chapters.map((c) => c.url).toList();
          final datesAsync = ref.watch(chapterDatesBatchProvider(urls));

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text('${novel.title} - ${volume.name}'),
              ),
              datesAsync.when(
                // Selagi tanggal masih dimuat, tetap tampilkan daftar
                // chapter (tanpa keterangan tanggal) -> user tidak perlu
                // menunggu sebelum bisa melihat/membuka chapter.
                loading: () => _chapterList(context, novel, volume, volume.chapters),
                error: (e, st) => _chapterList(context, novel, volume, volume.chapters),
                data: (dates) {
                  final withDates = volume.chapters.map((c) {
                    final d = dates[c.url];
                    if (d == null) return c;
                    return c.copyWithDates(
                      updatedAt: d.updatedAt,
                      publishedAt: d.publishedAt,
                    );
                  }).toList();
                  return _chapterList(context, novel, volume, withDates);
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _chapterList(
    BuildContext context,
    Novel novel,
    Volume volume,
    List<Chapter> chapters,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final chapter = chapters[i];
          return ChapterTile(
            chapter: chapter,
            onTap: () => context.push(
              '/novel/${novel.id}/volume/${volume.number}/chapter/${chapter.order}',
            ),
          );
        },
        childCount: chapters.length,
      ),
    );
  }
}
