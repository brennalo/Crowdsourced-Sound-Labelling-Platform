import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';

/// The "your forest" hero — a tree that grows in visible stages as the
/// contributor uploads more recordings. Every [treeThreshold] recordings
/// completes one tree and a new one starts growing behind it, so over time
/// this becomes an actual small forest rather than one tree scaling forever.
///
/// Entirely procedural (CustomPainter) — no external illustration assets
/// required. If you later want richer artwork, this is the single widget to
/// swap out for an SVG/Lottie sequence; [ForestStage] below gives you the
/// discrete stage index to key frames/animations off of.
class ForestHero extends StatelessWidget {
  final int recordingsCount;

  const ForestHero({super.key, required this.recordingsCount});

  static const int treeThreshold = 30;

  int get completedTrees => recordingsCount ~/ treeThreshold;
  int get _remainder => recordingsCount % treeThreshold;
  ForestStage get currentStage => ForestStage.forCount(_remainder);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: CustomPaint(
        painter: _ForestPainter(
          stage: currentStage,
          completedTrees: completedTrees,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

enum ForestStage {
  soil, // 0 recordings toward this tree
  sprout, // 1-4
  sapling, // 5-14
  young, // 15-29
  full; // hit threshold — about to roll over into a new tree

  static ForestStage forCount(int remainder) {
    if (remainder == 0) return ForestStage.soil;
    if (remainder < 5) return ForestStage.sprout;
    if (remainder < 15) return ForestStage.sapling;
    return ForestStage.young;
  }

  String get label {
    switch (this) {
      case ForestStage.soil:
        return 'Ready to plant';
      case ForestStage.sprout:
        return 'Sprout';
      case ForestStage.sapling:
        return 'Sapling';
      case ForestStage.young:
        return 'Young tree';
      case ForestStage.full:
        return 'Full tree';
    }
  }
}

class _ForestPainter extends CustomPainter {
  final ForestStage stage;
  final int completedTrees;

  _ForestPainter({required this.stage, required this.completedTrees});

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.82;

    _drawSky(canvas, size);
    _drawGround(canvas, size, groundY);
    _drawBackgroundTrees(canvas, size, groundY);
    _drawMainTree(canvas, size, groundY);
  }

  void _drawSky(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.mossLight.withOpacity(0.35),
          AppColors.mossLight.withOpacity(0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _drawGround(Canvas canvas, Size size, double groundY) {
    final paint = Paint()..color = AppColors.mossLight.withOpacity(0.6);
    final path = Path()
      ..moveTo(0, groundY + 18)
      ..quadraticBezierTo(
          size.width * 0.5, groundY - 6, size.width, groundY + 18)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawBackgroundTrees(Canvas canvas, Size size, double groundY) {
    if (completedTrees == 0) return;
    // Cap how many silhouettes we draw so it doesn't get visually noisy —
    // beyond a handful, the count is still shown in the stat row below.
    final visible = math.min(completedTrees, 6);
    final spacing = size.width / (visible + 1);
    for (var i = 0; i < visible; i++) {
      final cx = spacing * (i + 1);
      final scale = 0.34 + (i.isEven ? 0.02 : -0.02);
      _paintTree(
        canvas,
        center: Offset(cx, groundY),
        trunkHeight: size.height * 0.22 * scale * 3,
        foliageRadius: size.height * 0.16 * scale * 3,
        trunkColor: AppColors.bark.withOpacity(0.55),
        foliageColor: AppColors.canopy.withOpacity(0.35),
        foliageLayers: 3,
      );
    }
  }

  void _drawMainTree(Canvas canvas, Size size, double groundY) {
    final cx = size.width * 0.5;

    switch (stage) {
      case ForestStage.soil:
        // Bare mound + a single seed mark — nothing planted yet this cycle.
        final paint = Paint()..color = AppColors.bark.withOpacity(0.5);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, groundY + 6), width: 46, height: 14),
          paint,
        );
        final seedPaint = Paint()..color = AppColors.canopyDark;
        canvas.drawCircle(Offset(cx, groundY - 2), 3.5, seedPaint);
        return;

      case ForestStage.sprout:
        _paintSprout(canvas, Offset(cx, groundY));
        return;

      case ForestStage.sapling:
        _paintTree(
          canvas,
          center: Offset(cx, groundY),
          trunkHeight: size.height * 0.22,
          foliageRadius: size.height * 0.14,
          trunkColor: AppColors.bark,
          foliageColor: AppColors.moss,
          foliageLayers: 2,
        );
        return;

      case ForestStage.young:
      case ForestStage.full:
        _paintTree(
          canvas,
          center: Offset(cx, groundY),
          trunkHeight: size.height * 0.34,
          foliageRadius: size.height * 0.22,
          trunkColor: AppColors.bark,
          foliageColor: AppColors.canopy,
          foliageLayers: 4,
        );
        return;
    }
  }

  void _paintSprout(Canvas canvas, Offset base) {
    final stemPaint = Paint()
      ..color = AppColors.canopy
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final tip = base.translate(0, -26);
    canvas.drawLine(base, tip, stemPaint);

    final leafPaint = Paint()..color = AppColors.moss;
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(-0.5);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 22, height: 12), leafPaint);
    canvas.restore();

    canvas.save();
    canvas.translate(tip.dx, tip.dy + 4);
    canvas.rotate(0.5);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 10), leafPaint);
    canvas.restore();
  }

  void _paintTree(
    Canvas canvas, {
    required Offset center,
    required double trunkHeight,
    required double foliageRadius,
    required Color trunkColor,
    required Color foliageColor,
    required int foliageLayers,
  }) {
    final trunkPaint = Paint()..color = trunkColor;
    final trunkWidth = trunkHeight * 0.16;
    final trunkRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, -trunkHeight / 2),
        width: trunkWidth,
        height: trunkHeight,
      ),
      Radius.circular(trunkWidth / 2),
    );
    canvas.drawRRect(trunkRect, trunkPaint);

    final crownCenter = center.translate(0, -trunkHeight);
    final foliagePaint = Paint()..color = foliageColor;
    final rnd = math.Random(foliageLayers * 97);

    for (var layer = 0; layer < foliageLayers; layer++) {
      final layerRadius = foliageRadius * (1 - layer * 0.12);
      final blobs = 3 + layer;
      for (var b = 0; b < blobs; b++) {
        final angle = (2 * math.pi / blobs) * b + rnd.nextDouble() * 0.4;
        final dist = layerRadius * 0.45;
        final offset = crownCenter.translate(
          math.cos(angle) * dist,
          math.sin(angle) * dist * 0.6 - layer * foliageRadius * 0.28,
        );
        canvas.drawCircle(
          offset,
          layerRadius * 0.55,
          foliagePaint..color = foliageColor.withOpacity(0.85 + layer * 0.03),
        );
      }
    }
    // Central mass to keep the crown looking solid rather than a ring of dots.
    canvas.drawCircle(
      crownCenter.translate(0, -foliageRadius * 0.25),
      foliageRadius * 0.62,
      foliagePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ForestPainter oldDelegate) {
    return oldDelegate.stage != stage ||
        oldDelegate.completedTrees != completedTrees;
  }
}
