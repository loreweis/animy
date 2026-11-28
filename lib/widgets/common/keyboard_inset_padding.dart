import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Isolates `MediaQuery.viewInsetsOf(context).bottom` updates so only this
/// lightweight [Padding] rebuilds during keyboard animations while [child]
/// stays untouched and never rebuilds.
class KeyboardInsetPadding extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool includeSafeBottom;
  final double extraBottomWhenClosed;

  const KeyboardInsetPadding({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.includeSafeBottom = false,
    this.extraBottomWhenClosed = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = keyboardInset > 0
        ? keyboardInset
        : (includeSafeBottom
            ? math.max(
                MediaQuery.paddingOf(context).bottom,
                extraBottomWhenClosed,
              )
            : extraBottomWhenClosed);
    return Padding(
      padding: padding.add(EdgeInsets.only(bottom: bottomPadding)),
      child: child,
    );
  }
}
