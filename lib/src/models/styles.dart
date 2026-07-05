import 'package:flutter/material.dart';

import 'package:fldraw/src/models/entities.dart';

enum FlLineDrawMode { solid, dashed, dotted }

class FlGridStyle {
  final double gridSpacingX;
  final double gridSpacingY;
  final double lineWidth;
  final Color lineColor;
  final Color intersectionColor;
  final double intersectionRadius;
  final bool showGrid;

  const FlGridStyle({
    this.gridSpacingX = 64.0,
    this.gridSpacingY = 64.0,
    this.lineWidth = 1.0,
    this.lineColor = const Color.fromARGB(64, 100, 100, 100),
    this.intersectionColor = const Color.fromARGB(128, 150, 150, 150),
    this.intersectionRadius = 2,
    this.showGrid = true,
  });

  FlGridStyle copyWith({
    double? gridSpacingX,
    double? gridSpacingY,
    double? lineWidth,
    Color? lineColor,
    Color? intersectionColor,
    double? intersectionRadius,
    bool? showGrid,
  }) {
    return FlGridStyle(
      gridSpacingX: gridSpacingX ?? this.gridSpacingX,
      gridSpacingY: gridSpacingY ?? this.gridSpacingY,
      lineWidth: lineWidth ?? this.lineWidth,
      lineColor: lineColor ?? this.lineColor,
      intersectionColor: intersectionColor ?? this.intersectionColor,
      intersectionRadius: intersectionRadius ?? this.intersectionRadius,
      showGrid: showGrid ?? this.showGrid,
    );
  }
}

class FlSelectionAreaStyle {
  final Color color;
  final double borderWidth;
  final Color borderColor;
  final FlLineDrawMode borderDrawMode;

  const FlSelectionAreaStyle({
    this.color = const Color.fromARGB(25, 33, 150, 243),
    this.borderWidth = 1.0,
    this.borderColor = const Color.fromARGB(255, 33, 150, 243),
    this.borderDrawMode = FlLineDrawMode.solid,
  });

  FlSelectionAreaStyle copyWith({
    Color? color,
    double? borderWidth,
    Color? borderColor,
    FlLineDrawMode? borderDrawMode,
  }) {
    return FlSelectionAreaStyle(
      color: color ?? this.color,
      borderWidth: borderWidth ?? this.borderWidth,
      borderColor: borderColor ?? this.borderColor,
      borderDrawMode: borderDrawMode ?? this.borderDrawMode,
    );
  }
}

enum FlLinkCurveType { straight, bezier, ninetyDegree }

class FlLinkStyle {
  final Color? color;
  final bool useGradient;
  final LinearGradient? gradient;
  final double lineWidth;
  final FlLineDrawMode drawMode;
  final FlLinkCurveType curveType;

  const FlLinkStyle({
    this.color,
    this.useGradient = false,
    this.gradient,
    required this.lineWidth,
    required this.drawMode,
    required this.curveType,
  }) : assert(
         useGradient == false || gradient != null,
         'Gradient must be provided if useGradient is true',
       );

  FlLinkStyle copyWith({
    LinearGradient? gradient,
    double? lineWidth,
    FlLineDrawMode? drawMode,
    FlLinkCurveType? curveType,
  }) {
    return FlLinkStyle(
      gradient: gradient ?? this.gradient,
      lineWidth: lineWidth ?? this.lineWidth,
      drawMode: drawMode ?? this.drawMode,
      curveType: curveType ?? this.curveType,
    );
  }
}

class FlNodeHeaderStyle {
  final EdgeInsets padding;
  final BoxDecoration decoration;
  final TextStyle textStyle;
  final IconData? icon;

  const FlNodeHeaderStyle({
    required this.padding,
    required this.decoration,
    required this.textStyle,
    required this.icon,
  });

  FlNodeHeaderStyle copyWith({
    EdgeInsets? padding,
    BoxDecoration? decoration,
    TextStyle? textStyle,
    IconData? icon,
  }) {
    return FlNodeHeaderStyle(
      padding: padding ?? this.padding,
      decoration: decoration ?? this.decoration,
      textStyle: textStyle ?? this.textStyle,
      icon: icon ?? this.icon,
    );
  }
}

typedef FlNodeHeaderStyleBuilder = FlNodeHeaderStyle Function(NodeState style);

