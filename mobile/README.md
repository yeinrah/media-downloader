# MP3 Downloader — Flutter Android App

YouTube / Vimeo 영상을 MP3로 다운로드하는 개인용 Android 앱.

---

## 빌드 전 필수 준비: yt-dlp ARM64 바이너리

APK에 yt-dlp 바이너리를 포함시켜야 합니다.

```bash
# assets 폴더에 yt-dlp ARM64 바이너리 다운로드
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64 \
     -o assets/yt-dlp
chmod +x assets/yt-dlp
```

> ⚠️ 이 파일이 없으면 앱이 실행되지 않습니다.

---

## 빌드 방법

```bash
# 1. 의존성 설치
flutter pub get

# 2. APK 빌드 (릴리즈)
flutter build apk --release --split-per-abi

# 완성된 APK 위치:
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  ← 설치용
```

---

## 앱 기능

- YouTube / Vimeo URL → MP3 자동 변환 다운로드
- 최대 3개 동시 다운로드
- 실시간 진행률 + 속도 표시
- 다운로드 완료 파일 바로 재생
- 저장 위치: `/sdcard/Music/MP3Downloader/`

---

## 주의사항

- Android 8.0 (API 26) 이상 필요
- 처음 실행 시 저장소 권한 허용 필요
- Android 11+ 에서는 "모든 파일 접근" 권한도 허용 필요
- FFmpeg는 yt-dlp에 내장되어 있어 별도 설치 불필요

---

## 의존 패키지

| 패키지 | 역할 |
|---|---|
| `path_provider` | 저장 경로 |
| `permission_handler` | 권한 요청 |
| `open_filex` | 파일 열기 |
| `uuid` | 다운로드 항목 ID |
