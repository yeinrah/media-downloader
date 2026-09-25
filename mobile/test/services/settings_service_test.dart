import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_downloader/models/download_options.dart';
import 'package:yt_downloader/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load returns defaults when nothing stored', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService().load();
    expect(settings.format, AppSettings.defaults.format);
    expect(settings.audioQuality, AppSettings.defaults.audioQuality);
    expect(settings.videoQuality, AppSettings.defaults.videoQuality);
    expect(settings.saveDirUri, isNull);
  });

  test('save then load round-trips values', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();
    await service.save(const AppSettings(
      format: DownloadFormat.mp4,
      audioQuality: AudioQuality.kbps320,
      videoQuality: VideoQuality.q1080p,
      saveDirUri: 'content://tree/abc',
    ));

    final loaded = await service.load();
    expect(loaded.format, DownloadFormat.mp4);
    expect(loaded.audioQuality, AudioQuality.kbps320);
    expect(loaded.videoQuality, VideoQuality.q1080p);
    expect(loaded.saveDirUri, 'content://tree/abc');
  });

  test('load falls back to defaults when stored enum name is invalid', () async {
    SharedPreferences.setMockInitialValues({
      'download_format': 'not_a_real_format',
    });
    final settings = await SettingsService().load();
    expect(settings.format, AppSettings.defaults.format);
  });
}
