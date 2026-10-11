import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Screen breakpoint definitions for adaptive multi-device UI.
class ResponsiveBreakpoints {
  static const double compact = 360.0;
  static const double mobile = 600.0;
  static const double tablet = 900.0;
  static const double desktop = 1200.0;
}

/// Extension on [BuildContext] for responsive layout queries and adaptive sizing.
extension ResponsiveContext on BuildContext {
  /// Screen size shortcuts
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;

  /// Breakpoint checks
  bool get isCompact => screenWidth < ResponsiveBreakpoints.compact;
  bool get isMobile => screenWidth < ResponsiveBreakpoints.mobile;
  bool get isTablet =>
      screenWidth >= ResponsiveBreakpoints.mobile &&
      screenWidth < ResponsiveBreakpoints.tablet;
  bool get isDesktop => screenWidth >= ResponsiveBreakpoints.tablet;
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// Dynamic horizontal padding adapting from 12px on tiny phones to 32px on desktop
  double get responsiveHorizontalPadding {
    if (isCompact) return 12.0;
    if (isMobile) return 16.0;
    if (isTablet) return 24.0;
    return 32.0;
  }

  /// Dynamic card padding
  double get responsiveCardPadding {
    if (isCompact) return 14.0;
    if (isMobile) return 18.0;
    return 24.0;
  }

  /// Resolves an adaptive value based on current device screen width
  T responsiveValue<T>({
    required T mobile,
    T? tablet,
    T? desktop,
    T? compact,
  }) {
    if (isCompact && compact != null) return compact;
    if (isDesktop && desktop != null) return desktop;
    if (isTablet && tablet != null) return tablet;
    return mobile;
  }

  /// Clamps a width to a safe readable maximum for tablets/desktops
  double maxContentWidth([double max = 960.0]) {
    return math.min(screenWidth, max);
  }
}

/// A responsive wrapper widget that automatically applies max-width constraints
/// and centered alignment on tablets and desktop monitors.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 960.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ??
              EdgeInsets.symmetric(
                horizontal: context.responsiveHorizontalPadding,
                vertical: context.isMobile ? 12.0 : 20.0,
              ),
          child: child,
        ),
      ),
    );
  }
}
