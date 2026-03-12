import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Gradient? gradient;

  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 24.0,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) {
        return (gradient ?? AppColors.goldenGradient).createShader(bounds);
      },
      child: Icon(
        icon,
        size: size,
        color: Colors.white, // The gradient will replace this
      ),
    );
  }
}
