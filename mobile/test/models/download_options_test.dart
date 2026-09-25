import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_options.dart';

void main() {
  test('DownloadFormat labels', () {
    expect(DownloadFormat.mp3.label, 'MP3 (오디오)');
    expect(DownloadFormat.mp4.label, 'MP4 (영상)');
  });

  test('AudioQuality bitrate and label', () {
    expect(AudioQuality.kbps128.bitrateKbps, 128);
    expect(AudioQuality.kbps192.bitrateKbps, 192);
    expect(AudioQuality.kbps320.bitrateKbps, 320);
    expect(AudioQuality.kbps192.label, '192 kbps');
  });

  test('VideoQuality height and label', () {
    expect(VideoQuality.q360p.heightPx, 360);
    expect(VideoQuality.q480p.heightPx, 480);
    expect(VideoQuality.q720p.heightPx, 720);
    expect(VideoQuality.q1080p.heightPx, 1080);
    expect(VideoQuality.q720p.label, '720p');
  });

  test('defaults', () {
    expect(defaultAudioQuality, AudioQuality.kbps192);
    expect(defaultVideoQuality, VideoQuality.q720p);
  });
}
