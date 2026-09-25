/// `-y`는 임시 파일명이 우연히 겹칠 때 ffmpeg가 대화형 덮어쓰기 확인으로
/// 멈추는 것을 막기 위해 항상 포함한다.
List<String> buildMp3EncodeArgs({
  required String audioInputPath,
  required String outputPath,
  required int bitrateKbps,
}) {
  return [
    '-y',
    '-i', audioInputPath,
    '-vn',
    '-b:a', '${bitrateKbps}k',
    outputPath,
  ];
}

List<String> buildMp4MuxArgs({
  required String videoInputPath,
  required String audioInputPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-i', videoInputPath,
    '-i', audioInputPath,
    '-c:v', 'copy',
    '-c:a', 'aac',
    outputPath,
  ];
}
