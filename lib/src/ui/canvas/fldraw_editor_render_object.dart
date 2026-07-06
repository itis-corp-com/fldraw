import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/core/utils/json_extensions.dart';
import 'package:fldraw/src/core/utils/renderbox.dart';
import 'package:fldraw/src/core/utils/spatial_hash_grid.dart';
import 'package:fldraw/src/models/drawing_entities.dart';
import 'package:fldraw/src/ui/nodes/node_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

class NodeDiffCheckData {
  final String id;
  final Offset offset;
  final NodeState state;

  NodeDiffCheckData({
    required this.id,
    required this.offset,
    required this.state,
  });
}

class _ParentData extends ContainerBoxParentData<RenderBox> {
  String id = '';
  Offset nodeOffset = Offset.zero;
  NodeState state = NodeState();
  Rect rect = Rect.zero;
}

class FlDrawEditorRenderObjectWidget extends MultiChildRenderObjectWidget {
  final CanvasState canvasState;
  final SelectionState selectionState;
  final FlDrawEditorStyle style;
  final FragmentShader gridShader;
  final TempDrawingObject? tempDrawingObject;
  final Rect selectionArea;
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final Offset? snapHandlePosition;

  FlDrawEditorRenderObjectWidget({
    super.key,
    required this.canvasState,
    required this.selectionState,
    required this.style,
    required this.gridShader,
    this.tempDrawingObject,
    required this.selectionArea,
    this.headerBuilder,
    this.nodeBuilder,
    this.snapHandlePosition,
  }) : super(
         children: canvasState.nodes.values.map((node) {
           node.state.isSelected = selectionState.selectedNodeIds.contains(
             node.id,
           );
           return DefaultNodeWidget(
             node: node,
             headerBuilder: headerBuilder,
             nodeBuilder: nodeBuilder,
           );
         }).toList(),
       );

  @override
  FlDrawEditorRenderBox createRenderObject(BuildContext context) {
    return FlDrawEditorRenderBox(
      style: style,
      gridShader: gridShader,
      canvasState: canvasState,
      selectionState: selectionState,
      selectionArea: selectionArea,
      nodesData: _getNodeDrawData(),
      tempDrawingObject: tempDrawingObject,
      snapHandlePosition: snapHandlePosition,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    FlDrawEditorRenderBox renderObject,
  ) {
    renderObject
      ..style = style
      ..canvasState = canvasState
      ..selectionState = selectionState
      ..selectionArea = selectionArea
      ..tempDrawingObject = tempDrawingObject
      ..snapHandlePosition = snapHandlePosition
      ..updateNodes(_getNodeDrawData());
  }

  List<NodeDiffCheckData> _getNodeDrawData() {
    return canvasState.nodes.values
        .map(
          (node) => NodeDiffCheckData(
            id: node.id,
            offset: node.offset,
            state: node.state,
          ),
        )
        .toList();
  }
}

class FlDrawEditorRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ParentData> {
  FlDrawEditorRenderBox({
    required FlDrawEditorStyle style,
    required FragmentShader gridShader,
    required CanvasState canvasState,
    required SelectionState selectionState,
    required Rect selectionArea,
    required List<NodeDiffCheckData> nodesData,
    required this.tempDrawingObject,
    this.snapHandlePosition,
  }) : _style = style,
       _gridShader = gridShader,
       _canvasState = canvasState,
       _selectionState = selectionState,
       _selectionArea = selectionArea {
    _loadGridShader();
    updateNodes(nodesData);
  }

  final SpatialHashGrid _spatialHashGrid = SpatialHashGrid();

  CanvasState _canvasState;

  CanvasState get canvasState => _canvasState;

  set canvasState(CanvasState value) {
    if (_canvasState == value) return;
    _canvasState = value;
    _transformMatrixDirty = true;
    markNeedsLayout();
  }

  SelectionState _selectionState;

  SelectionState get selectionState => _selectionState;

  set selectionState(SelectionState value) {
    if (_selectionState == value) return;
    _selectionState = value;
    markNeedsPaint();
  }

  Offset? snapHandlePosition;

  FlDrawEditorStyle _style;

  FlDrawEditorStyle get style => _style;

  set style(FlDrawEditorStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaint();
  }

  FragmentShader _gridShader;

  FragmentShader get gridShader => _gridShader;

  set gridShader(FragmentShader value) {
    if (_gridShader == value) return;
    _gridShader = value;
    markNeedsPaint();
  }

  Matrix4? _transformMatrix;
  bool _transformMatrixDirty = true;

  Rect _selectionArea;

  Rect get selectionArea => _selectionArea;

  set selectionArea(Rect value) {
    if (_selectionArea == value) return;
    _selectionArea = value;
    markNeedsPaint();
  }

  TempDrawingObject? tempDrawingObject;
  List<NodeDiffCheckData> _nodesDiffCheckData = [];

  void _loadGridShader() {
    final gridStyle = style.gridStyle;
    gridShader.setFloat(0, gridStyle.gridSpacingX);
    gridShader.setFloat(1, gridStyle.gridSpacingY);
    final lineColor = gridStyle.lineColor;
    gridShader.setFloat(4, gridStyle.lineWidth);
    gridShader.setFloat(5, lineColor.red / 255.0);
    gridShader.setFloat(6, lineColor.green / 255.0);
    gridShader.setFloat(7, lineColor.blue / 255.0);
    gridShader.setFloat(8, lineColor.opacity);
    final intersectionColor = gridStyle.intersectionColor;
    gridShader.setFloat(9, gridStyle.intersectionRadius);
    gridShader.setFloat(10, intersectionColor.red / 255.0);
    gridShader.setFloat(11, intersectionColor.green / 255.0);
    gridShader.setFloat(12, intersectionColor.blue / 255.0);
    gridShader.setFloat(13, intersectionColor.opacity);
  }

  void updateNodes(List<NodeDiffCheckData> nodesData) {
    _nodesDiffCheckData = nodesData;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ParentData) {
      child.parentData = _ParentData();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    RenderBox? child = firstChild;
    _spatialHashGrid.clear();

    int i = 0;
    while (child != null && i < _nodesDiffCheckData.length) {
      final nodeData = _nodesDiffCheckData[i];
      final childParentData = child.parentData as _ParentData;

      childParentData.id = nodeData.id;

      child.layout(
        BoxConstraints.loose(constraints.biggest),
        parentUsesSize: true,
      );

      final rect = Rect.fromLTWH(
        nodeData.offset.dx,
        nodeData.offset.dy,
        child.size.width,
        child.size.height,
      );
      childParentData.rect = rect;

      _spatialHashGrid.insert((id: nodeData.id, rect: rect));

      child = childParentData.nextSibling;
      i++;
    }
  }

