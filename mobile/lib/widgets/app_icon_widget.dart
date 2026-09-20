import 'package:flutter/material.dart';

/// 앱 아이콘 - 헤더용 인라인 렌더링 버전
class AppIconWidget extends StatelessWidget {
  final double size;
  const AppIconWidget({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _IconPainter(),
    );
  }
}

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    // 배경 - 둥근 사각형
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFF7C6FF7), Color(0xFF4ECDC4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, s, s));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(s * 0.24),
      ),
      bgPaint,
    );

    // 음표 그리기
    final notePaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.fill;

    // 음표 기둥
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.56, s * 0.22, s * 0.09, s * 0.42),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(stemRect, notePaint);

    // 음표 머리 (타원)
    canvas.save();
    canvas.translate(s * 0.46, s * 0.60);
    canvas.rotate(-0.4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * 0.22, height: s * 0.17),
      notePaint,
    );
    canvas.restore();

    // 가로 빔 (비트 느낌의 파형 곡선)
    final wavePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(s * 0.18, s * 0.60);
    path.cubicTo(
      s * 0.26, s * 0.48,
      s * 0.34, s * 0.72,
      s * 0.42, s * 0.60,
    );
    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(_IconPainter old) => false;
}
