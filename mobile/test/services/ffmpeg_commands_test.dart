import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/services/ffmpeg_commands.dart';

void main() {
  test('buildMp3EncodeArgs sets bitrate and strips video', () {
    final args = buildMp3EncodeArgs(
      audioInputPath: '/tmp/audio.m4a',
      outputPath: '/tmp/out.mp3',
      bitrateKbps: 192,
    );
    expect(args, [
      '-y',
      '-i', '/tmp/audio.m4a',
      '-vn',
      '-b:a', '192k',
      '/tmp/out.mp3',
    ]);
  });

  test('buildMp4MuxArgs copies video and transcodes audio to aac', () {
    final args = buildMp4MuxArgs(
      videoInputPath: '/tmp/video.mp4',
      audioInputPath: '/tmp/audio.m4a',
      outputPath: '/tmp/out.mp4',
    );
    expect(args, [
      '-y',
      '-i', '/tmp/video.mp4',
      '-i', '/tmp/audio.m4a',
      '-c:v', 'copy',
      '-c:a', 'aac',
      '/tmp/out.mp4',
    ]);
  });
}
