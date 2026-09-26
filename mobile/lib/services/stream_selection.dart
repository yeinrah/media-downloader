class VideoStreamCandidate {
  final int heightPx;
  final int bitrateBitsPerSecond;

  const VideoStreamCandidate({
    required this.heightPx,
    required this.bitrateBitsPerSecond,
  });
}

class VideoStreamSelectionResult {
  final int candidateIndex;
  final int appliedHeightPx;

  const VideoStreamSelectionResult({
    required this.candidateIndex,
    required this.appliedHeightPx,
  });
}

/// 요청 화질 이하 중 가장 높은 화질을 우선 선택한다. 요청 화질 이하가 하나도
/// 없으면(모든 후보가 요청보다 고화질인 경우) 사용 가능한 가장 낮은 화질로
/// 대체한다. 같은 높이의 후보가 여러 개면 비트레이트가 가장 높은 것을 고른다.
VideoStreamSelectionResult? selectVideoStream(
  List<VideoStreamCandidate> candidates,
  int requestedHeightPx,
) {
  if (candidates.isEmpty) return null;

  final atOrBelow = <int>[
    for (var i = 0; i < candidates.length; i++)
      if (candidates[i].heightPx <= requestedHeightPx) i,
  ];

  final pool = atOrBelow.isNotEmpty
      ? atOrBelow
      : List.generate(candidates.length, (i) => i);

  final heights = pool.map((i) => candidates[i].heightPx);
  final targetHeight =
      atOrBelow.isNotEmpty ? heights.reduce((a, b) => a > b ? a : b) : heights.reduce((a, b) => a < b ? a : b);

  final sameHeight = pool.where((i) => candidates[i].heightPx == targetHeight).toList()
    ..sort((a, b) =>
        candidates[b].bitrateBitsPerSecond.compareTo(candidates[a].bitrateBitsPerSecond));

  final chosen = sameHeight.first;
  return VideoStreamSelectionResult(
    candidateIndex: chosen,
    appliedHeightPx: candidates[chosen].heightPx,
  );
}
