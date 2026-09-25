enum DownloadFormat { mp3, mp4 }

enum AudioQuality { kbps128, kbps192, kbps320 }

enum VideoQuality { q360p, q480p, q720p, q1080p }

extension DownloadFormatLabel on DownloadFormat {
  String get label {
    switch (this) {
      case DownloadFormat.mp3:
        return 'MP3 (오디오)';
      case DownloadFormat.mp4:
        return 'MP4 (영상)';
    }
  }
}

extension AudioQualityLabel on AudioQuality {
  int get bitrateKbps {
    switch (this) {
      case AudioQuality.kbps128:
        return 128;
      case AudioQuality.kbps192:
        return 192;
      case AudioQuality.kbps320:
        return 320;
    }
  }

  String get label => '$bitrateKbps kbps';
}

extension VideoQualityLabel on VideoQuality {
  int get heightPx {
    switch (this) {
      case VideoQuality.q360p:
        return 360;
      case VideoQuality.q480p:
        return 480;
      case VideoQuality.q720p:
        return 720;
      case VideoQuality.q1080p:
        return 1080;
    }
  }

  String get label => '${heightPx}p';
}

const defaultAudioQuality = AudioQuality.kbps192;
const defaultVideoQuality = VideoQuality.q720p;