  Rect _calculateViewport() {
    return Rect.fromLTWH(
      -size.width / 2 / canvasState.viewportZoom -
          canvasState.viewportOffset.dx,
      -size.height / 2 / canvasState.viewportZoom -
          canvasState.viewportOffset.dy,
      size.width / canvasState.viewportZoom,
      size.height / canvasState.viewportZoom,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final (viewport, startX, startY) = _prepareCanvas(context.canvas, size);
    _paintGrid(context.canvas, viewport, startX, startY);

    final visibleNodes = _spatialHashGrid.queryArea(viewport.inflate(300));

    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData as _ParentData;
      final nodeInstance = canvasState.nodes[childParentData.id];
      if (nodeInstance != null && visibleNodes.contains(childParentData.id)) {
        context.paintChild(child, nodeInstance.offset);
      }
      child = childParentData.nextSibling;
    }

    _paintDrawingObjects(context.canvas);
    _paintSnapHandle(context.canvas);
    _paintTempDrawingObject(context.canvas);
    _paintSelectionArea(context.canvas, viewport);

    _transformMatrixDirty = false;
  }

  Matrix4 _getTransformMatrix() {
    if (_transformMatrix != null && !_transformMatrixDirty)
      return _transformMatrix!;
    return _transformMatrix = Matrix4.identity()
      ..translate(size.width / 2, size.height / 2)
      ..scale(canvasState.viewportZoom, canvasState.viewportZoom)
      ..translate(canvasState.viewportOffset.dx, canvasState.viewportOffset.dy);
  }

  (Rect, double, double) _prepareCanvas(Canvas canvas, Size size) {
    canvas.transform(_getTransformMatrix().storage);
    final viewport = _calculateViewport();
    final startX =
        (viewport.left / style.gridStyle.gridSpacingX).floor() *
        style.gridStyle.gridSpacingX;
    final startY =
        (viewport.top / style.gridStyle.gridSpacingY).floor() *
        style.gridStyle.gridSpacingY;
    canvas.clipRect(viewport, clipOp: ui.ClipOp.intersect, doAntiAlias: false);
    return (viewport, startX, startY);
  }

  final _pencilOptions = StrokeOptions(
    size: 8.0,
    thinning: 0.7,
    smoothing: 0.5,
    streamline: 0.5,
    simulatePressure: true,
  );

  get zoom => canvasState.viewportZoom;

  get drawingObjects => canvasState.drawingObjects;

  void _paintGrid(Canvas canvas, Rect viewport, double startX, double startY) {
    if (!style.gridStyle.showGrid) return;
    gridShader.setFloat(2, startX);
    gridShader.setFloat(3, startY);
    gridShader.setFloat(14, viewport.left);
    gridShader.setFloat(15, viewport.top);
    gridShader.setFloat(16, viewport.right);
    gridShader.setFloat(17, viewport.bottom);
    canvas.drawRect(viewport, Paint()..shader = gridShader);
  }

  void _paintSnapHandle(Canvas canvas) {
    if (snapHandlePosition == null) return;
    final paint = Paint()..color = Colors.cyan.withOpacity(0.8);
    canvas.drawCircle(snapHandlePosition!, 6.0 / zoom, paint);
  }

