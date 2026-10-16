import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PbSvgIcon extends StatelessWidget {
  const PbSvgIcon({super.key, required this.assetName, this.size, this.width, this.height, required this.color})
    : assert(size != null || (width != null && height != null));

  final String assetName;
  final double? size;
  final double? width;
  final double? height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'lib/storage/powerboards/assets/icons/$assetName.svg',
      package: 'meshagent_flutter_shadcn',
      width: width ?? size,
      height: height ?? size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
