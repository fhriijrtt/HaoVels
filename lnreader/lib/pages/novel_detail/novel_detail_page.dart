import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/providers/providers.dart';
import '../../core/utils/date_format.dart';
import '../../widgets/volume_card.dart';

class NovelDetailPage extends ConsumerWidget {
  final String novelId;
  const NovelDetailPage({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(novelDetailProvider(novelId));
    final prefs = ref.read(prefsServiceProvider);

    return Scaffold(
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Gagal memuat: $e')),
        data: (novel) {
          if (novel == null) {
            return const Center(child: Text('Novel tidak ditemukan'));
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: novel.cover,
                        fit: BoxFit.cover,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.1),
                              Colors.black.withOpacity(0.85),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  FutureBuilder<bool>(
                    future: prefs.isBookmarked(novel.id),
                    builder: (context, snapshot) {
                      final bookmarked = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          bookmarked ? Icons.bookmark : Icons.bookmark_outline,
                        ),
                        onPressed: () async {
                          await prefs.toggleBookmark(
                            id: novel.id,
                            title: novel.title,
                            cover: novel.cover,
                            updatedAt: novel.updatedAt?.toIso8601String(),
                          );
                          ref.invalidate(bookmarkListProvider);
                          (context as Element).markNeedsBuild();
                        },
                      );
                    },
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(novel.title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    if (novel.updatedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.update,
                                size: 14, color: Colors.amber.shade300),
                            const SizedBox(width: 4),
                            Text(
                              'Terakhir update: ${formatRelative(novel.updatedAt!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade300,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (novel.author.isNotEmpty)
                      Text('Author: ${novel.author}'),
                    if (novel.artist.isNotEmpty)
                      Text('Artist: ${novel.artist}'),
                    const SizedBox(height: 8),
                    if (novel.genres.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: novel.genres
                            .map((g) => Chip(label: Text(g)))
                            .toList(),
                      ),
                    const SizedBox(height: 16),
                    Text('Sinopsis',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(novel.synopsis,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 20),
                    Text('Volume',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final volume = novel.volumes[i];
                      return VolumeCard(
                        volume: volume,
                        onTap: () => context.push(
                          '/novel/${novel.id}/volume/${volume.number}',
                        ),
                      );
                    },
                    childCount: novel.volumes.length,
                  ),
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
