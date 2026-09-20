# Media Downloader

YouTube / Vimeo 영상 다운로드 도구 모음

## 구성

| 디렉토리 | 설명 | 플랫폼 |
|---|---|---|
| `desktop/` | Python + tkinter GUI | Windows |
| `mobile/` | Flutter Android 앱 | Android |

## Desktop

- YouTube / Vimeo / m3u8 URL 다운로드
- 병렬 다운로드 (최대 3개 동시)
- MP4 (720p/1080p/최고화질) / MP3 지원
- FFmpeg 번들 EXE 빌드 지원

**실행 방법:**
```bash
pip install yt-dlp
python desktop/youtube_downloader.py
```

**EXE 빌드:**
```
desktop/build_exe.bat 더블클릭
```

## Mobile (Flutter Android)

- YouTube / Vimeo URL → MP3 자동 변환
- 최대 3개 동시 다운로드
- 실시간 진행률 표시

**빌드 방법:**
```bash
cd mobile
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64 -o assets/yt-dlp
flutter pub get
flutter build apk --release --split-per-abi
```
