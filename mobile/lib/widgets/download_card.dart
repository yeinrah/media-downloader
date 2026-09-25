import 'package:flutter/material.dart';
import '../models/download_item.dart';

class DownloadCard extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  const DownloadCard({
    super.key,
    required this.item,
    required this.onRemove,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ── 본문 ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상태 아이콘
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _iconBg(cs),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: _statusIcon(cs)),
                ),
                const SizedBox(width: 12),

                // 제목 + 상태
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isNotEmpty ? item.title : item.url,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            item.statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(cs),
                            ),
                          ),
                          if (item.speedLabel.isNotEmpty) ...[
                            Text('  •  ',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withOpacity(0.3))),
                            Text(
                              item.speedLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withOpacity(0.5)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // 버튼들
                Column(
                  children: [
                    // 삭제/닫기
                    GestureDetector(
                      onTap: onRemove,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 18,
                            color: cs.onSurface.withOpacity(0.35)),
                      ),
                    ),
                    if (onOpen != null)
                      GestureDetector(
                        onTap: onOpen,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.play_circle_outline_rounded,
                              size: 18, color: cs.secondary),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── 진행률 바 ──────────────────────────────
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.fetching ||
              item.status == DownloadStatus.processing)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.status == DownloadStatus.downloading
                      ? item.progress
                      : null,
                  minHeight: 3,
                  backgroundColor: cs.onSurface.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation(
                    item.status == DownloadStatus.downloading
                        ? cs.primary
                        : cs.secondary,
                  ),
                ),
              ),
            )
          else if (item.status == DownloadStatus.done)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1.0,
                  minHeight: 3,
                  backgroundColor: cs.onSurface.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation(cs.secondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _iconBg(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.waiting:     return cs.onSurface.withOpacity(0.06);
      case DownloadStatus.fetching:    return cs.secondary.withOpacity(0.12);
      case DownloadStatus.downloading: return cs.primary.withOpacity(0.12);
      case DownloadStatus.processing:  return cs.secondary.withOpacity(0.12);
      case DownloadStatus.done:        return cs.secondary.withOpacity(0.15);
      case DownloadStatus.error:       return cs.error.withOpacity(0.12);
    }
  }

  Color _statusColor(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.waiting:     return cs.onSurface.withOpacity(0.4);
      case DownloadStatus.fetching:    return cs.secondary;
      case DownloadStatus.downloading: return cs.primary;
      case DownloadStatus.processing:  return cs.secondary;
      case DownloadStatus.done:        return cs.secondary;
      case DownloadStatus.error:       return cs.error;
    }
  }

  Widget _statusIcon(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.waiting:
        return Icon(Icons.schedule_rounded,
            size: 18, color: cs.onSurface.withOpacity(0.4));
      case DownloadStatus.fetching:
        return SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: cs.secondary),
        );
      case DownloadStatus.downloading:
        return Icon(Icons.downloading_rounded, size: 18, color: cs.primary);
      case DownloadStatus.processing:
        return SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: cs.secondary),
        );
      case DownloadStatus.done:
        return Icon(Icons.check_rounded, size: 18, color: cs.secondary);
      case DownloadStatus.error:
        return Icon(Icons.error_outline_rounded, size: 18, color: cs.error);
    }
  }
}
