import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient? gradient;

  const GradientText(this.text, {super.key, this.style, this.gradient});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          (gradient ?? AppColors.goldenGradient).createShader(bounds),
      child: Text(
        text,
        style:
            style?.copyWith(color: Colors.white) ??
            const TextStyle(color: Colors.white),
      ),
    );
  }
}
