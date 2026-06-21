import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/providers.dart';
import '../../core/models/models.dart';
import '../../widgets/novel_card.dart';
import '../../widgets/bottom_navbar.dart';

class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  List<Novel> _filter(List<Novel> novels, String query) {
    if (query.trim().isEmpty) return novels;
    final q = query.toLowerCase();
    return novels.where((n) {
      final inTitle = n.title.toLowerCase().contains(q);
      final inAlias = n.alias.any((a) => a.toLowerCase().contains(q));
      final inAuthor = n.author.toLowerCase().contains(q);
      return inTitle || inAlias || inAuthor;
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novelsAsync = ref.watch(novelIndexProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari judul, alias, atau author...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) =>
                  ref.read(searchQueryProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: novelsAsync.when(
              data: (novels) {
                final filtered = _filter(novels, query);
                if (filtered.isEmpty) {
                  return const Center(child: Text('Tidak ditemukan'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final novel = filtered[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NovelCard(
                        novel: novel,
                        onTap: () => context.push('/novel/${novel.id}'),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Gagal memuat data: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
