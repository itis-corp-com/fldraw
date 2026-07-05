import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:fldraw/src/core/utils/json_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

enum EditorTool {
  arrow,
  square,
  circle,
  arrowTopRight,
  line,
  pencil,
  text,
  figure,
  comment,
  add,
  referencePoint,
}

enum Handle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  // For Arrow-based objects
  arrowStart,
  arrowEnd,
  midPoint,
  // For rotation
  rotate,
  // For no handle
  none,
}

enum LinkPathType { straight, curved, orthogonal }

/// Annotation attached to a specific vertex (start, end, or midPoint) of a
/// line or arrow.  Holds an optional free-form label and an optional distance
/// measurement string (e.g. "42 ft").
class VertexAnnotation {
  final String? label;
  final String? distance;

  const VertexAnnotation({this.label, this.distance});

  bool get isEmpty => (label == null || label!.isEmpty) && (distance == null || distance!.isEmpty);

  Map<String, dynamic> toJson() => {
    if (label != null) 'label': label,
    if (distance != null) 'distance': distance,
  };

  factory VertexAnnotation.fromJson(Map<String, dynamic> json) {
    return VertexAnnotation(
      label: json['label'] as String?,
      distance: json['distance'] as String?,
    );
  }

  VertexAnnotation copyWith({String? label, String? distance}) {
    return VertexAnnotation(
      label: label ?? this.label,
      distance: distance ?? this.distance,
    );
  }
}

abstract class DrawingObject {
  final String id;
  bool isSelected;

  DrawingObject({required this.id, this.isSelected = false});

  Rect get rect;

  Map<String, dynamic> toJson();

  DrawingObject copyWith({bool? isSelected});
}

class RectangleObject extends DrawingObject {
  Rect _rect;
  final Color? strokeColor;

  RectangleObject({required super.id, required Rect rect, this.strokeColor, super.isSelected})
    : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'rectangle',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'strokeColor': strokeColor?.toARGB32(),
  };

  factory RectangleObject.fromJson(Map<String, dynamic> json) {
    return RectangleObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, Color? strokeColor}) {
    return RectangleObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      strokeColor: strokeColor ?? this.strokeColor,
    );
  }
}

class CircleObject extends DrawingObject {
  Rect _rect;
  final Color? strokeColor;

  CircleObject({required super.id, required Rect rect, this.strokeColor, super.isSelected})
    : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'circle',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'strokeColor': strokeColor?.toARGB32(),
  };

  factory CircleObject.fromJson(Map<String, dynamic> json) {
    return CircleObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, Color? strokeColor}) {
    return CircleObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      strokeColor: strokeColor ?? this.strokeColor,
    );
  }
}

class ArrowObject extends DrawingObject {
  Offset start;
  Offset end;
  Offset? midPoint;
  final LinkPathType pathType;
  final ObjectAttachment? startAttachment;
  final ObjectAttachment? endAttachment;
  final Color? strokeColor;
  final Map<String, VertexAnnotation> vertexAnnotations;
  /// When true, the renderer paints a distance label at the arrow's
  /// midpoint. Default true; flipped via the host's selection action
  /// bar.
  final bool showMeasurement;

  ArrowObject({
    required super.id,
    required this.start,
    required this.end,
    super.isSelected,
    this.midPoint,
    this.pathType = LinkPathType.straight,
    this.startAttachment,
    this.endAttachment,
    this.strokeColor,
    this.vertexAnnotations = const {},
    this.showMeasurement = true,
  });

