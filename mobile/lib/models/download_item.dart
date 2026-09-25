import 'download_options.dart';

enum DownloadStatus { waiting, fetching, downloading, processing, done, error }

class DownloadItem {
  final String id;
  final String url;
  String title;
  DownloadStatus status;
  double progress;   // 0.0 ~ 1.0
  String? errorMsg;
  String? filePath;
  String speedLabel;

  final DownloadFormat format;
  final AudioQuality? audioQuality;
  final VideoQuality? videoQuality;
  int? appliedHeightPx;

  DownloadItem({
    required this.id,
    required this.url,
    required this.format,
    this.audioQuality,
    this.videoQuality,
    this.title = '',
    this.status = DownloadStatus.waiting,
    this.progress = 0,
    this.errorMsg,
    this.filePath,
    this.speedLabel = '',
    this.appliedHeightPx,
  }) : assert(
          (format == DownloadFormat.mp3 &&
                  audioQuality != null &&
                  videoQuality == null) ||
              (format == DownloadFormat.mp4 &&
                  videoQuality != null &&
                  audioQuality == null),
          'format must be paired with exactly one matching quality value',
        );

  String get statusLabel {
    switch (status) {
      case DownloadStatus.waiting:     return '대기 중';
      case DownloadStatus.fetching:    return '정보 수집 중';
      case DownloadStatus.downloading: return '다운로드 중';
      case DownloadStatus.processing:  return '변환 중';
      case DownloadStatus.done:        return '완료';
      case DownloadStatus.error:       return errorMsg ?? '오류';
    }
  }

  String get qualityLabel {
    if (format == DownloadFormat.mp3) return audioQuality!.label;
    final requestedHeight = videoQuality!.heightPx;
    final appliedHeight = appliedHeightPx ?? requestedHeight;
    if (appliedHeight != requestedHeight) {
      return '${requestedHeight}p 요청 → ${appliedHeight}p로 다운로드됨';
    }
    return '${appliedHeight}p';
  }

  bool get isActive =>
      status == DownloadStatus.fetching ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.processing;
}
