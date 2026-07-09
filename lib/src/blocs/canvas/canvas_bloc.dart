import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fldraw/src/core/node_editor/clipboard.dart';
import 'package:fldraw/src/core/utils/snackbar.dart';
import 'package:fldraw/src/models/drawing_entities.dart';
import 'package:fldraw/src/models/entities.dart';
import 'package:flutter/services.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

part 'canvas_event.dart';
part 'canvas_state.dart';

class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  static const int _maxHistoryStack = 100;

  CanvasBloc() : super(const CanvasState()) {
    on<CanvasPanned>(_onCanvasPanned);
    on<CanvasZoomed>(_onCanvasZoomed);
    on<ViewportSet>(_onViewportSet);
    on<NodeAdded>(_onNodeAdded);
    on<DrawingObjectAdded>(_onDrawingObjectAdded);
    on<ObjectsRemoved>(_onObjectsRemoved);
    on<ObjectsDragged>(_onObjectsDragged);
    on<ObjectsDragEnded>(_onObjectsDragEnded);
    on<DrawingObjectUpdated>(_onDrawingObjectUpdated);
    on<ObjectsResizeEnded>(_onObjectsResizeEnded);
    on<NodeValueUpdated>(_onNodeValueUpdated);
    on<NodeHeadingUpdated>(_onNodeHeadingUpdated);
    on<NodeToggled>(_onNodeToggled);
    on<UndoRequested>(_onUndo);
    on<RedoRequested>(_onRedo);
    on<ProjectSaved>(_onProjectSaved);
    on<ProjectLoaded>(_onProjectLoaded);
    on<NewProjectCreated>(_onNewProjectCreated);
    on<SelectionCut>(_onSelectionCut);
    on<SelectionPasted>(_onSelectionPasted);
  }

  void _emitWithHistory(
    CanvasState newState,
    CanvasEvent event,
    Emitter<CanvasState> emit,
  ) {
    if (event.isUndoable) {
      final historicState = CanvasState.historic(
        nodes: state.nodes,
        drawingObjects: state.drawingObjects,
        viewportOffset: state.viewportOffset,
        viewportZoom: state.viewportZoom,
      );

      final newUndoStack = List<HistoryEntry>.from(state.undoStack)
        ..add((historicState, event));
      if (newUndoStack.length > _maxHistoryStack) {
        newUndoStack.removeAt(0);
      }
      // Emit the new state with an updated undo stack and cleared redo stack
      emit(newState.copyWith(undoStack: newUndoStack, redoStack: []));
    } else {
      // If the event is not undoable (like a drag update), just emit the new state
      // but preserve the existing history.
      emit(
        newState.copyWith(
          undoStack: state.undoStack,
          redoStack: state.redoStack,
        ),
      );
    }
  }

  void _pushToUndoStack(
    CanvasEvent event,
    Emitter<CanvasState> emit,
    CanvasState currentState,
  ) {
    if (!event.isUndoable) return;

    final historicState = CanvasState.historic(
      nodes: currentState.nodes,
      drawingObjects: currentState.drawingObjects,
      viewportOffset: currentState.viewportOffset,
      viewportZoom: currentState.viewportZoom,
    );

    final newUndoStack = List<HistoryEntry>.from(currentState.undoStack)
      ..add((historicState, event));
    if (newUndoStack.length > _maxHistoryStack) {
      newUndoStack.removeAt(0);
    }
    emit(state.copyWith(undoStack: newUndoStack, redoStack: []));
  }

  void _onCanvasPanned(CanvasPanned event, Emitter<CanvasState> emit) {
    emit(state.copyWith(viewportOffset: state.viewportOffset + event.delta));
  }

  void _onCanvasZoomed(CanvasZoomed event, Emitter<CanvasState> emit) {
    emit(state.copyWith(viewportZoom: event.zoom));
  }

  void _onViewportSet(ViewportSet event, Emitter<CanvasState> emit) {
    emit(state.copyWith(viewportZoom: event.zoom, viewportOffset: event.offset));
  }

  void _onNodeAdded(NodeAdded event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    newNodes[event.node.id] = event.node;
    emit(state.copyWith(nodes: newNodes));
  }

  void _onDrawingObjectAdded(
    DrawingObjectAdded event,
    Emitter<CanvasState> emit,
  ) {
    _pushToUndoStack(event, emit, state);
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    );
    newDrawingObjects[event.object.id] = event.object;
    emit(state.copyWith(drawingObjects: newDrawingObjects));
  }

  void _onObjectsRemoved(ObjectsRemoved event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes)
      ..removeWhere((key, _) => event.nodeIds.contains(key));
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    )..removeWhere((key, _) => event.drawingObjectIds.contains(key));
    emit(state.copyWith(nodes: newNodes, drawingObjects: newDrawingObjects));
  }

  void _onObjectsResizeEnded(
    ObjectsResizeEnded event,
    Emitter<CanvasState> emit,
  ) {
    // This event IS undoable. We push the current state to the undo stack.
    _pushToUndoStack(event, emit, state);
  }

  void _onDrawingObjectUpdated(
    DrawingObjectUpdated event,
    Emitter<CanvasState> emit,
  ) {
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    );
    newDrawingObjects[event.object.id] = event.object;
    emit(state.copyWith(drawingObjects: newDrawingObjects));
  }

  void _onNodeValueUpdated(NodeValueUpdated event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final node = newNodes[event.nodeId];
    if (node != null) {
      newNodes[event.nodeId] = node.copyWith(value: event.value);
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onNodeHeadingUpdated(
    NodeHeadingUpdated event,
    Emitter<CanvasState> emit,
  ) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final node = newNodes[event.nodeId];
    if (node != null) {
      newNodes[event.nodeId] = node.copyWith(heading: event.heading);
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onNodeToggled(NodeToggled event, Emitter<CanvasState> emit) {
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final node = newNodes[event.nodeId];
    if (node != null) {
      _pushToUndoStack(event, emit, state);
      final oldState = node.state;
      newNodes[event.nodeId] = node.copyWith(
        state: NodeState(
          isSelected: oldState.isSelected,
          isCollapsed: !oldState.isCollapsed,
        ),
      );
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onObjectsDragged(ObjectsDragged event, Emitter<CanvasState> emit) {
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    );
    for (final id in event.objectIds) {
      if (newNodes.containsKey(id)) {
        final node = newNodes[id]!;
        newNodes[id] = node.copyWith(offset: node.offset + event.delta);
      } else if (newDrawingObjects.containsKey(id)) {
        final object = newDrawingObjects[id]!;
        // Your existing drag logic for drawing objects is correct...
        final effectiveDelta = event.delta;
        if (object is ArrowObject) {
          object.start += effectiveDelta;
          object.end += effectiveDelta;
          if (object.midPoint != null) {
            object.midPoint = object.midPoint! + effectiveDelta;
          }
        } else if (object is LineObject) {
          object.start += effectiveDelta;
          object.end += effectiveDelta;
          if (object.midPoint != null) {
            object.midPoint = object.midPoint! + effectiveDelta;
          }
        } else if (object is PencilStrokeObject) {
          object.points = object.points
              .map(
                (p) => PointVector(
                  p.x + effectiveDelta.dx,
                  p.y + effectiveDelta.dy,
                  p.pressure,
                ),
              )
              .toList();
        } else if (object is RectangleObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is CircleObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is FigureObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is TextObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is SvgObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is ReferencePointObject) {
          object.position += effectiveDelta;
        }

        newDrawingObjects[id] = object.copyWith();
      }
    }
    // We emit the new state BUT we pass the event, which is marked as NOT undoable.
    _emitWithHistory(
      state.copyWith(nodes: newNodes, drawingObjects: newDrawingObjects),
      event,
      emit,
    );
  }

  void _onObjectsDragEnded(ObjectsDragEnded event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
  }

  void _onUndo(UndoRequested event, Emitter<CanvasState> emit) {
    if (state.undoStack.isEmpty) return;

    final newUndoStack = List<HistoryEntry>.from(state.undoStack);
    final (previousState, lastEvent) = newUndoStack.removeLast();

    final currentStateForRedo = CanvasState.historic(
      nodes: state.nodes,
      drawingObjects: state.drawingObjects,
      viewportOffset: state.viewportOffset,
      viewportZoom: state.viewportZoom,
    );

    final newRedoStack = List<HistoryEntry>.from(state.redoStack)
      ..add((currentStateForRedo, lastEvent));

    emit(
      previousState.copyWith(undoStack: newUndoStack, redoStack: newRedoStack),
    );
  }

  void _onRedo(RedoRequested event, Emitter<CanvasState> emit) {
    if (state.redoStack.isEmpty) return;

    final newRedoStack = List<HistoryEntry>.from(state.redoStack);
    final (nextState, nextEvent) = newRedoStack.removeLast();

    final currentStateForUndo = CanvasState.historic(
      nodes: state.nodes,
      drawingObjects: state.drawingObjects,
      viewportOffset: state.viewportOffset,
      viewportZoom: state.viewportZoom,
    );

    final newUndoStack = List<HistoryEntry>.from(state.undoStack)
      ..add((currentStateForUndo, nextEvent));

    emit(nextState.copyWith(undoStack: newUndoStack, redoStack: newRedoStack));
  }

  void _onNewProjectCreated(
    NewProjectCreated event,
    Emitter<CanvasState> emit,
  ) {
    emit(const CanvasState());
    showNodeEditorSnackbar('New project created.', SnackbarType.success);
  }

  void _onProjectSaved(ProjectSaved event, Emitter<CanvasState> emit) {
    final jsonData = {
      'viewport': {
        'offset': [state.viewportOffset.dx, state.viewportOffset.dy],
        'zoom': state.viewportZoom,
      },
      'nodes': state.nodes.values.map((node) => node.toJson()).toList(),
      'drawingObjects': state.drawingObjects.values
          .map((obj) => obj.toJson())
          .toList(),
    };
    event.onSave(jsonData);
    showNodeEditorSnackbar('Project saved.', SnackbarType.success);
  }

  void _onProjectLoaded(ProjectLoaded event, Emitter<CanvasState> emit) {
    try {
      final viewportJson = event.data['viewport'] as Map<String, dynamic>;
      final offset = Offset(
        viewportJson['offset'][0],
        viewportJson['offset'][1],
      );
      final zoom = viewportJson['zoom'] as double;

      // Tolerate missing nodes/drawingObjects: a JSON round-trip through
      // Firebase RTDB DROPS empty arrays, so `nodes: []` comes back absent
      // (null) and `null as List` would throw, aborting the whole load.
      final nodesList = (event.data['nodes'] as List? ?? const [])
          .map((json) => NodeInstance.fromJson(json))
          .toList();
      final nodes = {for (var node in nodesList) node.id: node};

      final drawingObjectsList = (event.data['drawingObjects'] as List? ??
              const [])
          .map((json) {
            // This logic can be moved to a factory in DrawingObject
            switch (json['type']) {
              case 'rectangle':
                return RectangleObject.fromJson(json);
              case 'circle':
                return CircleObject.fromJson(json);
              case 'arrow':
                return ArrowObject.fromJson(json);
              case 'line':
                return LineObject.fromJson(json);
              case 'pencil_stroke':
                return PencilStrokeObject.fromJson(json);
              case 'figure':
                return FigureObject.fromJson(json);
              case 'text':
                return TextObject.fromJson(json);
              case 'svg':
                return SvgObject.fromJson(json);
              case 'referencePoint':
                return ReferencePointObject.fromJson(json);
              default:
                return null;
            }
          })
          .whereType<DrawingObject>()
          .toList();
      final drawingObjects = {for (var obj in drawingObjectsList) obj.id: obj};

      emit(
        CanvasState(
          viewportOffset: offset,
          viewportZoom: zoom,
          nodes: nodes,
          drawingObjects: drawingObjects,
        ),
      );
    } catch (e, s) {
      // ignore: avoid_print
      print('[fldraw] loadProject parse FAILED: $e');
      throw Exception('Failed to load project: $e\n$s');
    }
  }

  void _onSelectionCut(SelectionCut event, Emitter<CanvasState> emit) {
    // This is an example of composing events. We don't need a separate handler.
    // The clipboard logic will be handled in the UI layer for now.
  }

  void _onSelectionPasted(
    SelectionPasted event,
    Emitter<CanvasState> emit,
  ) async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null || clipboardData.text == null) return;

    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final pasted = ClipboardService.preparePaste(
      clipboardData.text!,
      event.pastePosition,
    );
    if (pasted != null) {
      _pushToUndoStack(event, emit, state);
      for (var node in pasted) {
        newNodes[node.id] = node;
      }
      emit(state.copyWith(nodes: newNodes));
    }
  }
}
