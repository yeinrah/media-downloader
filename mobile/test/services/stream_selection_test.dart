import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/services/stream_selection.dart';

void main() {
  test('returns null for empty candidate list', () {
    expect(selectVideoStream([], 720), isNull);
  });

  test('picks exact height match', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 360, bitrateBitsPerSecond: 500000),
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 2000000),
    ];
    final result = selectVideoStream(candidates, 720);
    expect(result!.candidateIndex, 1);
    expect(result.appliedHeightPx, 720);
  });

  test('falls back to highest height at or below requested when exact match missing', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 360, bitrateBitsPerSecond: 500000),
      VideoStreamCandidate(heightPx: 480, bitrateBitsPerSecond: 900000),
      VideoStreamCandidate(heightPx: 1080, bitrateBitsPerSecond: 5000000),
    ];
    final result = selectVideoStream(candidates, 720);
    expect(result!.candidateIndex, 1);
    expect(result.appliedHeightPx, 480);
  });

  test('falls back to lowest available height when all candidates exceed requested', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 2000000),
      VideoStreamCandidate(heightPx: 1080, bitrateBitsPerSecond: 5000000),
    ];
    final result = selectVideoStream(candidates, 360);
    expect(result!.candidateIndex, 0);
    expect(result.appliedHeightPx, 720);
  });

  test('picks highest bitrate among candidates that share the chosen height', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 1500000),
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 2500000),
    ];
    final result = selectVideoStream(candidates, 720);
    expect(result!.candidateIndex, 1);
    expect(result.appliedHeightPx, 720);
  });
}
