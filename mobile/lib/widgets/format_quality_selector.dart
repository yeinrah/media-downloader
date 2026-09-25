import 'package:flutter/material.dart';
import '../models/download_options.dart';

class FormatQualitySelector extends StatelessWidget {
  final DownloadFormat format;
  final AudioQuality audioQuality;
  final VideoQuality videoQuality;
  final ValueChanged<DownloadFormat> onFormatChanged;
  final ValueChanged<AudioQuality> onAudioQualityChanged;
  final ValueChanged<VideoQuality> onVideoQualityChanged;

  const FormatQualitySelector({
    super.key,
    required this.format,
    required this.audioQuality,
    required this.videoQuality,
    required this.onFormatChanged,
    required this.onAudioQualityChanged,
    required this.onVideoQualityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButton<DownloadFormat>(
            value: format,
            isExpanded: true,
            items: DownloadFormat.values
                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) onFormatChanged(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: format == DownloadFormat.mp3
              ? DropdownButton<AudioQuality>(
                  value: audioQuality,
                  isExpanded: true,
                  items: AudioQuality.values
                      .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onAudioQualityChanged(v);
                  },
                )
              : DropdownButton<VideoQuality>(
                  value: videoQuality,
                  isExpanded: true,
                  items: VideoQuality.values
                      .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onVideoQualityChanged(v);
                  },
                ),
        ),
      ],
    );
  }
}