  @override
  Rect get rect {
    if (pathType == LinkPathType.orthogonal) {
      return Rect.fromPoints(start, end).normalize;
    }

    final points = [start, end];
    final p0 = start;
    final p1 = midPoint ?? (start + end) / 2;
    final p2 = end;

    final dX = p0.dx - 2 * p1.dx + p2.dx;
    if (dX.abs() > 1e-12) {
      final t = (p0.dx - p1.dx) / dX;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    final dY = p0.dy - 2 * p1.dy + p2.dy;
    if (dY.abs() > 1e-12) {
      final t = (p0.dy - p1.dy) / dY;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;
    for (var i = 1; i < points.length; i++) {
      minX = min(minX, points[i].dx);
      minY = min(minY, points[i].dy);
      maxX = max(maxX, points[i].dx);
      maxY = max(maxY, points[i].dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _getPointOnCurve(double t, Offset p0, Offset p1, Offset p2) {
    final s = 1 - t;
    final x = s * s * p0.dx + 2 * s * t * p1.dx + t * t * p2.dx;
    final y = s * s * p0.dy + 2 * s * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }


  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'arrow',
    'start': start.toJson(),
    'end': end.toJson(),
    if (midPoint != null) 'midPoint': midPoint!.toJson(),
    'isSelected': isSelected,
    'pathType': pathType.name,
    'startAttachment': startAttachment?.toJson(),
    'endAttachment': endAttachment?.toJson(),
    'strokeColor': strokeColor?.toARGB32(),
    if (vertexAnnotations.isNotEmpty)
      'vertexAnnotations': vertexAnnotations.map((k, v) => MapEntry(k, v.toJson())),
    'showMeasurement': showMeasurement,
  };

  factory ArrowObject.fromJson(Map<String, dynamic> json) {
    final annotationsJson = json['vertexAnnotations'] as Map<String, dynamic>?;
    return ArrowObject(
      id: json['id'],
      start: JSONOffset.fromJson((json['start'] as List).cast<double>()),
      end: JSONOffset.fromJson((json['end'] as List).cast<double>()),
      midPoint: json['midPoint'] != null
          ? JSONOffset.fromJson((json['midPoint'] as List).cast<double>())
          : null,
      isSelected: json['isSelected'] ?? false,
      pathType: LinkPathType.values.byName(json['pathType'] ?? 'straight'),
      startAttachment: json['startAttachment'] != null ? ObjectAttachment.fromJson(json['startAttachment']) : null,
      endAttachment: json['endAttachment'] != null ? ObjectAttachment.fromJson(json['endAttachment']) : null,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
      // Older diagrams default true so existing arrows start measuring.
      showMeasurement: json['showMeasurement'] as bool? ?? true,
      vertexAnnotations: annotationsJson?.map(
        (k, v) => MapEntry(k, VertexAnnotation.fromJson(v as Map<String, dynamic>)),
      ) ?? const {},
    );
  }

  @override
  DrawingObject copyWith({
    Offset? start,
    Offset? end,
    Offset? midPoint,
    bool? isSelected,
    LinkPathType? pathType,
    ObjectAttachment? startAttachment,
    ObjectAttachment? endAttachment,
    Color? strokeColor,
    bool clearStartAttachment = false,
    bool clearEndAttachment = false,
    Map<String, VertexAnnotation>? vertexAnnotations,
    bool? showMeasurement,
  }) {
    return ArrowObject(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      isSelected: isSelected ?? this.isSelected,
      midPoint: midPoint ?? this.midPoint,
      pathType: pathType ?? this.pathType,
      startAttachment: clearStartAttachment
          ? null
          : (startAttachment ?? this.startAttachment),
      endAttachment: clearEndAttachment
          ? null
          : (endAttachment ?? this.endAttachment),
      strokeColor: strokeColor ?? this.strokeColor,
      vertexAnnotations: vertexAnnotations ?? this.vertexAnnotations,
      showMeasurement: showMeasurement ?? this.showMeasurement,
    );
  }
}

class LineObject extends DrawingObject {
  Offset start;
  Offset end;
  Offset? midPoint;
  final LinkPathType pathType;
  final Color? strokeColor;
  final Map<String, VertexAnnotation> vertexAnnotations;
  /// When true, the renderer paints a distance label at the line's
  /// midpoint using the host-supplied `metersPerWorldUnit` scale. The
  /// host (kapix) defaults this to true on new lines and lets the user
  /// toggle it via the selection action bar.
  final bool showMeasurement;

  LineObject({
    required super.id,
    required this.start,
    required this.end,
    this.midPoint,
    this.pathType = LinkPathType.straight,
    this.strokeColor,
    this.vertexAnnotations = const {},
    this.showMeasurement = true,
    super.isSelected,
  });

  @override
  Rect get rect {
    final points = [start, end];
    final p0 = start;
    final p1 = midPoint ?? (start + end) / 2;
    final p2 = end;

    final dX = p0.dx - 2 * p1.dx + p2.dx;
    if (dX.abs() > 1e-12) {
      final t = (p0.dx - p1.dx) / dX;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    final dY = p0.dy - 2 * p1.dy + p2.dy;
    if (dY.abs() > 1e-12) {
      final t = (p0.dy - p1.dy) / dY;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;
    for (var i = 1; i < points.length; i++) {
      minX = min(minX, points[i].dx);
      minY = min(minY, points[i].dy);
      maxX = max(maxX, points[i].dx);
      maxY = max(maxY, points[i].dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _getPointOnCurve(double t, Offset p0, Offset p1, Offset p2) {
    final s = 1 - t;
    final x = s * s * p0.dx + 2 * s * t * p1.dx + t * t * p2.dx;
    final y = s * s * p0.dy + 2 * s * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'line',
    'start': start.toJson(),
    'end': end.toJson(),
    if (midPoint != null) 'midPoint': midPoint!.toJson(),
    'isSelected': isSelected,
    'pathType': pathType.name,
    'strokeColor': strokeColor?.toARGB32(),
    if (vertexAnnotations.isNotEmpty)
      'vertexAnnotations': vertexAnnotations.map((k, v) => MapEntry(k, v.toJson())),
    'showMeasurement': showMeasurement,
  };

  factory LineObject.fromJson(Map<String, dynamic> json) {
    final annotationsJson = json['vertexAnnotations'] as Map<String, dynamic>?;
    return LineObject(
      id: json['id'],
      start: JSONOffset.fromJson((json['start'] as List).cast<double>()),
      end: JSONOffset.fromJson((json['end'] as List).cast<double>()),
      midPoint: json['midPoint'] != null
          ? JSONOffset.fromJson((json['midPoint'] as List).cast<double>())
          : null,
      isSelected: json['isSelected'] ?? false,
      pathType: LinkPathType.values.byName(json['pathType'] ?? 'straight'),
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
      // Older diagrams without this field default to true so existing
      // lines start measuring on next open. Officers can flip it off
      // per-line via the selection action bar.
      showMeasurement: json['showMeasurement'] as bool? ?? true,
      vertexAnnotations: annotationsJson?.map(
        (k, v) => MapEntry(k, VertexAnnotation.fromJson(v as Map<String, dynamic>)),
      ) ?? const {},
    );
  }

  @override
  DrawingObject copyWith({
    Offset? start,
    Offset? end,
    Offset? midPoint,
    bool? isSelected,
    LinkPathType? pathType,
    Color? strokeColor,
    Map<String, VertexAnnotation>? vertexAnnotations,
    bool? showMeasurement,
  }) {
    return LineObject(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      midPoint: midPoint ?? this.midPoint,
      isSelected: isSelected ?? this.isSelected,
      pathType: pathType ?? this.pathType,
      strokeColor: strokeColor ?? this.strokeColor,
      vertexAnnotations: vertexAnnotations ?? this.vertexAnnotations,
      showMeasurement: showMeasurement ?? this.showMeasurement,
    );
  }
}

class PencilStrokeObject extends DrawingObject {
  List<PointVector> points;
  Path? cachedPath;
  final Color? strokeColor;

  PencilStrokeObject({
    required super.id,
    required this.points,
    this.strokeColor,
    super.isSelected,
  });

  @override
  Rect get rect {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (final point in points) {
      minX = min(minX, point.x);
      maxX = max(maxX, point.x);
      minY = min(minY, point.y);
      maxY = max(maxY, point.y);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  set start(Offset _) {}

  set end(Offset _) {}

  set midPoint(Offset? _) {}

  Offset get start =>
      points.isNotEmpty ? Offset(points.first.x, points.first.y) : Offset.zero;

  Offset get end =>
      points.isNotEmpty ? Offset(points.last.x, points.last.y) : Offset.zero;

  Offset? get midPoint => null;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'pencil_stroke',
    'points': points.map((p) => [p.x, p.y, p.pressure]).toList(),
    'isSelected': isSelected,
    'strokeColor': strokeColor?.toARGB32(),
  };

  factory PencilStrokeObject.fromJson(Map<String, dynamic> json) {
    return PencilStrokeObject(
      id: json['id'],
      points: (json['points'] as List)
          .map(
            (p) => PointVector(p[0], p[1], p.length > 2 ? p[2] : 0.5),
          ) // Default pressure if null
          .toList(),
      isSelected: json['isSelected'] ?? false,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  @override
  DrawingObject copyWith({List<PointVector>? points, bool? isSelected, Color? strokeColor}) {
    return PencilStrokeObject(
      id: id,
      points: points ?? this.points,
      isSelected: isSelected ?? this.isSelected,
      strokeColor: strokeColor ?? this.strokeColor,
    );
  }
}

class FigureObject extends DrawingObject {
  Rect _rect;
  String label;
  Set<String> childrenIds;

  FigureObject({
    required super.id,
    required Rect rect,
    this.label = "Figure",
    this.childrenIds = const {},
    super.isSelected,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'figure',
    'rect': _rect.toJson(),
    'label': label,
    'childrenIds': childrenIds.toList(),
    'isSelected': isSelected,
  };

  factory FigureObject.fromJson(Map<String, dynamic> json) {
    return FigureObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      label: json['label'] ?? "Figure",
      childrenIds: (json['childrenIds'] as List<dynamic>)
          .cast<String>()
          .toSet(),
      isSelected: json['isSelected'] ?? false,
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    String? label,
    Set<String>? childrenIds,
    bool? isSelected,
  }) {
    return FigureObject(
      id: id,
      rect: rect ?? _rect,
      label: label ?? this.label,
      childrenIds: childrenIds ?? this.childrenIds,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FigureObject &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _rect == other._rect &&
          label == other.label &&
          setEquals(childrenIds, other.childrenIds) &&
          isSelected == other.isSelected;

  @override
  int get hashCode =>
      id.hashCode ^
      _rect.hashCode ^
      label.hashCode ^
      childrenIds.hashCode ^
      isSelected.hashCode;
}

class TextObject extends DrawingObject {
  Rect _rect;
  String text;
  TextStyle style;
  bool isEditing;
  /// Milliseconds since epoch when the note was created or last edited.
  int? timestamp;

  TextObject({
    required super.id,
    required Rect rect,
    this.text = 'Text',
    this.style = const TextStyle(fontSize: 16, color: Colors.white),
    this.isEditing = false,
    this.timestamp,
    super.isSelected,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'text',
    'rect': _rect.toJson(),
    'text': text,
    'style': {'fontSize': style.fontSize, 'color': style.color?.value},
    'isSelected': isSelected,
    if (timestamp != null) 'timestamp': timestamp,
  };

  factory TextObject.fromJson(Map<String, dynamic> json) {
    final styleJson = json['style'] as Map<String, dynamic>?;
    return TextObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      text: json['text'] ?? 'Text',
      style: TextStyle(
        fontSize: styleJson?['fontSize'] as double? ?? 16,
        color: styleJson?['color'] != null
            ? Color(styleJson!['color'] as int)
            : Colors.white,
      ),
      isSelected: json['isSelected'] ?? false,
      timestamp: json['timestamp'] as int?,
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    String? text,
    TextStyle? style,
    bool? isSelected,
    bool? isEditing,
    int? timestamp,
  }) {
    return TextObject(
      id: id,
      rect: rect ?? _rect,
      text: text ?? this.text,
      style: style ?? this.style,
      isSelected: isSelected ?? this.isSelected,
      isEditing: isEditing ?? this.isEditing,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class SvgObject extends DrawingObject {
  Rect _rect;
  final String assetPath;
  PictureInfo? pictureInfo;
  double rotation; // radians
  String label;
  /// Free-form text annotation displayed below the unit badge.
  String annotation;
  final Color? tintColor;
  /// Damage/impact marks as relative positions (0,0)=topLeft, (1,1)=bottomRight.
  final List<Offset> damageMarks;

  SvgObject({
    required super.id,
    required Rect rect,
    required this.assetPath,
    this.pictureInfo,
    this.rotation = 0.0,
    this.label = '',
    this.annotation = '',
    this.tintColor,
    this.damageMarks = const [],
    super.isSelected,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  @override
  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'svg',
    'rect': _rect.toJson(),
    'assetPath': assetPath,
    'rotation': rotation,
    'label': label,
    if (annotation.isNotEmpty) 'annotation': annotation,
    'tintColor': tintColor?.toARGB32(),
    'isSelected': isSelected,
    if (damageMarks.isNotEmpty)
      'damageMarks': damageMarks.map((o) => [o.dx, o.dy]).toList(),
  };

  factory SvgObject.fromJson(Map<String, dynamic> json) {
    return SvgObject(
      id: json['id'] as String,
      rect: JSONRect.fromJson(json['rect']),
      assetPath: json['assetPath'] as String,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      label: json['label'] as String? ?? '',
      annotation: json['annotation'] as String? ?? '',
      tintColor: json['tintColor'] != null ? Color(json['tintColor'] as int) : null,
      isSelected: json['isSelected'] as bool? ?? false,
      damageMarks: (json['damageMarks'] as List<dynamic>?)
          ?.map((e) => Offset((e[0] as num).toDouble(), (e[1] as num).toDouble()))
          .toList() ?? const [],
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    double? rotation,
    String? label,
    String? annotation,
    Color? tintColor,
    bool? isSelected,
    List<Offset>? damageMarks,
  }) {
    return SvgObject(
      id: id,
      rect: rect ?? _rect,
      assetPath: assetPath,
      pictureInfo: pictureInfo,
      rotation: rotation ?? this.rotation,
      label: label ?? this.label,
      annotation: annotation ?? this.annotation,
      tintColor: tintColor ?? this.tintColor,
      isSelected: isSelected ?? this.isSelected,
      damageMarks: damageMarks ?? this.damageMarks,
    );
  }
}

class ReferencePointObject extends DrawingObject {
  Offset position;
  final double radius;

  ReferencePointObject({
    required super.id,
    required this.position,
    this.radius = 6.0,
    super.isSelected,
  });

  @override
  Rect get rect => Rect.fromCircle(center: position, radius: radius);

  set rect(Rect newRect) {
    position = newRect.center;
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'referencePoint',
    'position': position.toJson(),
    'radius': radius,
    'isSelected': isSelected,
  };

  factory ReferencePointObject.fromJson(Map<String, dynamic> json) {
    return ReferencePointObject(
      id: json['id'] as String,
      position: JSONOffset.fromJson((json['position'] as List).cast<double>()),
      radius: (json['radius'] as num?)?.toDouble() ?? 6.0,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }

  @override
  DrawingObject copyWith({Offset? position, double? radius, bool? isSelected}) {
    return ReferencePointObject(
      id: id,
      position: position ?? this.position,
      radius: radius ?? this.radius,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class TempDrawingObject {
  final EditorTool tool;
  final Offset start;
  final Offset end;
  final LinkPathType pathType;
  final List<PointVector> points;

  TempDrawingObject({
    required this.tool,
    required this.start,
    required this.end,
    this.points = const [],
    this.pathType = LinkPathType.straight,
  });

  TempDrawingObject copyWith({
    Offset? end,
    List<PointVector>? points,
    LinkPathType? pathType,
  }) {
    return TempDrawingObject(
      tool: tool,
      start: start,
      end: end ?? this.end,
      points: points ?? this.points,
      pathType: pathType ?? this.pathType,
    );
  }
}

class ObjectAttachment extends Equatable {
  final String objectId;
  // An offset where (0,0) is topLeft and (1,1) is bottomRight of the target object's rect.
  final Offset relativePosition;

  const ObjectAttachment({required this.objectId, required this.relativePosition});

  @override
  List<Object> get props => [objectId, relativePosition];

  Map<String, dynamic> toJson() => {
    'objectId': objectId,
    'relativePosition': [relativePosition.dx, relativePosition.dy],
  };

  factory ObjectAttachment.fromJson(Map<String, dynamic> json) {
    return ObjectAttachment(
      objectId: json['objectId'],
      relativePosition: Offset(json['relativePosition'][0], json['relativePosition'][1]),
    );
  }
}
