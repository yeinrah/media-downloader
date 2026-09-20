# MP3 Downloader — Flutter Android App

YouTube 영상을 오디오로 다운로드하는 개인용 Android 앱.

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

- YouTube URL → 오디오 스트림 다운로드 (`youtube_explode_dart` 사용, 네이티브 바이너리 불필요)
- 최대 3개 동시 다운로드
- 실시간 진행률 + 속도 표시
- 다운로드 완료 파일 바로 재생
- 저장 위치: `/sdcard/Music/MP3Downloader/`

---

## 주의사항

- Android 8.0 (API 26) 이상 필요
- 처음 실행 시 저장소 권한 허용 필요
- Android 11+ 에서는 "모든 파일 접근" 권한도 허용 필요
- YouTube는 오디오를 원본 코덱(AAC/m4a 또는 Opus/webm) 그대로 제공하므로, 온디바이스
  인코더 없이는 진짜 `.mp3`로 재인코딩할 수 없습니다. 재생 호환성이 가장 좋은
  m4a(AAC) 스트림을 우선 선택하고, 없으면 최고 비트레이트 스트림을 원본 확장자
  그대로 저장합니다.
- Vimeo는 현재 지원하지 않습니다 (`youtube_explode_dart`는 YouTube 전용).

---

## 의존 패키지

| 패키지 | 역할 |
|---|---|
| `youtube_explode_dart` | YouTube 영상 정보 조회 및 오디오 스트림 다운로드 |
| `path_provider` | 저장 경로 |
| `permission_handler` | 권한 요청 |
| `open_filex` | 파일 열기 |
| `uuid` | 다운로드 항목 ID |
