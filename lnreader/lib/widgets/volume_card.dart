import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/models/models.dart';

class VolumeCard extends StatelessWidget {
  final Volume volume;
  final VoidCallback onTap;

  const VolumeCard({super.key, required this.volume, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: CachedNetworkImage(
                imageUrl: volume.cover,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (c, _) => Container(color: Colors.grey.shade800),
                errorWidget: (c, _, __) => Container(
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.menu_book),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                volume.name,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
