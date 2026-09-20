enum DownloadStatus { waiting, fetching, downloading, done, error }

class DownloadItem {
  final String id;
  final String url;
  String title;
  DownloadStatus status;
  double progress;   // 0.0 ~ 1.0
  String? errorMsg;
  String? filePath;
  String speedLabel;

  DownloadItem({
    required this.id,
    required this.url,
    this.title = '',
    this.status = DownloadStatus.waiting,
    this.progress = 0,
    this.errorMsg,
    this.filePath,
    this.speedLabel = '',
  });

  String get statusLabel {
    switch (status) {
      case DownloadStatus.waiting:     return '대기 중';
      case DownloadStatus.fetching:    return '정보 수집 중';
      case DownloadStatus.downloading: return '다운로드 중';
      case DownloadStatus.done:        return '완료';
      case DownloadStatus.error:       return errorMsg ?? '오류';
    }
  }

  bool get isActive =>
      status == DownloadStatus.fetching ||
      status == DownloadStatus.downloading;
}
