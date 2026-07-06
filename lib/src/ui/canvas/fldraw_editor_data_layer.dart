import 'dart:async';
import 'package:fldraw/src/core/utils/platform_info/platform_info.dart'
    show PlatformInfoImpl;
import 'dart:math';

import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/core/node_editor/clipboard.dart';
import 'package:fldraw/src/core/utils/json_extensions.dart';
import 'package:fldraw/src/core/utils/renderbox.dart';
import 'package:fldraw/src/models/drawing_entities.dart';
import 'package:fldraw/src/ui/canvas/fldraw_editor_render_object.dart';
import 'package:fldraw/src/ui/shared/improved_listener.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:keymap/keymap.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:uuid/uuid.dart';

import '../../constants.dart';

typedef SnapPoint = ({
  String objectId,
  Offset worldPosition,
  Offset relativePosition,
});

class FlOverlayData {
  final Widget child;
  final double? top;
  final double? left;
  final double? bottom;
  final double? right;

  FlOverlayData({
    required this.child,
    this.top,
    this.left,
    this.bottom,
    this.right,
  });
}

class FlDrawEditorDataLayer extends StatefulWidget {
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final String fragmentShader;
  final FlDrawEditorStyle style;

  const FlDrawEditorDataLayer({
    super.key,
    this.headerBuilder,
    this.nodeBuilder,
    required this.fragmentShader,
    this.style = const FlDrawEditorStyle(),
  });

  @override
  State<FlDrawEditorDataLayer> createState() => _FlDrawEditorDataLayerState();
}

