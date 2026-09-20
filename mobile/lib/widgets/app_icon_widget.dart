import 'package:flutter/material.dart';

/// 앱 아이콘 - 헤더용 인라인 렌더링 버전
class AppIconWidget extends StatelessWidget {
  final double size;
  const AppIconWidget({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
    );
  }
}
