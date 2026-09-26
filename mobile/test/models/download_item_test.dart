import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_item.dart';
import 'package:yt_downloader/models/download_options.dart';

void main() {
  test('statusLabel covers processing', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      status: DownloadStatus.processing,
    );
    expect(item.statusLabel, '변환 중');
  });

  test('isActive is true while processing', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      status: DownloadStatus.processing,
    );
    expect(item.isActive, isTrue);
  });

  test('qualityLabel for mp3 shows audio bitrate', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps320,
    );
    expect(item.qualityLabel, '320 kbps');
  });

  test('qualityLabel for mp4 without fallback shows requested height', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp4,
      videoQuality: VideoQuality.q720p,
      appliedHeightPx: 720,
    );
    expect(item.qualityLabel, '720p');
  });

  test('qualityLabel for mp4 with fallback shows requested-to-applied text', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp4,
      videoQuality: VideoQuality.q720p,
      appliedHeightPx: 480,
    );
    expect(item.qualityLabel, '720p 요청 → 480p로 다운로드됨');
  });

  test('constructor asserts format matches exactly one quality', () {
    expect(
      () => DownloadItem(
        id: '1',
        url: 'https://example.com',
        format: DownloadFormat.mp3,
        videoQuality: VideoQuality.q720p,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