class _FlDrawEditorDataLayerState extends State<FlDrawEditorDataLayer>
    with TickerProviderStateMixin {
  late CanvasBloc _canvasBloc;
  late SelectionBloc _selectionBloc;
  late ToolBloc _toolBloc;

  bool _isPanning = false;
  bool _isAreaSelecting = false;
  bool _isDraggingSelection = false;
  bool _isDrawing = false;

  ({String objectId, Handle handle}) _isResizing = (
    objectId: '',
    handle: Handle.none,
  );
  ({String objectId, Handle handle}) _hoveredHandle = (
    objectId: '',
    handle: Handle.none,
  );
  // Track last completed resize for double-tap vertex annotation detection.
  ({String objectId, Handle handle}) _lastCompletedResize = (
    objectId: '',
    handle: Handle.none,
  );

  Offset _lastPositionDelta = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  Offset _kineticEnergy = Offset.zero;
  Timer? _kineticTimer;
  Offset _selectionStart = Offset.zero;
  Rect _selectionArea = Rect.zero;
  Offset _drawingStart = Offset.zero;
  List<PointVector> _currentPencilPoints = [];
  TempDrawingObject? _tempDrawingObject;
  Rect? _originalResizeRect;
  SnapPoint? _hoveredSnapPoint;
  SnapPoint? _startSnapPoint;

  // Mobile multi-touch gesture tracking
  bool _mobileIsPanZoom = false;
  double _mobileInitialZoom = 1.0;
  bool _mobileMoved = false;
  Offset _mobileStartFocal = Offset.zero;
  DateTime _mobileGestureStartTime = DateTime.now();
  DateTime? _mobileLastTapTime;
  late final bool _isMobile;

  late final ScaleGestureRecognizer _trackpadGestureRecognizer;

  Offset get offset => _canvasBloc.state.viewportOffset;

  double get zoom => _canvasBloc.state.viewportZoom;

  @override
  void initState() {
    super.initState();
    _canvasBloc = context.read<CanvasBloc>();
    _selectionBloc = context.read<SelectionBloc>();
    _toolBloc = context.read<ToolBloc>();

    final platform = PlatformInfoImpl();
    _isMobile = platform.isAndroid || platform.isIOS;

    _trackpadGestureRecognizer = ScaleGestureRecognizer()
      ..onStart = ((details) => _onPanStart())
      ..onUpdate = _onScaleUpdate
      ..onEnd = ((details) => _onPanEnd());
  }

  @override
  void dispose() {
    _trackpadGestureRecognizer.dispose();
    _kineticTimer?.cancel();
    super.dispose();
  }

  void _updateSnapHandle(Offset worldPos) {
    final tool = _toolBloc.state.activeTool;
    final canvasState = _canvasBloc.state;

    bool shouldCheckForSnapping =
        ((tool == EditorTool.arrowTopRight || tool == EditorTool.line) &&
            !_isDrawing) ||
        (_isDrawing &&
            (_tempDrawingObject?.tool == EditorTool.arrowTopRight ||
                _tempDrawingObject?.tool == EditorTool.line)) ||
        (_isResizing.handle == Handle.arrowStart ||
            _isResizing.handle == Handle.arrowEnd);
    if (!shouldCheckForSnapping) {
      if (_hoveredSnapPoint != null) {
        setState(() => _hoveredSnapPoint = null);
      }
      return;
    }

    SnapPoint? newSnapPoint;
    double minDistance = double.infinity;
    final tolerance = 10.0 / canvasState.viewportZoom;

    for (final obj in canvasState.drawingObjects.values) {
      if (obj.id == _isResizing.objectId) continue;
      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is FigureObject ||
          obj is SvgObject) {
        final distance = distanceToRectBorder(worldPos, obj.rect);
        if (distance < tolerance && distance < minDistance) {
          minDistance = distance;
          final closestPoint = getClosestPointOnRectBorder(worldPos, obj.rect);
          newSnapPoint = (
            objectId: obj.id,
            worldPosition: closestPoint,
            relativePosition: Offset(
              (closestPoint.dx - obj.rect.left) /
                  obj.rect.width.clamp(0.001, double.infinity),
              (closestPoint.dy - obj.rect.top) /
                  obj.rect.height.clamp(0.001, double.infinity),
            ),
          );
        }
      }
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds == null) continue;
      final distance = distanceToRectBorder(worldPos, nodeBounds);
      if (distance < tolerance && distance < minDistance) {
        minDistance = distance;
        final closestPoint = getClosestPointOnRectBorder(worldPos, nodeBounds);
        newSnapPoint = (
          objectId: node.id,
          worldPosition: closestPoint,
          relativePosition: Offset(
            (closestPoint.dx - nodeBounds.left) /
                nodeBounds.width.clamp(0.001, double.infinity),
            (closestPoint.dy - nodeBounds.top) /
                nodeBounds.height.clamp(0.001, double.infinity),
          ),
        );
      }
    }

    if (newSnapPoint != _hoveredSnapPoint) {
      _hoveredSnapPoint = newSnapPoint;
      if (shouldCheckForSnapping &&
          _startSnapPoint != null &&
          newSnapPoint != null) {
        return;
      } else if (shouldCheckForSnapping && _hoveredSnapPoint != null) {
        _startSnapPoint = _hoveredSnapPoint;
      }
      setState(() {});
    }
  }

  double distanceToRectBorder(Offset point, Rect rect) {
    double dx = max(rect.left - point.dx, max(0, point.dx - rect.right));
    double dy = max(rect.top - point.dy, max(0, point.dy - rect.bottom));
    return sqrt(dx * dx + dy * dy);
  }

  Offset getClosestPointOnRectBorder(Offset point, Rect rect) {
    return Offset(
      point.dx.clamp(rect.left, rect.right),
      point.dy.clamp(rect.top, rect.bottom),
    );
  }

  void _onPanStart() {
    setState(() => _isPanning = true);
    _startKineticTimer();
  }

  void _onPanUpdate(Offset delta) {
    setState(() => _lastPositionDelta = delta);
    _resetKineticTimer();
    final panDelta = delta / _canvasBloc.state.viewportZoom;
    _canvasBloc.add(CanvasPanned(panDelta));
  }

  void _onPanEnd() {
    setState(() {
      _isPanning = false;
      _kineticEnergy = _lastPositionDelta;
    });
  }

  // ---------------------------------------------------------------------------
  // Mobile multi-touch gesture handlers
  // ---------------------------------------------------------------------------

  void _cancelMobileSingleFingerOps() {
    if (_isDrawing) {
      setState(() {
        _isDrawing = false;
        _tempDrawingObject = null;
        _currentPencilPoints = [];
      });
    }
    if (_isDraggingSelection) {
      _isDraggingSelection = false;
    }
    if (_isResizing.handle != Handle.none) {
      _isResizing = (objectId: '', handle: Handle.none);
      _originalResizeRect = null;
    }
    if (_isAreaSelecting) {
      setState(() {
        _isAreaSelecting = false;
        _selectionArea = Rect.zero;
      });
    }
  }

  bool _isConnectableObject(DrawingObject obj) {
    return obj is SvgObject ||
        obj is RectangleObject ||
        obj is CircleObject ||
        obj is FigureObject;
  }

  /// Resolves the actual start/end positions of an [ArrowObject] by looking up
  /// its ObjectAttachments against current canvas state. Matches the logic used
  /// by the render object at paint time so hit testing aligns with visuals.
  ({Offset start, Offset end}) _resolveArrowEndpoints(ArrowObject arrow) {
    final canvasState = _canvasBloc.state;
    var start = arrow.start;
    var end = arrow.end;

    final startAttachment = arrow.startAttachment;
    if (startAttachment != null) {
      final targetNode = canvasState.nodes[startAttachment.objectId];
      final targetObject =
          canvasState.drawingObjects[startAttachment.objectId];
      final Rect? targetRect = targetNode != null
          ? getNodeBoundsInWorld(targetNode)
          : targetObject?.rect;
      if (targetRect != null) {
        final relPos = startAttachment.relativePosition;
        start = targetRect.topLeft +
            Offset(
              targetRect.width * relPos.dx,
              targetRect.height * relPos.dy,
            );
      }
    }

    final endAttachment = arrow.endAttachment;
    if (endAttachment != null) {
      final targetNode = canvasState.nodes[endAttachment.objectId];
      final targetObject =
          canvasState.drawingObjects[endAttachment.objectId];
      final Rect? targetRect = targetNode != null
          ? getNodeBoundsInWorld(targetNode)
          : targetObject?.rect;
      if (targetRect != null) {
        final relPos = endAttachment.relativePosition;
        end = targetRect.topLeft +
            Offset(
              targetRect.width * relPos.dx,
              targetRect.height * relPos.dy,
            );
      }
    }

    return (start: start, end: end);
  }

  void _createConnectionBetween(DrawingObject objA, DrawingObject objB) {
    final centerA = objA.rect.center;
    final centerB = objB.rect.center;

    // Find the closest border points facing each other
    final startPoint = getClosestPointOnRectBorder(centerB, objA.rect);
    final endPoint = getClosestPointOnRectBorder(centerA, objB.rect);

    // Compute 0-1 normalised positions for snap-to attachments
    final relStart = Offset(
      (startPoint.dx - objA.rect.left) /
          objA.rect.width.clamp(0.001, double.infinity),
      (startPoint.dy - objA.rect.top) /
          objA.rect.height.clamp(0.001, double.infinity),
    );
    final relEnd = Offset(
      (endPoint.dx - objB.rect.left) /
          objB.rect.width.clamp(0.001, double.infinity),
      (endPoint.dy - objB.rect.top) /
          objB.rect.height.clamp(0.001, double.infinity),
    );

    final arrowId = const Uuid().v4();
    final newArrow = ArrowObject(
      id: arrowId,
      start: startPoint,
      end: endPoint,
      startAttachment: ObjectAttachment(
        objectId: objA.id,
        relativePosition: relStart,
      ),
      endAttachment: ObjectAttachment(
        objectId: objB.id,
        relativePosition: relEnd,
      ),
    );

    _canvasBloc.add(DrawingObjectAdded(newArrow));
    // Select the new arrow so the user can immediately adjust its bezier handle
    _selectionBloc.add(SelectionReplaced(drawingObjectIds: {arrowId}));
  }

  void _onMobileScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
    _mobileStartFocal = details.focalPoint;
    _mobileGestureStartTime = DateTime.now();
    _mobileInitialZoom = _canvasBloc.state.viewportZoom;
    _mobileMoved = false;

    if (details.pointerCount >= 2) {
      _mobileIsPanZoom = true;
      _cancelMobileSingleFingerOps();
      return;
    }

    _mobileIsPanZoom = false;

    final worldPos = screenToWorld(
      details.focalPoint,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    // 1. Always check resize/rotate handles first (regardless of active tool)
    _updateHoveredHandle(details.focalPoint);
    if (_hoveredHandle.handle != Handle.none) {
      _isResizing = _hoveredHandle;
      _originalResizeRect =
          _canvasBloc.state.drawingObjects[_isResizing.objectId]?.rect;
      return;
    }

    // 2. Check if finger hit an existing object
    final hitObjectId = _findHitObject(worldPos);
    if (hitObjectId != null) {
      final canvasState = _canvasBloc.state;

      // If one object is already selected and we tap a different connectable
      // object, auto-create a red bezier connection line between them.
      final currentSel = _selectionBloc.state;
      if (currentSel.selectedDrawingObjectIds.length == 1) {
        final selectedId = currentSel.selectedDrawingObjectIds.first;
        if (selectedId != hitObjectId) {
          final selObj = canvasState.drawingObjects[selectedId];
          final hitObj = canvasState.drawingObjects[hitObjectId];
          if (selObj != null &&
              hitObj != null &&
              _isConnectableObject(selObj) &&
              _isConnectableObject(hitObj)) {
            _createConnectionBetween(selObj, hitObj);
            return;
          }
        }
      }

      // Otherwise, just select the tapped object + prepare drag
      final isNode = canvasState.nodes.containsKey(hitObjectId);
      final nodeIds = isNode ? {hitObjectId} : <String>{};
      final drawingObjectIds = !isNode ? {hitObjectId} : <String>{};

      _selectionBloc.add(
        SelectionReplaced(
          nodeIds: nodeIds,
          drawingObjectIds: drawingObjectIds,
        ),
      );
      _isDraggingSelection = true;
      return;
    }

    // 3. Nothing hit → clear selection and use the active tool
    _selectionBloc.add(SelectionCleared());

    final tool = _toolBloc.state.activeTool;
    if (tool == EditorTool.arrow || tool == EditorTool.add) {
      // Start area selection
      setState(() {
        _isAreaSelecting = true;
        _selectionStart = worldPos;
        _selectionArea = Rect.fromPoints(worldPos, worldPos);
      });
    } else {
      // Start drawing with the active tool
      _updateSnapHandle(worldPos);
      _handleDrawingToolPointerDown(
        PointerDownEvent(position: details.focalPoint, pressure: 1.0),
        worldPos,
      );
    }
  }

  void _onMobileScaleUpdate(ScaleUpdateDetails details) {
    _lastFocalPoint = details.focalPoint;

    // Two-finger (or was already two-finger) → pan + zoom
    if (details.pointerCount >= 2 || _mobileIsPanZoom) {
      if (!_mobileIsPanZoom) {
        _mobileIsPanZoom = true;
        _cancelMobileSingleFingerOps();
      }

      // Pan
      if (details.focalPointDelta.distanceSquared > 0) {
        final panDelta =
            details.focalPointDelta / _canvasBloc.state.viewportZoom;
        _canvasBloc.add(CanvasPanned(panDelta));
      }

      // Zoom
      if (details.scale != 1.0) {
        final newZoom =
            (_mobileInitialZoom * details.scale).clamp(0.1, 10.0);
        _canvasBloc.add(CanvasZoomed(newZoom));
      }
      return;
    }

    // Track total movement for tap / long-press detection
    if ((details.focalPoint - _mobileStartFocal).distance > 10.0) {
      _mobileMoved = true;
    }

    final worldPos = screenToWorld(
      details.focalPoint,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    _updateSnapHandle(worldPos);

    if (_isResizing.handle != Handle.none) {
      _handleObjectResizing(worldPos);
    } else if (_isDraggingSelection) {
      final dragDelta =
          details.focalPointDelta / _canvasBloc.state.viewportZoom;
      _canvasBloc.add(
        ObjectsDragged(
          _selectionBloc.state.selectedNodeIds.union(
            _selectionBloc.state.selectedDrawingObjectIds,
          ),
          dragDelta,
        ),
      );
    } else if (_isAreaSelecting) {
      setState(
        () => _selectionArea = Rect.fromPoints(_selectionStart, worldPos),
      );
    } else if (_isDrawing) {
      _handleObjectDrawing(worldPos, 1.0);
    }
  }

  void _onMobileScaleEnd(ScaleEndDetails details) {
    if (_mobileIsPanZoom) {
      _mobileIsPanZoom = false;
      return;
    }

    final duration = DateTime.now().difference(_mobileGestureStartTime);

    // Finalize any in-progress operations
    if (_isAreaSelecting) _finalizeAreaSelection();
    if (_isDrawing) _finalizeDrawing();
    if (_isResizing.handle != Handle.none) {
      _lastCompletedResize = _isResizing;
      _finalizeResizing();
      _canvasBloc.add(const ObjectsResizeEnded());
    }
    if (_isDraggingSelection) {
      _canvasBloc.add(const ObjectsDragEnded());
    }

    // Double-tap detection (only for short taps)
    if (!_mobileMoved && duration < const Duration(milliseconds: 300)) {
      final now = DateTime.now();
      if (_mobileLastTapTime != null &&
          now.difference(_mobileLastTapTime!) <
              const Duration(milliseconds: 300)) {
        _onDoubleClick();
        _mobileLastTapTime = null;
      } else {
        _mobileLastTapTime = now;

        // Single tap on a TextObject → fire the viewer callback
        final config = FlDrawConfig.of(context);
        if (config?.onTextObjectTapped != null) {
          final worldPos = screenToWorld(
            _mobileStartFocal,
            _canvasBloc.state.viewportOffset,
            _canvasBloc.state.viewportZoom,
          );
          if (worldPos != null) {
            final hitId = _findHitObject(worldPos);
            if (hitId != null) {
              final hitObj = _canvasBloc.state.drawingObjects[hitId];
              if (hitObj is TextObject) {
                config!.onTextObjectTapped!(hitObj);
              }
            }
          }
        }
      }
    } else {
      _mobileLastTapTime = null;
    }

    // Reset state
    _isDraggingSelection = false;
    _isResizing = (objectId: '', handle: Handle.none);
    _originalResizeRect = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final state = _canvasBloc.state;
    if (details.scale != 1.0) {
      final newZoom = state.viewportZoom * details.scale;
      _canvasBloc.add(CanvasZoomed(newZoom.clamp(0.1, 10.0)));
    } else if (details.focalPointDelta.distanceSquared > 0) {
      _onPanUpdate(details.focalPointDelta);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final state = _canvasBloc.state;
      final zoomDelta = -event.scrollDelta.dy * 0.001;
      final newZoom = state.viewportZoom * (1 + zoomDelta);
      _canvasBloc.add(CanvasZoomed(newZoom.clamp(0.1, 10.0)));
    }
  }

  void _startKineticTimer() {
    _kineticTimer?.cancel();
    _kineticTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isPanning && _kineticEnergy.distance > 0.1) {
        final panDelta = _kineticEnergy / _canvasBloc.state.viewportZoom;
        _canvasBloc.add(CanvasPanned(panDelta));
        setState(() => _kineticEnergy *= 0.9);
      } else {
        timer.cancel();
      }
    });
  }

  void _resetKineticTimer() {
    _kineticTimer?.cancel();
    _startKineticTimer();
  }

  void _onPointerDown(PointerDownEvent event) {
    _lastFocalPoint = event.position;
    final worldPos = screenToWorld(
      event.position,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    final tool = _toolBloc.state.activeTool;

    if (event.buttons == kMiddleMouseButton) {
      _onPanStart();
      return;
    }

    if (tool == EditorTool.arrow) {
      _handleArrowToolPointerDown(event, worldPos);
    } else {
      _handleDrawingToolPointerDown(event, worldPos);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isPanning) {
      _onPanUpdate(event.delta);
      return;
    }

    final worldPos = screenToWorld(
      event.position,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    _updateSnapHandle(worldPos);

    if (_isResizing.handle != Handle.none) {
      _handleObjectResizing(worldPos);
    } else if (_isDraggingSelection) {
      // Scale-correct drag: diff of world positions (handles an ancestor
      // Transform.scale). Falls back to the raw delta if the previous world
      // position can't be resolved.
      final prevWorld = screenToWorld(
        event.position - event.delta,
        _canvasBloc.state.viewportOffset,
        _canvasBloc.state.viewportZoom,
      );
      final dragDelta = prevWorld != null
          ? (worldPos - prevWorld)
          : (event.delta / _canvasBloc.state.viewportZoom);
      _canvasBloc.add(
        ObjectsDragged(
          _selectionBloc.state.selectedNodeIds.union(
            _selectionBloc.state.selectedDrawingObjectIds,
          ),
          dragDelta,
        ),
      );
    } else if (_isAreaSelecting) {
      setState(
        () => _selectionArea = Rect.fromPoints(_selectionStart, worldPos),
      );
    } else if (_isDrawing) {
      _handleObjectDrawing(worldPos, event.pressure);
    } else {
      _updateHoveredHandle(event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isPanning) _onPanEnd();
    if (_isAreaSelecting) _finalizeAreaSelection();
    if (_isDrawing) _finalizeDrawing();

    if (_isResizing.handle != Handle.none) {
      _finalizeResizing();
      _canvasBloc.add(const ObjectsResizeEnded());
    }

    if (_isDraggingSelection) {
      _canvasBloc.add(const ObjectsDragEnded());
    }

    _isDraggingSelection = false;
    _isResizing = (objectId: '', handle: Handle.none);
    _originalResizeRect = null;
  }

  void _onDoubleClick() {
    final worldPos = screenToWorld(
      _lastFocalPoint,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    // Check for vertex hit on lines/arrows first
    if (_tryVertexDoubleTap(worldPos)) return;

    // Fallback: if the last resize was on an arrow/line handle, use that
    // directly. This handles cases where the position hit-test misses due
    // to micro-movement during the resize.
    if (_lastCompletedResize.handle != Handle.none) {
      final resizeObj = _canvasBloc.state.drawingObjects[_lastCompletedResize.objectId];
      if (resizeObj != null) {
        final isLineOrArrow = resizeObj is ArrowObject || resizeObj is LineObject;
        if (isLineOrArrow) {
          final config = FlDrawConfig.of(context);
          if (config?.onVertexDoubleTapped != null) {
            final handle = _lastCompletedResize.handle;
            Offset vertexPos = worldPos;
            if (resizeObj is ArrowObject) {
              final resolved = _resolveArrowEndpoints(resizeObj);
              if (handle == Handle.arrowStart) vertexPos = resolved.start;
              else if (handle == Handle.arrowEnd) vertexPos = resolved.end;
              else if (handle == Handle.midPoint) vertexPos = resizeObj.midPoint ?? (resolved.start + resolved.end) / 2.0;
            } else if (resizeObj is LineObject) {
              if (handle == Handle.arrowStart) vertexPos = resizeObj.start;
              else if (handle == Handle.arrowEnd) vertexPos = resizeObj.end;
              else if (handle == Handle.midPoint) vertexPos = resizeObj.midPoint ?? (resizeObj.start + resizeObj.end) / 2.0;
            }
            _handleVertexAnnotation(resizeObj, handle, vertexPos, config!.onVertexDoubleTapped!);
            _lastCompletedResize = (objectId: '', handle: Handle.none);
            return;
          }
        }
      }
      _lastCompletedResize = (objectId: '', handle: Handle.none);
    }

    final hitObject = _findHitObject(worldPos);
    if (hitObject != null) {
      final obj = _canvasBloc.state.drawingObjects[hitObject];
      if (obj is TextObject) {
        _beginTextEditing(existingObject: obj);
        return;
      }
      if (obj is SvgObject) {
        final config = FlDrawConfig.of(context);
        config?.onSvgDoubleTapped?.call(obj);
        return;
      }
      if (obj is ReferencePointObject) {
        _canvasBloc.add(ObjectsRemoved(
          nodeIds: const {},
          drawingObjectIds: {obj.id},
        ));
        return;
      }
    }
  }

  /// Returns true if the double-tap landed on a line/arrow vertex and was handled.
  bool _tryVertexDoubleTap(Offset worldPos) {
    final config = FlDrawConfig.of(context);
    if (config?.onVertexDoubleTapped == null) return false;

    final zoom = _canvasBloc.state.viewportZoom;
    final handleHitAreaRadius = (_isMobile ? 24.0 : 10.0) / zoom;

    for (final entry in _canvasBloc.state.drawingObjects.entries) {
      final obj = entry.value;
      Map<Handle, Offset>? handles;

      if (obj is ArrowObject) {
        final resolved = _resolveArrowEndpoints(obj);
        final start = resolved.start;
        final end = resolved.end;
        final midPoint = obj.midPoint ?? (start + end) / 2.0;
        final onCurveMidPoint = (start * 0.25) + (midPoint * 0.5) + (end * 0.25);
        handles = {
          Handle.arrowStart: start,
          Handle.arrowEnd: end,
          Handle.midPoint: obj.pathType == LinkPathType.orthogonal
              ? (obj.end.dx - obj.start.dx).abs() > (obj.end.dy - obj.start.dy).abs()
                  ? Offset(end.dx, start.dy)
                  : Offset(start.dx, end.dy)
              : onCurveMidPoint,
        };
      } else if (obj is LineObject) {
        final start = obj.start;
        final end = obj.end;
        final midPoint = obj.midPoint ?? (start + end) / 2.0;
        final onCurveMidPoint = (start * 0.25) + (midPoint * 0.5) + (end * 0.25);
        handles = {
          Handle.arrowStart: start,
          Handle.arrowEnd: end,
          Handle.midPoint: onCurveMidPoint,
        };
      }

      if (handles == null) continue;

      for (final h in handles.entries) {
        if ((worldPos - h.value).distance < handleHitAreaRadius) {
          _handleVertexAnnotation(obj, h.key, h.value, config!.onVertexDoubleTapped!);
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _handleVertexAnnotation(
    DrawingObject obj,
    Handle handle,
    Offset vertexPosition,
    Future<VertexAnnotation?> Function(
      DrawingObject, Handle, Offset, VertexAnnotation?,
    ) callback,
  ) async {
    final handleKey = handle.name;
    final Map<String, VertexAnnotation> annotations;
    if (obj is ArrowObject) {
      annotations = obj.vertexAnnotations;
    } else if (obj is LineObject) {
      annotations = obj.vertexAnnotations;
    } else {
      return;
    }

    final existing = annotations[handleKey];
    final result = await callback(obj, handle, vertexPosition, existing);

    if (!mounted || result == null) return;

    final newAnnotations = Map<String, VertexAnnotation>.from(annotations);
    if (result.isEmpty) {
      newAnnotations.remove(handleKey);
    } else {
      newAnnotations[handleKey] = result;
    }

    final DrawingObject updated;
    if (obj is ArrowObject) {
      updated = obj.copyWith(vertexAnnotations: newAnnotations);
    } else {
      updated = (obj as LineObject).copyWith(vertexAnnotations: newAnnotations);
    }
    _canvasBloc.add(DrawingObjectUpdated(updated));
  }

  void _handleArrowToolPointerDown(PointerDownEvent event, Offset worldPos) {
    _updateHoveredHandle(event.position);
    if (_hoveredHandle.handle != Handle.none) {
      _isResizing = _hoveredHandle;
      _originalResizeRect =
          _canvasBloc.state.drawingObjects[_isResizing.objectId]?.rect;
      return;
    }

    final hitObjectId = _findHitObject(worldPos);
    if (hitObjectId != null) {
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final currentSelection = _selectionBloc.state;
      final isNode = _canvasBloc.state.nodes.containsKey(hitObjectId);

      final alreadySelected = isNode
          ? currentSelection.selectedNodeIds.contains(hitObjectId)
          : currentSelection.selectedDrawingObjectIds.contains(hitObjectId);

      if (!alreadySelected) {
        final nodeIds = isNode ? {hitObjectId} : <String>{};
        final drawingObjectIds = !isNode ? {hitObjectId} : <String>{};

        if (isShiftPressed) {
          _selectionBloc.add(
            SelectionObjectsAdded(
              nodeIds: nodeIds,
              drawingObjectIds: drawingObjectIds,
            ),
          );
        } else {
          _selectionBloc.add(
            SelectionReplaced(
              nodeIds: nodeIds,
              drawingObjectIds: drawingObjectIds,
            ),
          );
        }
      }
      _isDraggingSelection = true;
      return;
    }

    setState(() {
      _isAreaSelecting = true;
      _selectionStart = worldPos;
      _selectionArea = Rect.fromPoints(worldPos, worldPos);
    });
  }

  void _handleDrawingToolPointerDown(PointerDownEvent event, Offset worldPos) {
    final tool = _toolBloc.state.activeTool;
    _isDrawing = true;
    _drawingStart = _hoveredSnapPoint?.worldPosition ?? worldPos;
    _startSnapPoint = _hoveredSnapPoint;

    if (tool == EditorTool.text) {
      _beginTextEditing(at: _drawingStart);
      return;
    }

    if (tool == EditorTool.referencePoint) {
      final id = const Uuid().v4();
      final radius = 6.0 / _canvasBloc.state.viewportZoom;
      final newObject = ReferencePointObject(
        id: id,
        position: _drawingStart,
        radius: radius,
      );
      _canvasBloc.add(DrawingObjectAdded(newObject));
      _toolBloc.add(const ToolSelected(EditorTool.arrow));
      _isDrawing = false;
      return;
    }

    setState(() {
      if (tool == EditorTool.pencil) {
        _currentPencilPoints = [
          PointVector(_drawingStart.dx, _drawingStart.dy, event.pressure),
        ];
        _tempDrawingObject = TempDrawingObject(
          tool: tool,
          start: _drawingStart,
          end: _drawingStart,
          points: _currentPencilPoints,
        );
      } else {
        _tempDrawingObject = TempDrawingObject(
          tool: tool,
          start: _drawingStart,
          end: _drawingStart,
        );
      }
    });
  }

  void _handleObjectResizing(Offset worldPos) {
    final objectId = _isResizing.objectId;
    final handle = _isResizing.handle;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null) return;

    // Handle rotation for SvgObject
    if (handle == Handle.rotate && object is SvgObject) {
      final center = object.rect.center;
      final angle = atan2(worldPos.dy - center.dy, worldPos.dx - center.dx);
      // Offset so dragging straight up = 0 rotation
      final rotation = angle + pi / 2;
      final updatedObject = object.copyWith(rotation: rotation);
      _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      return;
    }

    if (_originalResizeRect == null) return;

    final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (object is ArrowObject) {
      // Use resolved positions so handles track the visual arrow endpoints
      final resolved = _resolveArrowEndpoints(object);
      final start = resolved.start;
      final end = resolved.end;
      final pathType = object.pathType;

      if (pathType == LinkPathType.orthogonal) {
        Offset newStart = start;
        Offset newEnd = end;
        Offset cornerDelta;
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;

        if (dx.abs() > dy.abs()) {
          cornerDelta = Offset(end.dx, start.dy);
        } else {
          cornerDelta = Offset(start.dx, end.dy);
        }

        if (handle == Handle.arrowStart || handle == Handle.arrowEnd) {
          final dragDelta =
              worldPos - (handle == Handle.arrowStart ? start : end);
          if (dragDelta.dx.abs() > dragDelta.dy.abs()) {
            if (handle == Handle.arrowStart) {
              newStart = Offset(worldPos.dx, start.dy);
            } else {
              newEnd = Offset(worldPos.dx, end.dy);
            }
          } else {
            if (handle == Handle.arrowStart) {
              newStart = Offset(start.dx, worldPos.dy);
            } else {
              newEnd = Offset(end.dx, worldPos.dy);
            }
          }
        } else if (handle == Handle.midPoint) {
          final dx = end.dx - start.dx;
          final dy = end.dy - start.dy;

          if (dx.abs() > dy.abs()) {
            cornerDelta = worldPos - Offset(end.dx, start.dy);
            newStart = Offset(start.dx, start.dy + cornerDelta.dy);
            newEnd = Offset(end.dx + cornerDelta.dx, end.dy);
          } else {
            cornerDelta = worldPos - Offset(start.dx, end.dy);
            newStart = Offset(start.dx + cornerDelta.dx, start.dy);
            newEnd = Offset(end.dx, end.dy + cornerDelta.dy);
          }
        }

        final updatedObject = (object).copyWith(
          start: newStart,
          end: newEnd,
          midPoint: cornerDelta,
          // Detach from objects when user manually repositions endpoints
          clearStartAttachment: handle == Handle.arrowStart,
          clearEndAttachment: handle == Handle.arrowEnd,
        );
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      } else {
        if (handle == Handle.arrowStart) {
          final updatedObject = object.copyWith(
            start: worldPos,
            clearStartAttachment: true,
          );
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        } else if (handle == Handle.arrowEnd) {
          final updatedObject = object.copyWith(
            end: worldPos,
            clearEndAttachment: true,
          );
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        } else if (handle == Handle.midPoint) {
          final midPoint = (worldPos * 2) - (start * 0.5) - (end * 0.5);
          final updatedObject = object.copyWith(midPoint: midPoint);
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        }
      }
      return;
    } else if (object is LineObject) {
      final start = object.start;
      final end = object.end;

      if (_isResizing.handle == Handle.arrowStart) {
        final updatedObject = object.copyWith(start: worldPos);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      } else if (_isResizing.handle == Handle.arrowEnd) {
        final updatedObject = object.copyWith(end: worldPos);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      } else if (_isResizing.handle == Handle.midPoint) {
        final midPoint = (worldPos * 2) - (start * 0.5) - (end * 0.5);
        final updatedObject = object.copyWith(midPoint: midPoint);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      }
    } else if (object is RectangleObject ||
        object is CircleObject ||
        object is FigureObject ||
        object is SvgObject) {
      Rect oldRect = object.rect;
      Offset anchor;
      switch (handle) {
        case Handle.topLeft:
          anchor = oldRect.bottomRight;
          break;
        case Handle.topRight:
          anchor = oldRect.bottomLeft;
          break;
        case Handle.bottomRight:
          anchor = oldRect.topLeft;
          break;
        case Handle.bottomLeft:
          anchor = oldRect.topRight;
          break;
        default:
          return;
      }

      Rect newRect;
      final bool lockAspect = object is SvgObject ||
          (isShiftPressed &&
              _originalResizeRect!.width > 0 &&
              _originalResizeRect!.height > 0);
      if (lockAspect) {
        final aspectRatio =
            _originalResizeRect!.width / _originalResizeRect!.height;
        newRect = _resizeWithAspectRatio(
          worldPos: worldPos,
          originalAspectRatio: aspectRatio,
          anchor: anchor,
        );
      } else {
        newRect = Rect.fromPoints(anchor, worldPos);
      }

      final updatedObject = (object as dynamic).copyWith(rect: newRect);
      if (updatedObject != null) {
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      }
    } else if (object is PencilStrokeObject) {
      // todo: still pencil strokes cannot be resized
    }
  }

  void _handleObjectDrawing(Offset worldPos, double pressure) {
    final tool = _toolBloc.state.activeTool;
    final endPos = _hoveredSnapPoint?.worldPosition ?? worldPos;
    if (tool == EditorTool.pencil) {
      setState(() {
        _currentPencilPoints.add(PointVector(endPos.dx, endPos.dy, pressure));
        if (_tempDrawingObject != null) {
          _tempDrawingObject = TempDrawingObject(
            tool: _tempDrawingObject!.tool,
            start: _tempDrawingObject!.start,
            end: endPos,
            points: _currentPencilPoints,
          );
        }
      });
    } else {
      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
      Offset finalPos = endPos;
      LinkPathType pathType = LinkPathType.straight;

      if (isShiftPressed) {
        if (tool == EditorTool.square ||
            tool == EditorTool.circle ||
            tool == EditorTool.figure) {
          final dx = worldPos.dx - _drawingStart.dx;
          final dy = worldPos.dy - _drawingStart.dy;
          final side = max(dx.abs(), dy.abs());
          finalPos = Offset(
            _drawingStart.dx + side * dx.sign,
            _drawingStart.dy + side * dy.sign,
          );
        } else if (tool == EditorTool.line) {
          finalPos = _snapPointToAngle(_drawingStart, worldPos);
        } else if (tool == EditorTool.arrowTopRight) {
          if (isCtrlPressed) {
            pathType = LinkPathType.orthogonal;
            finalPos = worldPos;
          } else {
            finalPos = _snapPointToAngle(_drawingStart, worldPos);
          }
        }
      }
      if (_tempDrawingObject != null) {
        _tempDrawingObject = TempDrawingObject(
          tool: _tempDrawingObject!.tool,
          start: _tempDrawingObject!.start,
          end: finalPos,
          pathType: pathType,
          points: _tempDrawingObject!.points,
        );
      }
      setState(() {});
    }
  }

  void _finalizeAreaSelection() {
    final selectedArea = _selectionArea.normalize;
    final tapSlop =
        (_isMobile ? 24.0 : 10.0) / _canvasBloc.state.viewportZoom;
    if (selectedArea.size.longestSide > tapSlop) {
      final holdSelection =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isShiftPressed;
      final (nodes, objects) = _findObjectsInArea(selectedArea);

      if (holdSelection) {
        _selectionBloc.add(
          SelectionObjectsAdded(nodeIds: nodes, drawingObjectIds: objects),
        );
      } else {
        _selectionBloc.add(
          SelectionReplaced(nodeIds: nodes, drawingObjectIds: objects),
        );
      }
    } else if (!HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _selectionBloc.add(SelectionCleared());
    }
    setState(() {
      _isAreaSelecting = false;
      _selectionArea = Rect.zero;
    });
  }

  void _finalizeDrawing() {
    if (_tempDrawingObject == null) return;

    final tool = _tempDrawingObject!.tool;
    DrawingObject? newObject;
    final id = const Uuid().v4();

    final endPos = _hoveredSnapPoint?.worldPosition ?? _tempDrawingObject!.end;

    ObjectAttachment? startAttachment = _startSnapPoint != null
        ? ObjectAttachment(
            objectId: _startSnapPoint!.objectId,
            relativePosition: _startSnapPoint!.relativePosition,
          )
        : null;

    ObjectAttachment? endAttachment = _hoveredSnapPoint != null
        ? ObjectAttachment(
            objectId: _hoveredSnapPoint!.objectId,
            relativePosition: _hoveredSnapPoint!.relativePosition,
          )
        : null;

    if (tool == EditorTool.arrowTopRight) {
      newObject = ArrowObject(
        id: id,
        start: _drawingStart,
        end: endPos,
        pathType: _tempDrawingObject!.pathType,
        startAttachment: startAttachment,
        endAttachment: endAttachment,
      );
    } else if (tool == EditorTool.pencil) {
      if (_currentPencilPoints.length > 1) {
        newObject = PencilStrokeObject(id: id, points: _currentPencilPoints);
      }
    } else {
      final rect = Rect.fromPoints(
        _drawingStart,
        _tempDrawingObject!.end,
      ).normalize;
      if (rect.width > 2 || rect.height > 2) {
        switch (tool) {
          case EditorTool.circle:
            newObject = CircleObject(id: id, rect: rect);
            break;
          case EditorTool.square:
            newObject = RectangleObject(id: id, rect: rect);
            break;
          case EditorTool.arrowTopRight:
            newObject = ArrowObject(
              id: id,
              start: _drawingStart,
              end: _tempDrawingObject!.end,
              pathType: _tempDrawingObject!.pathType,
            );
            break;
          case EditorTool.line:
            newObject = LineObject(
              id: id,
              start: _drawingStart,
              end: _tempDrawingObject!.end,
            );
            break;
          case EditorTool.figure:
            newObject = FigureObject(id: id, rect: rect);
            break;
          case EditorTool.text:
            newObject = TextObject(id: id, rect: rect);
            break;
          default:
            break;
        }
      }
    }

    if (newObject != null) {
      _canvasBloc.add(DrawingObjectAdded(newObject));
    }

    setState(() {
      _isDrawing = false;
      _tempDrawingObject = null;
      _currentPencilPoints = [];
      _startSnapPoint = null;
      _hoveredSnapPoint = null;
    });
  }

  void _finalizeResizing() {
    final objectId = _isResizing.objectId;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null) return;

    dynamic finalObject = object;

    // Check if the end of the resize lands on a snap point
    if (_hoveredSnapPoint != null && (object is ArrowObject)) {
      final endAttachment = ObjectAttachment(
        objectId: _hoveredSnapPoint!.objectId,
        relativePosition: _hoveredSnapPoint!.relativePosition,
      );
      if (_isResizing.handle == Handle.arrowEnd) {
        finalObject = (object).copyWith(endAttachment: endAttachment);
      } else if (_isResizing.handle == Handle.arrowStart) {
        finalObject = (object).copyWith(startAttachment: endAttachment);
      }
    }

    if (finalObject.rect.width < 0 || finalObject.rect.height < 0) {
      finalObject = (finalObject as dynamic).copyWith(
        rect: finalObject.rect.normalize,
      );
    }

    _canvasBloc.add(DrawingObjectUpdated(finalObject));
  }

  String? _findHitObject(Offset worldPos) {
    final canvasState = _canvasBloc.state;
    final tolerance =
        (_isMobile ? 16.0 : 8.0) / canvasState.viewportZoom;

    for (final obj in canvasState.drawingObjects.values.toList().reversed) {
      if (obj is ArrowObject) {
        final resolved = _resolveArrowEndpoints(obj);
        final start = resolved.start;
        final end = resolved.end;
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final cornerPoint = (dx.abs() > dy.abs())
            ? Offset(end.dx, start.dy)
            : Offset(start.dx, end.dy);

        final controlPoint = obj.midPoint ?? cornerPoint;

        Path path;
        if (obj.pathType == LinkPathType.orthogonal) {
          path = Path();
          path.moveTo(start.dx, start.dy);
          if (dx.abs() > dy.abs()) {
            path.lineTo(end.dx, start.dy);
            path.lineTo(end.dx, end.dy);
          } else {
            path.lineTo(start.dx, end.dy);
            path.lineTo(end.dx, end.dy);
          }
        } else {
          path = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(
              controlPoint.dx,
              controlPoint.dy,
              end.dx,
              end.dy,
            );
        }

        if (isPointNearPath(path, worldPos, tolerance)) {
          return obj.id;
        }
      } else if (obj is LineObject) {
        final start = (obj as dynamic).start;
        final end = (obj as dynamic).end;
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final cornerPoint = (dx.abs() > dy.abs())
            ? Offset(end.dx, start.dy)
            : Offset(start.dx, end.dy);

        final controlPoint = (obj as dynamic).midPoint ?? cornerPoint;

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, end.dx, end.dy);

        if (isPointNearPath(path, worldPos, tolerance)) {
          return obj.id;
        }
      } else if (obj is ReferencePointObject) {
        final hitRadius = (obj.radius + tolerance);
        if ((worldPos - obj.position).distance < hitRadius) {
          return obj.id;
        }
      } else if (obj is SvgObject && obj.rotation != 0.0) {
        // For rotated SVGs, transform the hit point into unrotated space
        final center = obj.rect.center;
        final cosR = cos(-obj.rotation);
        final sinR = sin(-obj.rotation);
        final dx = worldPos.dx - center.dx;
        final dy = worldPos.dy - center.dy;
        final localPos = Offset(
          center.dx + dx * cosR - dy * sinR,
          center.dy + dx * sinR + dy * cosR,
        );
        final hitRect =
            _isMobile ? obj.rect.inflate(tolerance) : obj.rect;
        if (hitRect.contains(localPos)) {
          return obj.id;
        }
      } else {
        final hitRect =
            _isMobile ? obj.rect.inflate(tolerance) : obj.rect;
        if (hitRect.contains(worldPos)) {
          return obj.id;
        }
      }
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds != null && nodeBounds.contains(worldPos)) {
        return node.id;
      }
    }

    return null;
  }

  bool isPointNearPath(Path path, Offset point, double tolerance) {
    final pathBounds = path.getBounds();
    if (!pathBounds.inflate(tolerance).contains(point)) {
      return false;
    }

    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 2.0) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null &&
            (tangent.position - point).distance < tolerance) {
          return true;
        }
      }
    }
    return false;
  }

  (Set<String>, Set<String>) _findObjectsInArea(Rect area) {
    final Set<String> nodeIds = {};
    final Set<String> drawingObjectIds = {};

    for (final node in _canvasBloc.state.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds != null && area.overlaps(nodeBounds)) {
        nodeIds.add(node.id);
      }
    }

    for (final obj in _canvasBloc.state.drawingObjects.values) {
      if (area.overlaps(obj.rect)) {
        drawingObjectIds.add(obj.id);
      }
    }
    return (nodeIds, drawingObjectIds);
  }

  void _updateHoveredHandle(Offset screenPosition) {
    final selectionState = _selectionBloc.state;
    if (selectionState.selectedDrawingObjectIds.isEmpty) {
      if (_hoveredHandle.handle != Handle.none) {
        setState(() => _hoveredHandle = (objectId: '', handle: Handle.none));
      }
      return;
    }

    final canvasState = _canvasBloc.state;
    final worldPos = screenToWorld(
      screenPosition,
      canvasState.viewportOffset,
      canvasState.viewportZoom,
    );
    if (worldPos == null) return;

    final handleHitAreaRadius =
        (_isMobile ? 14.0 : 10.0) / canvasState.viewportZoom;

    for (final objectId in selectionState.selectedDrawingObjectIds) {
      final obj = canvasState.drawingObjects[objectId];
      if (obj == null) continue;

      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is FigureObject ||
          obj is SvgObject ||
          obj is PencilStrokeObject) {
        final selectionRect = obj.rect.inflate(4.0 / canvasState.viewportZoom);

        // On mobile, skip corner-handle detection when the touch is deep inside
        // the object body — the user likely wants to drag, not resize.
        if (_isMobile) {
          final edgeInset = handleHitAreaRadius * 2.5;
          final innerRect = selectionRect.deflate(edgeInset);
          if (innerRect.width > 0 && innerRect.height > 0) {
            // For rotated SvgObjects, check in local (unrotated) coordinates
            Offset testPos = worldPos;
            if (obj is SvgObject && obj.rotation != 0.0) {
              final center = obj.rect.center;
              final cosR = cos(-obj.rotation);
              final sinR = sin(-obj.rotation);
              final dx = worldPos.dx - center.dx;
              final dy = worldPos.dy - center.dy;
              testPos = Offset(
                center.dx + dx * cosR - dy * sinR,
                center.dy + dx * sinR + dy * cosR,
              );
            }
            if (innerRect.contains(testPos)) {
              // Touch is inside the body — skip handle detection for this object
              continue;
            }
          }
        }

        // For SvgObject, only rotation handle — no corner resize handles.
        if (obj is SvgObject) {
          final rotateHandleOffset = 30.0 / canvasState.viewportZoom;
          final topCenter = Offset(selectionRect.center.dx, selectionRect.top);
          // Transform the handle position by the object's rotation
          final center = obj.rect.center;
          final cosR = cos(obj.rotation);
          final sinR = sin(obj.rotation);
          final localHandle = topCenter - Offset(0, rotateHandleOffset);
          final dx = localHandle.dx - center.dx;
          final dy = localHandle.dy - center.dy;
          final rotatedHandle = Offset(
            center.dx + dx * cosR - dy * sinR,
            center.dy + dx * sinR + dy * cosR,
          );
          if ((worldPos - rotatedHandle).distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != Handle.rotate) {
              setState(
                () => _hoveredHandle = (objectId: objectId, handle: Handle.rotate),
              );
            }
            return;
          }
          // Skip corner handles for SvgObject — size is controlled via slider.
          continue;
        }

        final handles = {
          Handle.topLeft: selectionRect.topLeft,
          Handle.topRight: selectionRect.topRight,
          Handle.bottomRight: selectionRect.bottomRight,
          Handle.bottomLeft: selectionRect.bottomLeft,
        };

        for (final entry in handles.entries) {
          if ((worldPos - entry.value).distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != entry.key) {
              setState(
                () => _hoveredHandle = (objectId: objectId, handle: entry.key),
              );
            }
            return;
          }
        }
      } else if (obj is ArrowObject) {
        final resolved = _resolveArrowEndpoints(obj);
        final start = resolved.start;
        final end = resolved.end;
        final midPoint = obj.midPoint ?? (start + end) / 2.0;

        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final Offset cornerPoint;
        if (dx.abs() > dy.abs()) {
          cornerPoint = Offset(end.dx, start.dy);
        } else {
          cornerPoint = Offset(start.dx, end.dy);
        }

        final onCurveMidPoint =
            (start * 0.25) + (midPoint * 0.5) + (end * 0.25);

        final handles = {
          Handle.arrowStart: start,
          Handle.arrowEnd: end,
          Handle.midPoint: obj.pathType == LinkPathType.orthogonal
              ? cornerPoint
              : onCurveMidPoint,
        };
        for (final entry in handles.entries) {
          if ((worldPos - entry.value).distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != entry.key) {
              setState(
                () => _hoveredHandle = (objectId: objectId, handle: entry.key),
              );
            }
            return;
          }
        }
      } else if (obj is LineObject) {
        final start = (obj as dynamic).start;
        final end = (obj as dynamic).end;
        final midPoint = (obj as dynamic).midPoint ?? (start + end) / 2.0;
        final onCurveMidPoint =
            (start * 0.25) + (midPoint * 0.5) + (end * 0.25);
        final handles = {
          Handle.arrowStart: start,
          Handle.arrowEnd: end,
          Handle.midPoint: onCurveMidPoint,
        };
        for (final entry in handles.entries) {
          if ((worldPos - entry.value).distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != entry.key) {
              setState(
                () => _hoveredHandle = (objectId: objectId, handle: entry.key),
              );
            }
            return;
          }
        }
      }
    }

    if (_hoveredHandle.handle != Handle.none) {
      setState(() => _hoveredHandle = (objectId: '', handle: Handle.none));
    }
  }

  Rect _resizeWithAspectRatio({
    required Offset worldPos,
    required double originalAspectRatio,
    required Offset anchor,
  }) {
    final dx = worldPos.dx - anchor.dx;
    final dy = worldPos.dy - anchor.dy;
    double newWidth, newHeight;
    if ((dx.abs() * (1 / originalAspectRatio)) > dy.abs()) {
      newWidth = dx.abs();
      newHeight = newWidth / originalAspectRatio;
    } else {
      newHeight = dy.abs();
      newWidth = newHeight * originalAspectRatio;
    }
    return Rect.fromLTWH(
      (dx < 0) ? anchor.dx - newWidth : anchor.dx,
      (dy < 0) ? anchor.dy - newHeight : anchor.dy,
      newWidth,
      newHeight,
    );
  }

  Offset _snapPointToAngle(Offset startPoint, Offset currentPoint) {
    final dx = currentPoint.dx - startPoint.dx;
    final dy = currentPoint.dy - startPoint.dy;
    final angle = atan2(dy, dx);
    final distance = sqrt(dx * dx + dy * dy);
    const snapAngleIncrement = pi / 4;
    final snappedAngle =
        (angle / snapAngleIncrement).round() * snapAngleIncrement;
    final newDx = cos(snappedAngle) * distance;
    final newDy = sin(snappedAngle) * distance;
    return Offset(startPoint.dx + newDx, startPoint.dy + newDy);
  }

  void _beginTextEditing({TextObject? existingObject, Offset? at}) {
    if (existingObject == null && at == null) return;

    // Check if the host app wants to handle text input via callback
    final config = FlDrawConfig.of(context);
    if (config?.onTextInputRequested != null) {
      _beginTextEditingViaCallback(
        callback: config!.onTextInputRequested!,
        existingObject: existingObject,
        at: at,
      );
      return;
    }

    final TextObject object;
    if (existingObject != null) {
      object = existingObject;
      _selectionBloc.add(SelectionReplaced(drawingObjectIds: {object.id}));
    } else {
      object = TextObject(
        id: const Uuid().v4(),
        rect: Rect.fromLTWH(at!.dx, at.dy, 60, 20),
        text: 'Text',
      );
      _canvasBloc.add(DrawingObjectAdded(object));
      _selectionBloc.add(SelectionReplaced(drawingObjectIds: {object.id}));
    }

    setState(() {
      object.isEditing = true;
    });

    final textEditingController = TextEditingController(text: object.text);
    final focusNode = FocusNode();
    OverlayEntry? overlayEntry;

    void _submitAndClose() {
      if (!mounted) return;
      final newText = textEditingController.text;

      setState(() {
        object.isEditing = false;
      });

      if (newText.trim().isEmpty) {
        _canvasBloc.add(
          ObjectsRemoved(nodeIds: {}, drawingObjectIds: {object.id}),
        );
      } else {
        final textPainter = TextPainter(
          text: TextSpan(text: newText, style: object.style),
          textDirection: TextDirection.ltr,
        )..layout();

        setState(() {
          object.text = newText;
          object.rect = Rect.fromLTWH(
            object.rect.left,
            object.rect.top,
            textPainter.width,
            textPainter.height,
          );
        });
      }

      // focusNode.dispose();
      textEditingController.dispose();
      overlayEntry?.remove();
    }

    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        _submitAndClose();
      }
    });

    overlayEntry = OverlayEntry(
      builder: (context) {
        final editorBox =
            kNodeEditorWidgetKey.currentContext!.findRenderObject()
                as RenderBox;
        final editorSize = editorBox.size;
        final editorGlobalOffset = editorBox.localToGlobal(Offset.zero);

        Offset worldToGlobal(Offset worldPoint) {
          final screenPointX =
              (worldPoint.dx + offset.dx) * zoom + editorSize.width / 2;
          final screenPointY =
              (worldPoint.dy + offset.dy) * zoom + editorSize.height / 2;
          return Offset(screenPointX, screenPointY) + editorGlobalOffset;
        }

        final globalPosition = worldToGlobal(object.rect.topLeft);

        final screenSize = Size(
          object.rect.width * zoom,
          object.rect.height * zoom,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  focusNode.unfocus();
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              width: max(100, screenSize.width),
              height: max(30, screenSize.height),
              child: Material(
                color: Colors.transparent,
                child: TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  style: object.style.copyWith(
                    fontSize: object.style.fontSize! * zoom,
                  ),
                  maxLines: null,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submitAndClose(),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(overlayEntry);
  }

  /// Handle text input via the host app's callback (e.g. a dictation bottom sheet).
  Future<void> _beginTextEditingViaCallback({
    required Future<String?> Function(Offset position, String? existingText)
        callback,
    TextObject? existingObject,
    Offset? at,
  }) async {
    final bool isNew = existingObject == null;
    final position = existingObject?.rect.topLeft ?? at!;
    final existingText = existingObject?.text;

    final result = await callback(position, isNew ? null : existingText);

    if (!mounted) return;

    if (result == null || result.trim().isEmpty) {
      // Cancelled — nothing to do (object wasn't created yet for new, leave
      // existing unchanged for edits)
      return;
    }

    // Determine text color from the editor style
    final strokeColor =
        widget.style.defaultStrokeColor ?? Colors.white;
    const fontSize = 12.0;
    final textStyle = TextStyle(fontSize: fontSize, color: strokeColor);

    // Size the hit-rect to the text (dot gap + text + padding) so the whole
    // label is selectable, not just the anchor dot.
    final tp = TextPainter(
      text: TextSpan(text: result, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 240.0);
    final double rw = 7.0 + tp.width + 6.0;
    final double rh = tp.height + 4.0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (isNew) {
      final newObject = TextObject(
        id: const Uuid().v4(),
        rect: Rect.fromLTWH(position.dx, position.dy - rh / 2, rw, rh),
        text: result,
        style: textStyle,
        timestamp: now,
      );
      _canvasBloc.add(DrawingObjectAdded(newObject));
      _selectionBloc.add(SelectionReplaced(drawingObjectIds: {newObject.id}));
    } else {
      final obj = existingObject!;
      final updated = obj.copyWith(
        text: result,
        style: textStyle,
        rect: Rect.fromLTWH(
            obj.rect.left, obj.rect.center.dy - rh / 2, rw, rh),
        timestamp: now,
      );
      _canvasBloc.add(DrawingObjectUpdated(updated));
      _selectionBloc
          .add(SelectionReplaced(drawingObjectIds: {obj.id}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, canvasState) {
        return BlocBuilder<SelectionBloc, SelectionState>(
          builder: (context, selectionState) {
            return BlocBuilder<ToolBloc, ToolState>(
              builder: (context, toolState) {
                final Widget canvasChild = RepaintBoundary(
                  child: ShaderBuilder(
                    assetKey: widget.fragmentShader,
                    (context, gridShader, child) =>
                        FlDrawEditorRenderObjectWidget(
                          key: kNodeEditorWidgetKey,
                          canvasState: canvasState,
                          selectionState: selectionState,
                          style: widget.style,
                          gridShader: gridShader,
                          tempDrawingObject: _tempDrawingObject,
                          selectionArea: _selectionArea,
                          headerBuilder: widget.headerBuilder,
                          nodeBuilder: widget.nodeBuilder,
                          snapHandlePosition: _hoveredSnapPoint?.worldPosition,
                        ),
                  ),
                );

                if (_isMobile) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onMobileScaleStart,
                    onScaleUpdate: _onMobileScaleUpdate,
                    onScaleEnd: _onMobileScaleEnd,
                    child: canvasChild,
                  );
                }

                return KeyboardWidget(
                  bindings: [
                    KeyAction(
                      LogicalKeyboardKey.delete,
                      "Remove selected items",
                      () => _canvasBloc.add(
                        ObjectsRemoved(
                          nodeIds: selectionState.selectedNodeIds,
                          drawingObjectIds:
                              selectionState.selectedDrawingObjectIds,
                        ),
                      ),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.backspace,
                      "Remove selected items",
                      () => _canvasBloc.add(
                        ObjectsRemoved(
                          nodeIds: selectionState.selectedNodeIds,
                          drawingObjectIds:
                              selectionState.selectedDrawingObjectIds,
                        ),
                      ),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyC,
                      "Copy selection",
                      () async {
                        await ClipboardService.copySelection(
                          allNodes: canvasState.nodes,
                          selectedNodeIds: selectionState.selectedNodeIds,
                        );
                      },
                      isControlPressed: true,
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyV,
                      "Paste selection",
                      () {
                        final worldPos =
                            screenToWorld(
                              _lastFocalPoint,
                              canvasState.viewportOffset,
                              canvasState.viewportZoom,
                            ) ??
                            Offset.zero;
                        _canvasBloc.add(
                          SelectionPasted(pastePosition: worldPos),
                        );
                      },
                      isControlPressed: true,
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyX,
                      "Cut selection",
                      () async {
                        final copied = await ClipboardService.copySelection(
                          allNodes: canvasState.nodes,
                          selectedNodeIds: selectionState.selectedNodeIds,
                        );
                        if (copied != null) {
                          _canvasBloc.add(
                            ObjectsRemoved(
                              nodeIds: selectionState.selectedNodeIds,
                              drawingObjectIds:
                                  selectionState.selectedDrawingObjectIds,
                            ),
                          );
                        }
                      },
                      isControlPressed: true,
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyZ,
                      "Undo",
                      () => _canvasBloc.add(UndoRequested()),
                      isControlPressed: true,
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyY,
                      "Redo",
                      () => _canvasBloc.add(RedoRequested()),
                      isControlPressed: true,
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyV,
                      "Select Arrow Tool",
                      () => _toolBloc.add(const ToolSelected(EditorTool.arrow)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyP,
                      "Select Reference Point Tool",
                      () => _toolBloc.add(const ToolSelected(EditorTool.referencePoint)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyR,
                      "Select Rectangle Tool",
                      () =>
                          _toolBloc.add(const ToolSelected(EditorTool.square)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyO,
                      "Select Circle Tool",
                      () =>
                          _toolBloc.add(const ToolSelected(EditorTool.circle)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyA,
                      "Select Arrow Drawing Tool",
                      () => _toolBloc.add(
                        const ToolSelected(EditorTool.arrowTopRight),
                      ),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyL,
                      "Select Line Tool",
                      () => _toolBloc.add(const ToolSelected(EditorTool.line)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyD,
                      "Select Pencil (Draw) Tool",
                      () =>
                          _toolBloc.add(const ToolSelected(EditorTool.pencil)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyT,
                      "Select Text Tool",
                      () => _toolBloc.add(const ToolSelected(EditorTool.text)),
                    ),
                    KeyAction(
                      LogicalKeyboardKey.keyF,
                      "Select Figure Tool",
                      () =>
                          _toolBloc.add(const ToolSelected(EditorTool.figure)),
                    ),
                  ],
                  child: MouseRegion(
                    cursor: _getCursor(toolState.activeTool),
                    onHover: (event) {
                      if (!_isDrawing &&
                          _isResizing.handle == Handle.none &&
                          !_isDraggingSelection &&
                          !_isPanning) {
                        _updateHoveredHandle(event.position);
                      }
                    },
                    onExit: (event) {
                      if (_hoveredHandle.handle != Handle.none) {
                        setState(
                          () => _hoveredHandle = (
                            objectId: '',
                            handle: Handle.none,
                          ),
                        );
                      }
                    },
                    child: ImprovedListener(
                      behavior: HitTestBehavior.translucent,
                      onDoubleClick: _onDoubleClick,
                      onPointerPressed: _onPointerDown,
                      onPointerMoved: _onPointerMove,
                      onPointerReleased: _onPointerUp,
                      onPointerSignalReceived: _onPointerSignal,
                      onPointerPanZoomStart:
                          _toolBloc.state.activeTool == EditorTool.arrow
                          ? _trackpadGestureRecognizer.addPointerPanZoom
                          : null,
                      child: canvasChild,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  SystemMouseCursor _getCursor(EditorTool currentTool) {
    if (_hoveredHandle.handle != Handle.none) {
      switch (_hoveredHandle.handle) {
        case Handle.topLeft:
        case Handle.bottomRight:
          return SystemMouseCursors.resizeUpLeftDownRight;
        case Handle.topRight:
        case Handle.bottomLeft:
          return SystemMouseCursors.resizeUpRightDownLeft;
        case Handle.arrowStart:
        case Handle.arrowEnd:
          return SystemMouseCursors.resizeColumn;
        case Handle.midPoint:
          return SystemMouseCursors.grab;
        case Handle.rotate:
          return SystemMouseCursors.click;
        default:
          return SystemMouseCursors.basic;
      }
    }
    if (_isPanning) return SystemMouseCursors.move;

    switch (currentTool) {
      case EditorTool.arrow:
        return SystemMouseCursors.basic;
      default:
        return SystemMouseCursors.precise;
    }
  }
}
