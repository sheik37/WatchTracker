import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.posterPath,
    required this.title,
    required this.onTap,
    this.showTitle = false,
    this.bottomContent,
    this.topRightContent,
  });

  final String? posterPath;
  final String title;
  final VoidCallback onTap;
  final bool showTitle;
  final Widget? bottomContent;
  final Widget? topRightContent;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 0.7,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posterPath != null)
                CachedNetworkImage(
                  imageUrl: posterPath!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey.shade800),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey.shade800,
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                    ),
                  ),
                )
              else
                Container(
                  color: Colors.grey.shade800,
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.white54,
                  ),
                ),
              ?topRightContent,
              ?bottomContent,
              if (showTitle)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.8),
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FollowCheckbox extends StatelessWidget {
  const FollowCheckbox({
    super.key,
    required this.checked,
    required this.onToggle,
  });

  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
    final bgColor = checked
        ? const Color(0xFFFFD400)
        : Colors.black.withValues(alpha: 0.45);
    final borderColor = checked
        ? Colors.black.withValues(alpha: 0.65)
        : const Color(0xFFFFD400).withValues(alpha: 0.85);
    final iconColor = checked
        ? Colors.black.withValues(alpha: 0.75)
        : const Color(0xFFFFD400);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 34,
        height: 34,
        decoration: ShapeDecoration(shape: shape, color: bgColor),
        foregroundDecoration: ShapeDecoration(
          shape: shape.copyWith(
            side: BorderSide(color: borderColor, width: 1.5),
          ),
        ),
        child: Icon(
          checked ? Icons.check_rounded : Icons.close_rounded,
          color: iconColor,
          size: 20,
        ),
      ),
    );
  }
}
