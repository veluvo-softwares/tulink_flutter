import 'package:flutter/widgets.dart';

/// Shared adaptive layout rules for phones, tablets and resizable Apple
/// Silicon app windows.
abstract final class TulinkBreakpoints {
  static const double tablet = 720;
  static const double wide = 900;

  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= tablet;
  }

  static bool isWideLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Use the same landscape composition on phones and tablets.
    return size.width > size.height;
  }

  static double readableContentWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= wide ? 520 : 600;
  }
}
