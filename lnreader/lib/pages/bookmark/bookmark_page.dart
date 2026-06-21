import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/providers/providers.dart';
import '../../widgets/bottom_navbar.dart';

class BookmarkPage extends ConsumerWidget {
  const BookmarkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarkListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmark')),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
      body: bookmarksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Gagal memuat: $e')),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return const Center(child: Text('Belum ada bookmark'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: bookmarks.length,
            itemBuilder: (context, i) {
              final item = bookmarks[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(8),
                  leading: SizedBox(
                    width: 50,
                    height: 70,
                    child: CachedNetworkImage(
                      imageUrl: item['cover'] ?? '',
                      fit: BoxFit.cover,
                      errorWidget: (c, _, __) => const Icon(Icons.book),
                    ),
                  ),
                  title: Text(item['title'] ?? ''),
                  onTap: () => context.push('/novel/${item['id']}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
