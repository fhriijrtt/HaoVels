import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/providers/providers.dart';
import '../../core/models/models.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final String novelId;
  final int volumeNumber;
  final int chapterOrder;

  const ReaderPage({
    super.key,
    required this.novelId,
    required this.volumeNumber,
    required this.chapterOrder,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  double _fontSize = 18;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
  }

  Future<void> _loadFontSize() async {
    final prefs = ref.read(prefsServiceProvider);
    final size = await prefs.getFontSize();
    setState(() => _fontSize = size);
  }

  Future<void> _changeFontSize(double delta) async {
    final prefs = ref.read(prefsServiceProvider);
    final newSize = (_fontSize + delta).clamp(12.0, 32.0);
    setState(() => _fontSize = newSize);
    await prefs.setFontSize(newSize);
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(novelDetailProvider(widget.novelId));

    return Scaffold(
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Gagal memuat: $e')),
        data: (novel) {
          if (novel == null) return const Center(child: Text('Tidak ditemukan'));

          // Build the single linear list of chapters across ALL volumes.
          final flat = novel.flatChapters;
          final currentIndex = flat.indexWhere(
            (f) =>
                f.volume.number == widget.volumeNumber &&
                f.chapter.order == widget.chapterOrder,
          );

          if (currentIndex == -1) {
            return const Center(child: Text('Chapter tidak ditemukan'));
          }

          final current = flat[currentIndex];
          final hasPrev = currentIndex > 0;
          final hasNext = currentIndex < flat.length - 1;

          // Save reading progress whenever a chapter is opened.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(prefsServiceProvider).saveProgress(
                  novelId: novel.id,
                  novelTitle: novel.title,
                  cover: novel.cover,
                  volumeNumber: current.volume.number,
                  volumeName: current.volume.name,
                  chapterOrder: current.chapter.order,
                  chapterTitle: current.chapter.title,
                );
          });

          return Column(
            children: [
              AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      novel.title,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${current.volume.name} • ${current.chapter.title}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.text_decrease),
                    onPressed: () => _changeFontSize(-1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_increase),
                    onPressed: () => _changeFontSize(1),
                  ),
                ],
              ),
              Expanded(
                child: ref.watch(chapterContentProvider(current.chapter.url)).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) =>
                      Center(child: Text('Gagal memuat chapter: $e')),
                  data: (htmlContent) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Html(
                      data: htmlContent,
                      style: {
                        "body": Style(
                          fontFamily: 'Georgia',
                          fontSize: FontSize(_fontSize),
                          lineHeight: const LineHeight(1.6),
                        ),
                        "p": Style(
                          margin: Margins.only(bottom: 12),
                        ),
                        "img": Style(
                          width: Width(double.infinity, Unit.px),
                          margin: Margins.symmetric(vertical: 12),
                        ),
                      },
                      extensions: [
                        _ImageExtension(),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Previous'),
                          onPressed: hasPrev
                              ? () => _goTo(context, novel, flat[currentIndex - 1])
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next'),
                          onPressed: hasNext
                              ? () => _goTo(context, novel, flat[currentIndex + 1])
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _goTo(BuildContext context, Novel novel, FlatChapterRef target) {
    context.pushReplacement(
      '/novel/${novel.id}/volume/${target.volume.number}/chapter/${target.chapter.order}',
    );
  }
}

/// Minimal custom extension so <img> tags render via cached_network_image
/// (keeps illustrations embedded inside chapter content working nicely,
/// including on web where some image loading needs CORS-friendly caching).
class _ImageExtension extends HtmlExtension {
  @override
  Set<String> get supportedTags => {"img"};

  @override
  InlineSpan build(ExtensionContext context) {
    final src = context.attributes['src'] ?? '';
    if (src.isEmpty) return const TextSpan(text: '');
    return WidgetSpan(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: CachedNetworkImage(
          imageUrl: src,
          fit: BoxFit.contain,
          placeholder: (c, _) => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (c, _, __) => const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  @override
  bool matches(ExtensionContext context) => supportedTags.contains(context.elementName);
}