  void _paintDrawingObjects(Canvas canvas) {
    final defaultColor = style.defaultStrokeColor ?? Colors.white;
    final Paint objectPaint = Paint()
      ..color = defaultColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    final Paint selectedObjectPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;
    final Paint selectedBorderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;
    final Paint selectedArrowPaint = Paint()
      ..color = defaultColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;

    final Paint handlePaint = Paint()..color = Colors.blue;
    final Paint handleHitAreaPaint = Paint()..color = Colors.transparent;
    final Paint selectedRectBorderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;

    for (final obj in drawingObjects.values) {
      final isSelected = selectionState.selectedDrawingObjectIds.contains(
        obj.id,
      );
      obj.isSelected = isSelected;

      if (obj is FigureObject) {
        final paint = Paint()
          ..color = obj.isSelected ? Colors.blue : Colors.white.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = obj.isSelected ? 2.0 / zoom : 1.5 / zoom;

        _paintDashedRect(canvas, obj.rect, paint);

        final textStyle = TextStyle(
          color: paint.color,
          fontSize: 14.0 / zoom,
          fontWeight: FontWeight.bold,
        );
        final textSpan = TextSpan(text: obj.label, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          obj.rect.topLeft - Offset(0, textPainter.height),
        );

        if (obj.isSelected) {
          final selectionPadding = 4.0 / zoom;
          final selectionRect = obj.rect.inflate(selectionPadding);
          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final corners = [
            selectionRect.topLeft,
            selectionRect.topRight,
            selectionRect.bottomRight,
            selectionRect.bottomLeft,
          ];
          for (final corner in corners) {
            canvas.drawCircle(corner, handleHitAreaRadius, handleHitAreaPaint);
            canvas.drawCircle(corner, visibleHandleRadius, handlePaint);
          }
        }
        continue;
      }

      if (obj is TextObject) {
        if (obj.isEditing) {
          continue;
        }

        // Draw a compact note icon instead of full text
        final iconRect = obj.rect;
        final iconColor = obj.style.color ?? defaultColor;

        // Filled rounded-rect background
        final bgPaint = Paint()
          ..color = iconColor.withOpacity(0.15)
          ..style = PaintingStyle.fill;
        final borderPaint2 = Paint()
          ..color = iconColor.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / zoom;
        final rRect = RRect.fromRectAndRadius(
          iconRect,
          Radius.circular(4.0 / zoom),
        );
        canvas.drawRRect(rRect, bgPaint);
        canvas.drawRRect(rRect, borderPaint2);

        // Draw a small chat-bubble / note icon inside
        final cx = iconRect.center.dx;
        final cy = iconRect.center.dy;
        final s = iconRect.width * 0.35; // icon half-size
        final notePath = Path()
          ..moveTo(cx - s, cy - s * 0.7)
          ..lineTo(cx + s, cy - s * 0.7)
          ..lineTo(cx + s, cy + s * 0.3)
          ..lineTo(cx + s * 0.2, cy + s * 0.3)
          ..lineTo(cx - s * 0.2, cy + s * 0.8)
          ..lineTo(cx - s * 0.2, cy + s * 0.3)
          ..lineTo(cx - s, cy + s * 0.3)
          ..close();
        final iconPaint = Paint()
          ..color = iconColor.withOpacity(0.8)
          ..style = PaintingStyle.fill;
        canvas.drawPath(notePath, iconPaint);

        // Two small "text lines" inside the bubble
        final linePaint2 = Paint()
          ..color = (iconColor == Colors.white || iconColor == const Color(0xFFFFFFFF))
              ? Colors.black.withOpacity(0.5)
              : Colors.white.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / zoom
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(cx - s * 0.55, cy - s * 0.25),
          Offset(cx + s * 0.55, cy - s * 0.25),
          linePaint2,
        );
        canvas.drawLine(
          Offset(cx - s * 0.55, cy + s * 0.05),
          Offset(cx + s * 0.35, cy + s * 0.05),
          linePaint2,
        );

        if (isSelected) {
          final selectionPadding = 4.0 / zoom;
          final selectionRect = obj.rect.inflate(selectionPadding);
          canvas.drawRect(selectionRect, selectedBorderPaint);
          // No resize handles — note icons are fixed-size
        }
        continue;
      }

      if (obj is PencilStrokeObject) {
        final paint = Paint()
          ..color = obj.isSelected ? Colors.blue : (obj.strokeColor ?? defaultColor);
        _paintPencilStroke(canvas, obj, paint);

        if (obj.isSelected) {
          final selectionPadding = 4.0 / zoom;
          final selectionRect = obj.rect.inflate(selectionPadding);
          canvas.drawRect(selectionRect, selectedRectBorderPaint);

          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final corners = [
            selectionRect.topLeft,
            selectionRect.topRight,
            selectionRect.bottomRight,
            selectionRect.bottomLeft,
          ];
          for (final corner in corners) {
            canvas.drawCircle(corner, handleHitAreaRadius, handleHitAreaPaint);
            canvas.drawCircle(corner, visibleHandleRadius, handlePaint);
          }
        }
        continue;
      } else if (obj is ArrowObject) {
        final Paint paint;
        if (obj.strokeColor != null) {
          paint = Paint()
            ..color = obj.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = (obj.isSelected ? 2.5 : 2.0) / zoom;
        } else {
          paint = obj.isSelected ? selectedArrowPaint : objectPaint;
        }

        var start = (obj).start;
        final startAttachment = obj.startAttachment;
        if (startAttachment != null) {
          final targetNode = canvasState.nodes[startAttachment.objectId];
          final targetObject =
              canvasState.drawingObjects[startAttachment.objectId];
          final Rect? targetRect = targetNode != null
              ? getNodeBoundsInWorld(targetNode)
              : targetObject?.rect;

          if (targetRect != null) {
            final relPos = startAttachment.relativePosition;
            start =
                targetRect.topLeft +
                Offset(
                  targetRect.width * relPos.dx,
                  targetRect.height * relPos.dy,
                );
          }
        }

        var end = (obj).end;
        final endAttachment = obj.endAttachment;
        if (endAttachment != null) {
          final targetNode = canvasState.nodes[endAttachment.objectId];
          final targetObject =
              canvasState.drawingObjects[endAttachment.objectId];
          final Rect? targetRect = targetNode != null
              ? getNodeBoundsInWorld(targetNode)
              : targetObject?.rect;

          if (targetRect != null) {
            final relPos = endAttachment.relativePosition;
            end =
                targetRect.topLeft +
                Offset(
                  targetRect.width * relPos.dx,
                  targetRect.height * relPos.dy,
                );
          }
        }

        final pathType = obj.pathType;
        var controlPoint = obj.midPoint ?? (start + end) / 2;

        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final Offset cornerPoint;
        if (dx.abs() > dy.abs()) {
          cornerPoint = Offset(end.dx, start.dy);
        } else {
          cornerPoint = Offset(start.dx, end.dy);
        }

        if (pathType == LinkPathType.orthogonal) {
          _paintOrthogonalPath(canvas, start, end, paint);
        } else if (pathType == LinkPathType.curved) {
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(
              controlPoint.dx,
              controlPoint.dy,
              end.dx,
              end.dy,
            );
          canvas.drawPath(path, paint);
        } else {
          // LinkPathType.straight — midPoint is a vertex (on the line).
          final path = Path()..moveTo(start.dx, start.dy);
          if (obj.midPoint != null) {
            path.lineTo(obj.midPoint!.dx, obj.midPoint!.dy);
          }
          path.lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
        }

        if (pathType == LinkPathType.orthogonal) {
          final dx = end.dx - start.dx;
          final dy = end.dy - start.dy;
          if (dx.abs() > dy.abs()) {
            controlPoint = Offset(end.dx, start.dy);
          } else {
            controlPoint = Offset(start.dx, end.dy);
          }
        }
        // For straight lines, arrowhead direction comes from the last vertex.
        final arrowFrom = pathType == LinkPathType.straight && obj.midPoint != null
            ? obj.midPoint!
            : controlPoint;
        _paintArrowHead(canvas, arrowFrom, end, paint);

        // Per-arrow distance label. Uses path-aware length so curved
        // and orthogonal arrows report their actual path distance, not
        // the straight chord between endpoints.
        if (obj.showMeasurement) {
          _paintLineDistanceLabel(
            canvas, start, end, obj.midPoint, pathType, zoom);
        }

        if (obj.isSelected) {
          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final onCurveMidPoint =
              (start * 0.25) + (controlPoint * 0.5) + (end * 0.25);

          final Offset midHandle;
          if (pathType == LinkPathType.orthogonal) {
            midHandle = cornerPoint;
          } else if (pathType == LinkPathType.straight) {
            midHandle = obj.midPoint ?? (start + end) / 2;
          } else {
            midHandle = onCurveMidPoint;
          }
          final handles = [start, end, midHandle];
          for (final handlePos in handles) {
            canvas.drawCircle(
              handlePos,
              handleHitAreaRadius,
              handleHitAreaPaint,
            );
            canvas.drawCircle(handlePos, visibleHandleRadius, handlePaint);
          }
        }

        // Draw vertex annotations
        if (obj.vertexAnnotations.isNotEmpty) {
          final Offset annotationMid;
          if (pathType == LinkPathType.orthogonal) {
            annotationMid = cornerPoint;
          } else if (pathType == LinkPathType.straight) {
            annotationMid = obj.midPoint ?? (start + end) / 2;
          } else {
            annotationMid =
                (start * 0.25) + (controlPoint * 0.5) + (end * 0.25);
          }
          _paintVertexAnnotations(
            canvas,
            obj.vertexAnnotations,
            {
              'arrowStart': start,
              'arrowEnd': end,
              'midPoint': annotationMid,
            },
            obj.strokeColor ?? style.defaultStrokeColor ?? Colors.white,
          );
        }
        continue;
      } else if (obj is LineObject) {
        final Paint paint;
        if (obj.strokeColor != null) {
          paint = Paint()
            ..color = obj.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = (obj.isSelected ? 2.0 : 1.5) / zoom;
        } else {
          paint = obj.isSelected ? selectedArrowPaint : objectPaint;
        }

        final controlPoint = obj.midPoint ?? (obj.start + obj.end) / 2;

        final path = Path()..moveTo(obj.start.dx, obj.start.dy);
        if (obj.pathType == LinkPathType.curved) {
          path.quadraticBezierTo(
            controlPoint.dx, controlPoint.dy,
            obj.end.dx, obj.end.dy,
          );
        } else {
          // LinkPathType.straight — midPoint is a vertex (on the line).
          if (obj.midPoint != null) {
            path.lineTo(obj.midPoint!.dx, obj.midPoint!.dy);
          }
          path.lineTo(obj.end.dx, obj.end.dy);
        }
        canvas.drawPath(path, paint);

        // Per-line distance label using path-aware length (curve and
        // polyline cases included). Default true on new lines.
        if (obj.showMeasurement) {
          _paintLineDistanceLabel(
              canvas, obj.start, obj.end, obj.midPoint, obj.pathType, zoom);
        }

        if (obj.isSelected) {
          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;

          final Offset midHandle;
          if (obj.pathType == LinkPathType.straight) {
            midHandle = obj.midPoint ?? (obj.start + obj.end) / 2;
          } else {
            midHandle =
                (obj.start * 0.25) + (controlPoint * 0.5) + (obj.end * 0.25);
          }
          final handles = [obj.start, obj.end, midHandle];
          for (final handlePos in handles) {
            canvas.drawCircle(
              handlePos,
              handleHitAreaRadius,
              handleHitAreaPaint,
            );
            canvas.drawCircle(handlePos, visibleHandleRadius, handlePaint);
          }
        }

        // Draw vertex annotations
        if (obj.vertexAnnotations.isNotEmpty) {
          final Offset annotationMid;
          if (obj.pathType == LinkPathType.straight) {
            annotationMid = obj.midPoint ?? (obj.start + obj.end) / 2;
          } else {
            annotationMid =
                (obj.start * 0.25) + (controlPoint * 0.5) + (obj.end * 0.25);
          }
          _paintVertexAnnotations(
            canvas,
            obj.vertexAnnotations,
            {
              'arrowStart': obj.start,
              'arrowEnd': obj.end,
              'midPoint': annotationMid,
            },
            obj.strokeColor ?? style.defaultStrokeColor ?? Colors.white,
          );
        }
        continue;
      } else if (obj is CircleObject) {
        if (obj.fillColor != null && obj.fillOpacity > 0) {
          canvas.drawOval(
            obj.rect,
            Paint()
              ..color = obj.fillColor!.withValues(alpha: obj.fillOpacity)
              ..style = PaintingStyle.fill,
          );
        }
        if (obj.strokeColor != null) {
          canvas.drawOval(
            obj.rect,
            Paint()
              ..color = obj.strokeColor!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 / zoom,
          );
        } else {
          canvas.drawOval(obj.rect, objectPaint);
        }
      } else if (obj is RectangleObject) {
        if (obj.fillColor != null && obj.fillOpacity > 0) {
          canvas.drawRect(
            obj.rect,
            Paint()
              ..color = obj.fillColor!.withValues(alpha: obj.fillOpacity)
              ..style = PaintingStyle.fill,
          );
        }
        if (obj.strokeColor != null) {
          canvas.drawRect(
            obj.rect,
            Paint()
              ..color = obj.strokeColor!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 / zoom,
          );
        } else {
          canvas.drawRect(obj.rect, objectPaint);
        }
      } else if (obj is SvgObject) {
        final center = obj.rect.center;

        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(obj.rotation);
        canvas.translate(-center.dx, -center.dy);

        canvas.save();
        canvas.translate(obj.rect.left, obj.rect.top);

        if (obj.pictureInfo != null) {
          final Size svgSize = obj.pictureInfo!.size;
          final double scaleX =
              obj.rect.width /
              (svgSize.width.isFinite && svgSize.width > 0 ? svgSize.width : 1);
          final double scaleY =
              obj.rect.height /
              (svgSize.height.isFinite && svgSize.height > 0
                  ? svgSize.height
                  : 1);

          canvas.scale(scaleX, scaleY);

          final svgBounds = Rect.fromLTWH(0, 0, svgSize.width, svgSize.height);
          final bodyImg = obj.bodyImage;
          final tint = obj.tintColor;

          if (!obj.wireframe && bodyImg != null) {
            // FILLED LINE-ART (cars/trucks): a solid body (chosen colour, or
            // white by default) with the line art over it — WHITE detail on a
            // coloured body, dark detail on a white body.
            final bodyColor = tint ?? const Color(0xFFFFFFFF);
            canvas.drawImageRect(
              bodyImg,
              Rect.fromLTWH(
                  0, 0, bodyImg.width.toDouble(), bodyImg.height.toDouble()),
              svgBounds,
              Paint()
                ..colorFilter = ColorFilter.mode(bodyColor, BlendMode.srcIn)
                ..filterQuality = FilterQuality.medium
                ..isAntiAlias = true,
            );
            // Dark detail on a light body (white/yellow), white detail on a
            // dark/saturated body (red/blue/…).
            final bArgb = bodyColor.toARGB32();
            final bLum = 0.299 * ((bArgb >> 16) & 0xFF) +
                0.587 * ((bArgb >> 8) & 0xFF) +
                0.114 * (bArgb & 0xFF);
            final lineColor = bLum > 150
                ? const Color(0xFF222222)
                : const Color(0xFFFFFFFF);
            canvas.saveLayer(
              svgBounds,
              Paint()
                ..colorFilter = ColorFilter.mode(lineColor, BlendMode.srcIn),
            );
            canvas.drawPicture(obj.pictureInfo!.picture);
            canvas.restore();
          } else if (!obj.wireframe && tint != null) {
            // FILLED FIGURE (pedestrian etc.): already a solid-fill SVG with no
            // enclosed area to synthesise, so recolour the whole figure — map
            // luminance (white -> chosen colour, dark -> a darker shade of it)
            // so it reads as a solid coloured body, matching the vehicles.
            final argb = tint.toARGB32();
            final r = ((argb >> 16) & 0xFF).toDouble();
            final g = ((argb >> 8) & 0xFF).toDouble();
            final b = (argb & 0xFF).toDouble();
            const k = 0.35; // dark pixels -> k * colour
            double slope(double c) => c * (1.0 - k) / 255.0;
            double offset(double c) => k * c;
            final solidPaint = Paint()
              ..colorFilter = ColorFilter.matrix(<double>[
                slope(r), 0, 0, 0, offset(r), //
                0, slope(g), 0, 0, offset(g), //
                0, 0, slope(b), 0, offset(b), //
                0, 0, 0, 1, 0, //
              ]);
            canvas.saveLayer(svgBounds, solidPaint);
            canvas.drawPicture(obj.pictureInfo!.picture);
            canvas.restore();
          } else {
            // WIREFRAME (per-object), or an untinted filled figure: render the
            // ORIGINAL default line art — always the default (black) colour,
            // ignoring any tint the asset carries, so wireframe reverts to the
            // asset's original look.
            final rampTint = style.svgTintColor;
            if (rampTint != null) {
              final argb = rampTint.toARGB32();
              final r = ((argb >> 16) & 0xFF).toDouble();
              final g = ((argb >> 8) & 0xFF).toDouble();
              final b = (argb & 0xFF).toDouble();
              const dark = 77.0; // #4d4d4d reference for the dark fills
              double slope(double c) => (255.0 - c) / (255.0 - dark);
              double offset(double c) => c - slope(c) * dark;
              final tintPaint = Paint()
                ..colorFilter = ColorFilter.matrix(<double>[
                  slope(r), 0, 0, 0, offset(r), //
                  0, slope(g), 0, 0, offset(g), //
                  0, 0, slope(b), 0, offset(b), //
                  0, 0, 0, 1, 0, //
                ]);
              canvas.saveLayer(svgBounds, tintPaint);
              canvas.drawPicture(obj.pictureInfo!.picture);
              canvas.restore();
            } else {
              canvas.drawPicture(obj.pictureInfo!.picture);
            }
          }
        } else {
          // Placeholder rect for SVG not yet loaded
          final placeholderPaint = Paint()
            ..color = const Color(0x30808080)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromLTWH(0, 0, obj.rect.width, obj.rect.height),
            placeholderPaint,
          );
        }

        canvas.restore(); // inner save (translate to rect origin)

        // Draw damage/impact marks (X) at relative positions on the SVG
        if (obj.damageMarks.isNotEmpty) {
          final dmPaint = Paint()
            ..color = Colors.red
            ..strokeWidth = 2.0 / zoom
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          final markSize = 6.0 / zoom;
          for (final mark in obj.damageMarks) {
            final pos = Offset(
              obj.rect.left + mark.dx * obj.rect.width,
              obj.rect.top + mark.dy * obj.rect.height,
            );
            canvas.drawLine(
              pos - Offset(markSize, markSize),
              pos + Offset(markSize, markSize),
              dmPaint,
            );
            canvas.drawLine(
              pos - Offset(-markSize, markSize),
              pos + Offset(-markSize, markSize),
              dmPaint,
            );
          }
        }

        if (obj.isSelected) {
          final selectionPadding = 4.0 / zoom;
          final selectionRect = obj.rect.inflate(selectionPadding);
          canvas.drawRect(selectionRect, selectedBorderPaint);

          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;

          // Rotation handle only — no corner resize handles for SVG objects.
          final rotateHandleOffset = 30.0 / zoom;
          final topCenter = Offset(selectionRect.center.dx, selectionRect.top);
          final rotateHandlePos = topCenter - Offset(0, rotateHandleOffset);

          final linePaint = Paint()
            ..color = const Color(0xFF3B82F6)
            ..strokeWidth = 1.0 / zoom;
          canvas.drawLine(topCenter, rotateHandlePos, linePaint);
          canvas.drawCircle(rotateHandlePos, handleHitAreaRadius, handleHitAreaPaint);
          canvas.drawCircle(rotateHandlePos, visibleHandleRadius, handlePaint);
        }

        canvas.restore(); // outer save (rotation transform)

        // Paint unit number badge AFTER rotation restore so it stays upright.
        // Anchor at the rotated TOP-LEFT corner (the type label sits below).
        if (obj.label.isNotEmpty) {
          final rectCenter = obj.rect.center;
          final cosR = cos(obj.rotation);
          final sinR = sin(obj.rotation);
          // Top-left corner in local space, rotated to world space.
          final tlLocal = Offset(
            obj.rect.left - rectCenter.dx,
            obj.rect.top - rectCenter.dy,
          );
          final tlWorld = Offset(
            rectCenter.dx + tlLocal.dx * cosR - tlLocal.dy * sinR,
            rectCenter.dy + tlLocal.dx * sinR + tlLocal.dy * cosR,
          );

          final shortSide = obj.rect.shortestSide;
          // ~3/4 of the previous size (0.32 -> 0.24, clamps scaled to match).
          final badgeDiameter =
              (shortSide * 0.24).clamp(12.0 / zoom, 30.0 / zoom);
          final badgeRadius = badgeDiameter / 2;
          // Push the badge OUTWARD from the top-left corner (along the
          // centre→corner direction) so it sits just off the asset, not on it.
          final outward = tlWorld - rectCenter;
          final outLen = outward.distance;
          final outDir =
              outLen > 0 ? outward / outLen : const Offset(-0.707, -0.707);
          final badgeCenter = tlWorld + outDir * (badgeRadius * 0.8);

          final badgeFill = Paint()..color = const Color(0xFFFFFFFF);
          final badgeBorder = Paint()
            ..color = const Color(0xFF777777)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8 / zoom;
          canvas.drawCircle(badgeCenter, badgeRadius, badgeFill);
          canvas.drawCircle(badgeCenter, badgeRadius, badgeBorder);

          final fontSize = badgeDiameter * 0.55;
          final labelSpan = TextSpan(
            text: obj.label,
            style: TextStyle(
              color: const Color(0xFF444444),
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          );
          final labelPainter = TextPainter(
            text: labelSpan,
            textDirection: TextDirection.ltr,
          )..layout();
          labelPainter.paint(
            canvas,
            Offset(
              badgeCenter.dx - labelPainter.width / 2,
              badgeCenter.dy - labelPainter.height / 2,
            ),
          );

          // Type-name label below the asset (bottom-centre), when toggled on.
          // Upright, dark text on a light backdrop so it reads on the white
          // blueprint (and on darker areas).
          if (obj.showLabel && obj.annotation.isNotEmpty) {
            final bcLocal = Offset(0, obj.rect.bottom - rectCenter.dy);
            final bcWorld = Offset(
              rectCenter.dx + bcLocal.dx * cosR - bcLocal.dy * sinR,
              rectCenter.dy + bcLocal.dx * sinR + bcLocal.dy * cosR,
            );
            // Architectural style: small, UPPERCASE, letter-spaced.
            final annotationPainter = TextPainter(
              text: TextSpan(
                text: obj.annotation.toUpperCase(),
                style: TextStyle(
                  color: const Color(0xCC000000),
                  fontSize: 8.5 / zoom,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.7 / zoom,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            // Sit clearly below the asset + its number badge.
            final textOffset = Offset(
              bcWorld.dx - annotationPainter.width / 2,
              bcWorld.dy + badgeRadius + 6.0 / zoom,
            );
            final bgRect = Rect.fromLTWH(
              textOffset.dx - 3.0 / zoom,
              textOffset.dy - 1.0 / zoom,
              annotationPainter.width + 6.0 / zoom,
              annotationPainter.height + 2.0 / zoom,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(bgRect, Radius.circular(2.0 / zoom)),
              Paint()..color = const Color(0xB3FFFFFF),
            );
            annotationPainter.paint(canvas, textOffset);
          }
        }
        continue;
      } else if (obj is ReferencePointObject) {
        _paintReferencePoint(canvas, obj, objectPaint, selectedBorderPaint, handlePaint, handleHitAreaPaint);
        continue;
      }

      if (obj.isSelected) {
        final selectionPadding = 4.0 / zoom;
        final selectionRect = obj.rect.inflate(selectionPadding);
        canvas.drawRect(selectionRect, selectedBorderPaint);

        final double visibleHandleRadius = 4.0 / zoom;
        final double handleHitAreaRadius = 10.0 / zoom;

        final corners = [
          selectionRect.topLeft,
          selectionRect.topRight,
          selectionRect.bottomRight,
          selectionRect.bottomLeft,
        ];

        for (final corner in corners) {
          canvas.drawCircle(corner, handleHitAreaRadius, handleHitAreaPaint);
          canvas.drawCircle(corner, visibleHandleRadius, handlePaint);
        }
      }
    }
  }

  void _paintDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const double dashWidth = 5.0;
    const double dashSpace = 3.0;

    double startX = rect.left;
    while (startX < rect.right) {
      canvas.drawLine(
        Offset(startX, rect.top),
        Offset(min(startX + dashWidth, rect.right), rect.top),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
    startX = rect.left;
    while (startX < rect.right) {
      canvas.drawLine(
        Offset(startX, rect.bottom),
        Offset(min(startX + dashWidth, rect.right), rect.bottom),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
    double startY = rect.top;
    while (startY < rect.bottom) {
      canvas.drawLine(
        Offset(rect.left, startY),
        Offset(rect.left, min(startY + dashWidth, rect.bottom)),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
    startY = rect.top;
    while (startY < rect.bottom) {
      canvas.drawLine(
        Offset(rect.right, startY),
        Offset(rect.right, min(startY + dashWidth, rect.bottom)),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
  }

  void _paintReferencePoint(
    Canvas canvas,
    ReferencePointObject obj,
    Paint objectPaint,
    Paint selectedBorderPaint,
    Paint handlePaint,
    Paint handleHitAreaPaint,
  ) {
    final pos = obj.position;
    final r = 8.0 / zoom;

    // Draw dashed lines to every SVG object with distance labels
    for (final other in drawingObjects.values) {
      if (other is SvgObject) {
        final target = other.rect.center;
        _paintDashedLineBetween(canvas, pos, target, zoom);
        _paintDistanceLabel(canvas, pos, target, zoom);
      }
    }

    // White outer ring
    final outerPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, r, outerPaint);

    // Light blue fill
    final fillPaint = Paint()
      ..color = const Color(0xFF64B5F6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, r * 0.7, fillPaint);

    // Subtle border
    final borderPaint = Paint()
      ..color = const Color(0xFF1E88E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    canvas.drawCircle(pos, r, borderPaint);

    // Inner dot
    final dotPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, r * 0.2, dotPaint);

    // "RP" label to the lower-right — matches stroke color for visibility
    final labelColor = style.defaultStrokeColor ?? const Color(0xFFFFFFFF);
    final textStyle = ui.TextStyle(
      color: labelColor,
      fontSize: 9.0 / zoom,
      fontWeight: FontWeight.w600,
    );
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
    ))
      ..pushStyle(textStyle)
      ..addText('RP');
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    canvas.drawParagraph(paragraph, pos + Offset(r * 1.1, r * 0.3));

    // Selection handles
    if (obj.isSelected) {
      final selectionPadding = 4.0 / zoom;
      final selectionRect = obj.rect.inflate(selectionPadding + r * 0.5);
      canvas.drawRect(selectionRect, selectedBorderPaint);
    }
  }

  void _paintDashedLineBetween(Canvas canvas, Offset from, Offset to, double zoom) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance < 1e-6) return;

    final direction = delta / distance;
    // Larger dash + thicker stroke + darker blue than before
    // (Blue-200 0xFF90CAF9 was reported as too faint to read against
    // satellite imagery and the AI diagram render). Blue-700 with 2x
    // stroke width keeps the dashed reference-point connections
    // legible across both backgrounds.
    final dashWidth = 7.0 / zoom;
    final dashSpace = 4.0 / zoom;
    final paint = Paint()
      ..color = const Color(0xFF1976D2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;

    double drawn = 0;
    while (drawn < distance) {
      final segStart = from + direction * drawn;
      final segEnd = from + direction * min(drawn + dashWidth, distance);
      canvas.drawLine(segStart, segEnd, paint);
      drawn += dashWidth + dashSpace;
    }
  }

  /// Paint a measurement label for a straight chord between [from] and
  /// [to]. Used by reference-point connections; lines and arrows go
  /// through [_paintLineDistanceLabel] which knows about midPoint and
  /// curve geometry.
  void _paintDistanceLabel(Canvas canvas, Offset from, Offset to, double zoom) {
    final delta = to - from;
    final pixelDistance = delta.distance;
    if (pixelDistance < 1e-6) return;
    final midpoint = (from + to) / 2;
    final perpendicular = Offset(-delta.dy, delta.dx) / pixelDistance;
    _paintLengthLabel(
      canvas: canvas,
      lengthInUnits: pixelDistance,
      anchor: midpoint,
      perpendicular: perpendicular,
      zoom: zoom,
    );
  }

  /// Paint a measurement label for a [LineObject] / [ArrowObject]. Uses
  /// the actual path length:
  ///   - straight w/o vertex   → chord distance
  ///   - straight w/ midPoint  → two-segment polyline length
  ///   - curved (Bezier)       → numerical arc length (24 sub-segments)
  ///   - orthogonal (L-shape)  → sum of the two axis-aligned segments
  ///
  /// Anchor point for the label is the geometric midpoint of the path,
  /// offset perpendicular so the text doesn't sit on the line.
  void _paintLineDistanceLabel(
    Canvas canvas,
    Offset start,
    Offset end,
    Offset? midPoint,
    LinkPathType pathType,
    double zoom,
  ) {
    if ((end - start).distance < 1e-6) return;

    final length = _pathLength(start, end, midPoint, pathType);
    final anchor = _pathMidpoint(start, end, midPoint, pathType);
    final tangent = _pathTangentAt(start, end, midPoint, pathType, 0.5);
    final perp = tangent.distance < 1e-6
        ? const Offset(0, -1)
        : Offset(-tangent.dy, tangent.dx) / tangent.distance;

    _paintLengthLabel(
      canvas: canvas,
      lengthInUnits: length,
      anchor: anchor,
      perpendicular: perp,
      zoom: zoom,
    );
  }

  /// Numerical arc length of a quadratic Bezier — subdivides into
  /// [n] segments and sums chord lengths. n=24 keeps relative error
  /// well under 0.5% for typical curvatures while staying cheap to
  /// recompute every paint pass.
  double _quadraticBezierLength(Offset p0, Offset p1, Offset p2,
      {int n = 24}) {
    double length = 0;
    Offset prev = p0;
    for (int i = 1; i <= n; i++) {
      final t = i / n;
      final s = 1 - t;
      final point = Offset(
        s * s * p0.dx + 2 * s * t * p1.dx + t * t * p2.dx,
        s * s * p0.dy + 2 * s * t * p1.dy + t * t * p2.dy,
      );
      length += (point - prev).distance;
      prev = point;
    }
    return length;
  }

  double _pathLength(
      Offset start, Offset end, Offset? midPoint, LinkPathType pathType) {
    if (pathType == LinkPathType.curved) {
      final control = midPoint ?? (start + end) / 2;
      return _quadraticBezierLength(start, control, end);
    }
    if (pathType == LinkPathType.orthogonal) {
      return (end.dx - start.dx).abs() + (end.dy - start.dy).abs();
    }
    // straight
    if (midPoint != null) {
      return (midPoint - start).distance + (end - midPoint).distance;
    }
    return (end - start).distance;
  }

  Offset _pathMidpoint(
      Offset start, Offset end, Offset? midPoint, LinkPathType pathType) {
    if (pathType == LinkPathType.curved) {
      final control = midPoint ?? (start + end) / 2;
      // Bezier point at t=0.5
      return start * 0.25 + control * 0.5 + end * 0.25;
    }
    if (pathType == LinkPathType.orthogonal) {
      // Corner is closer to the longer axis — anchor between mid-corner.
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final corner = dx.abs() > dy.abs()
          ? Offset(end.dx, start.dy)
          : Offset(start.dx, end.dy);
      return corner;
    }
    return midPoint ?? (start + end) / 2;
  }

  Offset _pathTangentAt(Offset start, Offset end, Offset? midPoint,
      LinkPathType pathType, double t) {
    if (pathType == LinkPathType.curved) {
      final p1 = midPoint ?? (start + end) / 2;
      // d/dt of quadratic Bezier = 2(1-t)(p1-p0) + 2t(p2-p1)
      return (p1 - start) * (2 * (1 - t)) + (end - p1) * (2 * t);
    }
    if (pathType == LinkPathType.orthogonal) {
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      // Tangent at the corner is along the second leg.
      return dx.abs() > dy.abs()
          ? Offset(0, end.dy - start.dy)
          : Offset(end.dx - start.dx, 0);
    }
    if (midPoint != null && t >= 0.5) {
      return end - midPoint;
    }
    if (midPoint != null) {
      return midPoint - start;
    }
    return end - start;
  }

  /// Shared label painter — no backdrop, theme-aware fill (uses
  /// [style.labelColor] which the host can lerp from white→black as a
  /// background-blend slider moves). A subtle drop-shadow keeps the
  /// label readable against high-contrast backgrounds when fill is
  /// near-neutral; without the shadow the older opaque pill was a hard
  /// dark stamp on the canvas.
  void _paintLengthLabel({
    required Canvas canvas,
    required double lengthInUnits,
    required Offset anchor,
    required Offset perpendicular,
    required double zoom,
  }) {
    final mPerUnit = style.metersPerWorldUnit ?? 0.15; // fallback ≈ 0.5 ft
    final feet = lengthInUnits * mPerUnit * 3.28084;
    // Distances rendered as whole feet — officers don't need decimal
    // precision on rough sketch measurements and the cleaner labels
    // read better on small mobile canvases. Applies to reference-
    // point dashed lines, straight LineObjects, and curved Bezier
    // ArrowObjects through the same _paintLengthLabel call.
    final label = '${feet.round()} ft';

    final fontSize = 9.0 / zoom;
    final fillColor =
        style.labelColor ?? style.defaultStrokeColor ?? const Color(0xFFFFFFFF);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          color: fillColor,
          fontWeight: FontWeight.w600,
          shadows: const [
            // Soft drop-shadow so the label survives intermediate fill
            // colors (gray) when the host's slider is mid-blend.
            Shadow(color: Color(0x66000000), blurRadius: 1.5),
            Shadow(color: Color(0x66FFFFFF), blurRadius: 1.5),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelOffset = anchor +
        perpendicular * (10.0 / zoom) +
        Offset(-textPainter.width / 2, -textPainter.height / 2);
    textPainter.paint(canvas, labelOffset);
  }

  void _paintPencilStroke(
    Canvas canvas,
    PencilStrokeObject object,
    Paint paint,
  ) {
    final options = _pencilOptions.copyWith(size: 8.0 / sqrt(zoom));
    final outlinePoints = getStroke(object.points, options: options);

    if (outlinePoints.isEmpty) {
      object.cachedPath = null;
      return;
    } else if (outlinePoints.length < 2) {
      final path = Path()
        ..addOval(
          Rect.fromCircle(
            center: outlinePoints.first,
            radius: options.size / 2,
          ),
        );
      object.cachedPath = path;
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
    } else {
      final path = Path();
      path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);
      for (int i = 0; i < outlinePoints.length - 1; ++i) {
        final p0 = outlinePoints[i];
        final p1 = outlinePoints[i + 1];
        path.quadraticBezierTo(
          p0.dx,
          p0.dy,
          (p0.dx + p1.dx) / 2,
          (p0.dy + p1.dy) / 2,
        );
      }
      object.cachedPath = path;
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
    }
  }

  void _paintVertexAnnotations(
    Canvas canvas,
    Map<String, VertexAnnotation> annotations,
    Map<String, Offset> handlePositions,
    Color textColor,
  ) {
    final fontSize = 10.0 / zoom;
    // Vertex annotations use the host's labelColor when set so they
    // adjust with the diagram/satellite blend slider — falls back to
    // the textColor passed by the caller (typically the line's stroke
    // color) for back-compat.
    final fillColor = style.labelColor ?? textColor;
    for (final entry in annotations.entries) {
      final pos = handlePositions[entry.key];
      if (pos == null) continue;
      final annotation = entry.value;
      if (annotation.isEmpty) continue;

      // Build display text: distance on first line, label on second
      final parts = <String>[];
      if (annotation.distance != null && annotation.distance!.isNotEmpty) {
        parts.add(annotation.distance!);
      }
      if (annotation.label != null && annotation.label!.isNotEmpty) {
        parts.add(annotation.label!);
      }
      if (parts.isEmpty) continue;

      final displayText = parts.join('\n');
      final textPainter = TextPainter(
        text: TextSpan(
          text: displayText,
          style: TextStyle(
            fontSize: fontSize,
            color: fillColor,
            fontWeight: FontWeight.w500,
            shadows: const [
              // Soft drop-shadow keeps annotations legible at
              // intermediate fill colors when the host's blend slider
              // sits mid-range. Subtle — not the prior hard backplate.
              Shadow(color: Color(0x66000000), blurRadius: 1.5),
              Shadow(color: Color(0x66FFFFFF), blurRadius: 1.5),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Position below the vertex, centered horizontally
      final offset = Offset(
        pos.dx - textPainter.width / 2,
        pos.dy + (8.0 / zoom),
      );

      textPainter.paint(canvas, offset);
    }
  }

  void _paintArrowHead(
    Canvas canvas,
    Offset controlPoint,
    Offset end,
    Paint paint,
  ) {
    final double arrowSize = 12.0 / zoom;
    const double arrowAngle = 25 * (pi / 180);

    // For orthogonal lines, the "control point" is the corner, not the start.
    // We need to determine the final segment's direction.
    Offset effectiveControlPoint = controlPoint;
    if (tempDrawingObject?.pathType == LinkPathType.orthogonal) {
      final start = tempDrawingObject!.start;
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      if (dx.abs() > dy.abs()) {
        // Horizontal-then-Vertical, so the final segment is vertical.
        effectiveControlPoint = Offset(end.dx, start.dy);
      } else {
        // Vertical-then-Horizontal, so the final segment is horizontal.
        effectiveControlPoint = Offset(start.dx, end.dy);
      }
    }

    final lineVector = end - effectiveControlPoint;
    if (lineVector.distanceSquared == 0)
      return; // Avoid errors if start and end are the same
    final angle = lineVector.direction;

    // A clean, solid (filled) triangular head reads far better than an open
    // stroked "V", which looked hand-drawn.
    final p2 = end - Offset.fromDirection(angle - arrowAngle, arrowSize);
    final p3 = end - Offset.fromDirection(angle + arrowAngle, arrowSize);
    // Pull the base back very slightly so the head sits flush on the line.
    final baseMid = end - Offset.fromDirection(angle, arrowSize * 0.72);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(baseMid.dx, baseMid.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  void _paintOrthogonalPath(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;

    final Path path = Path();
    path.moveTo(start.dx, start.dy);

    // OrthogonalPath logic:
    // Determine the corner point based on the dominant direction of the drag.
    // If the drag is mostly horizontal, the first segment is horizontal.
    // If the drag is mostly vertical, the first segment is vertical.
    if (dx.abs() > dy.abs()) {
      // Horizontal-then-Vertical
      path.lineTo(end.dx, start.dy); // Horizontal segment
      path.lineTo(end.dx, end.dy); // Vertical segment
    } else {
      // Vertical-then-Horizontal
      path.lineTo(start.dx, end.dy); // Vertical segment
      path.lineTo(end.dx, end.dy); // Horizontal segment
    }

    canvas.drawPath(path, paint);
  }

  void _paintTempDrawingObject(Canvas canvas) {
    if (tempDrawingObject == null) return;
    final Paint tempPaint = Paint()
      ..color = Colors.grey.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    final start = tempDrawingObject!.start;
    final end = tempDrawingObject!.end;
    final rect = Rect.fromPoints(start, end);

    switch (tempDrawingObject!.tool) {
      case EditorTool.circle:
        canvas.drawOval(rect.normalize, tempPaint);
        break;
      case EditorTool.square:
        canvas.drawRect(rect.normalize, tempPaint);
        break;
      case EditorTool.arrowTopRight:
        if (tempDrawingObject!.pathType == LinkPathType.orthogonal) {
          _paintOrthogonalPath(canvas, start, end, tempPaint);
        } else {
          canvas.drawLine(start, end, tempPaint);
        }
        _paintArrowHead(canvas, start, end, tempPaint);
        break;
        break;
      case EditorTool.line:
        canvas.drawLine(start, end, tempPaint);
        break;
      case EditorTool.pencil:
        _paintPencilStroke(
          canvas,
          PencilStrokeObject(id: "temp", points: tempDrawingObject!.points),
          tempPaint,
        );
        break;
      case EditorTool.figure:
        _paintDashedRect(canvas, rect.normalize, tempPaint);
        break;
      default:
        break;
    }
  }

  void _paintSelectionArea(Canvas canvas, Rect viewport) {
    if (selectionArea.isEmpty) return;
    final selStyle = style.selectionAreaStyle;
    final Paint selectionPaint = Paint()
      ..color = selStyle.color
      ..style = PaintingStyle.fill;
    canvas.drawRect(selectionArea, selectionPaint);
    final Paint borderPaint = Paint()
      ..color = selStyle.borderColor
      ..strokeWidth = selStyle.borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(selectionArea, borderPaint);
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }

    if (size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }

    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final childParentData = child.parentData as _ParentData;
      final nodeInstance = canvasState.nodes[childParentData.id];

      if (nodeInstance == null) {
        child = childParentData.previousSibling;
        continue;
      }

      final transform = _getTransformMatrix();
      final invertedTransform = Matrix4.tryInvert(transform);
      if (invertedTransform == null) {
        child = childParentData.previousSibling;
        continue;
      }

      final worldPosition = MatrixUtils.transformPoint(
        invertedTransform,
        position,
      );

      final childLocalPosition = worldPosition - nodeInstance.offset;

      if (child.hitTest(result, position: childLocalPosition)) {
        return true;
      }

      child = childParentData.previousSibling;
    }
    return false;
  }
}
