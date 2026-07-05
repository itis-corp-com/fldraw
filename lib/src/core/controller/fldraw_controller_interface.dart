import 'dart:async';

import 'package:fldraw/fldraw.dart';
import 'package:flutter/widgets.dart';

abstract class FlDrawController {
  Stream<CanvasState> get canvasStateStream;

  CanvasState get canvasState;

  Stream<SelectionState> get selectionStateStream;

  SelectionState get selectionState;

  Stream<ToolState> get toolStateStream;

  ToolState get toolState;

  // --- Tool Methods ---

  void setTool(EditorTool tool);

  // --- History Methods ---

  void undo();

  void redo();

  // --- Object Manipulation Methods ---

  void addNode(NodeInstance node);

  void addDrawingObject(DrawingObject object);

  void updateDrawingObject(DrawingObject object);

  void removeObjects({Set<String> nodeIds, Set<String> drawingObjectIds});

  void removeSelectedObjects();

  // --- Selection Methods ---

  void clearSelection();

  void setSelection({Set<String> nodeIds, Set<String> drawingObjectIds});

  // --- Viewport Methods ---

  void pan(Offset delta);

  void zoom(double newZoom);

  /// Set both zoom and offset atomically (no race conditions).
  void setViewport(double zoom, Offset offset);

  void zoomIn([double factor = 1.2]);

  void zoomOut([double factor = 1.2]);

  void resetZoom();

  void centerView();

  // --- Project Methods ---

  void createNewProject();

  void loadProject(Map<String, dynamic> data);

  void saveProject(Function(Map<String, dynamic>) onSave);

  // --- Lifecycle ---

  void dispose();
}
