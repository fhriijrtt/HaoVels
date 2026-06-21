import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/providers.dart';
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
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text('${novel.title} - ${volume.name}'),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final chapter = volume.chapters[i];
                    return ChapterTile(
                      chapter: chapter,
                      onTap: () => context.push(
                        '/novel/${novel.id}/volume/${volume.number}/chapter/${chapter.order}',
                      ),
                    );
                  },
                  childCount: volume.chapters.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          );
        },
      ),
    );
  }
}
