import 'package:flutter/material.dart';
import '../core/models/models.dart';

class ChapterTile extends StatelessWidget {
  final Chapter chapter;
  final VoidCallback onTap;
  final bool isLastRead;

  const ChapterTile({
    super.key,
    required this.chapter,
    required this.onTap,
    this.isLastRead = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(chapter.title),
      trailing: isLastRead
          ? const Icon(Icons.bookmark, color: Colors.amber, size: 18)
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
