import 'package:flutter/material.dart';

import 'game_preview_controller.dart';

export 'game_preview_controller.dart';
export 'game_tools.dart';

class PocketGamePreview extends StatelessWidget {
  const PocketGamePreview({super.key, required this.controller});
  final GamePreviewController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ColoredBox(
      color: const Color(0xff0b1020),
      child: controller.buildView(),
    ),
  );
}
