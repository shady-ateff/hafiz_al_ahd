import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AppLoader extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit? fit;

  const AppLoader({
    super.key,
    this.width,
    this.height,
    this.fit,
  });

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      "assets/lotties/hafez_loader.json",
      width: width,
      height: height,
      fit: fit,
    );
  }
}