FlNodeHeaderStyle defaultNodeHeaderStyle(NodeState state) {
  return FlNodeHeaderStyle(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    textStyle: TextStyle(fontSize: 16),
    decoration: BoxDecoration(
      color: Color(0xFF27272A),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
        bottomLeft: Radius.circular(state.isCollapsed ? 7 : 0),
        bottomRight: Radius.circular(state.isCollapsed ? 7 : 0),
      ),
    ),
    icon: state.isCollapsed ? Icons.expand_more : Icons.expand_less,
  );
}

class FlNodeStyle {
  final BoxDecoration decoration;

  const FlNodeStyle({required this.decoration});

  FlNodeStyle copyWith({BoxDecoration? decoration}) {
    return FlNodeStyle(decoration: decoration ?? this.decoration);
  }
}

typedef FlNodeStyleBuilder = FlNodeStyle Function(NodeState style);

FlNodeStyle defaultNodeStyle(NodeState state) {
  return const FlNodeStyle(
    decoration: BoxDecoration(
      color: Color(0xFF27272A),
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
  );
}

class FlDrawEditorStyle {
  final BoxDecoration decoration;
  final EdgeInsetsGeometry padding;
  final FlGridStyle gridStyle;
  final FlSelectionAreaStyle selectionAreaStyle;

  /// When set, applies a [BlendMode.srcIn] color filter to all SVG objects,
  /// tinting them this color. Useful for making dark SVGs visible on dark
  /// backgrounds (satellite maps) or vice versa.
  final Color? svgTintColor;

  /// Default stroke color for drawing objects (lines, rectangles, circles,
  /// pencil strokes, arrows). Individual objects can override via their own
  /// `strokeColor` field. Falls back to [Colors.white] when null.
  final Color? defaultStrokeColor;

  /// Real-world meters per canvas world unit at the current map zoom.
  /// Used by the reference-point distance label to display accurate
  /// measurements. When null, falls back to a default approximation.
  final double? metersPerWorldUnit;

  /// Color used for measurement and vertex-annotation text. Hosts can
  /// lerp this from white→black based on any background-blend signal
  /// (e.g. an opacity slider that fades a diagram render onto a
  /// satellite image) so labels stay legible. Falls back to
  /// [defaultStrokeColor] or white when null.
  final Color? labelColor;

  /// When true, an SvgObject's [annotation] (e.g. its type name) is drawn as a
  /// small label below the asset. Hosts toggle this on/off.
  final bool showAssetLabels;

  /// When true, line-art assets (with a synthesised [SvgObject.bodyImage]) are
  /// drawn as a solid filled body with line detail over it; when false they
  /// render as the original wireframe/line art.
  final bool filledAssets;

  const FlDrawEditorStyle({
    this.decoration = const BoxDecoration(color: Colors.black12),
    this.padding = const EdgeInsets.all(8.0),
    this.gridStyle = const FlGridStyle(),
    this.selectionAreaStyle = const FlSelectionAreaStyle(),
    this.svgTintColor,
    this.defaultStrokeColor,
    this.metersPerWorldUnit,
    this.labelColor,
    this.showAssetLabels = false,
    this.filledAssets = false,
  });

  FlDrawEditorStyle copyWith({
    BoxDecoration? decoration,
    EdgeInsetsGeometry? padding,
    FlGridStyle? gridStyle,
    FlSelectionAreaStyle? selectionAreaStyle,
    Color? svgTintColor,
    Color? defaultStrokeColor,
    double? metersPerWorldUnit,
    Color? labelColor,
    bool? showAssetLabels,
    bool? filledAssets,
  }) {
    return FlDrawEditorStyle(
      decoration: decoration ?? this.decoration,
      padding: padding ?? this.padding,
      gridStyle: gridStyle ?? this.gridStyle,
      selectionAreaStyle: selectionAreaStyle ?? this.selectionAreaStyle,
      svgTintColor: svgTintColor ?? this.svgTintColor,
      defaultStrokeColor: defaultStrokeColor ?? this.defaultStrokeColor,
      metersPerWorldUnit: metersPerWorldUnit ?? this.metersPerWorldUnit,
      labelColor: labelColor ?? this.labelColor,
      showAssetLabels: showAssetLabels ?? this.showAssetLabels,
      filledAssets: filledAssets ?? this.filledAssets,
    );
  }
}
