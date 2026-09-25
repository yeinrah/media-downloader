import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_options.dart';

class AppSettings {
  final DownloadFormat format;
  final AudioQuality audioQuality;
  final VideoQuality videoQuality;
  final String? saveDirUri;

  const AppSettings({
    required this.format,
    required this.audioQuality,
    required this.videoQuality,
    this.saveDirUri,
  });

  static const defaults = AppSettings(
    format: DownloadFormat.mp3,
    audioQuality: defaultAudioQuality,
    videoQuality: defaultVideoQuality,
    saveDirUri: null,
  );

  AppSettings copyWith({
    DownloadFormat? format,
    AudioQuality? audioQuality,
    VideoQuality? videoQuality,
    String? saveDirUri,
  }) {
    return AppSettings(
      format: format ?? this.format,
      audioQuality: audioQuality ?? this.audioQuality,
      videoQuality: videoQuality ?? this.videoQuality,
      saveDirUri: saveDirUri ?? this.saveDirUri,
    );
  }
}

class SettingsService {
  static const _keyFormat = 'download_format';
  static const _keyAudioQuality = 'audio_quality';
  static const _keyVideoQuality = 'video_quality';
  static const _keySaveDirUri = 'save_dir_uri';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      format: _readEnum(prefs, _keyFormat, DownloadFormat.values) ??
          AppSettings.defaults.format,
      audioQuality: _readEnum(prefs, _keyAudioQuality, AudioQuality.values) ??
          AppSettings.defaults.audioQuality,
      videoQuality: _readEnum(prefs, _keyVideoQuality, VideoQuality.values) ??
          AppSettings.defaults.videoQuality,
      saveDirUri: prefs.getString(_keySaveDirUri),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFormat, settings.format.name);
    await prefs.setString(_keyAudioQuality, settings.audioQuality.name);
    await prefs.setString(_keyVideoQuality, settings.videoQuality.name);
    if (settings.saveDirUri != null) {
      await prefs.setString(_keySaveDirUri, settings.saveDirUri!);
    } else {
      await prefs.remove(_keySaveDirUri);
    }
  }

  T? _readEnum<T extends Enum>(SharedPreferences prefs, String key, List<T> values) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}
