part of 'canvas_bloc.dart';

abstract class CanvasEvent extends Equatable {
  final bool isUndoable;
  const CanvasEvent({this.isUndoable = true});

  String get description => 'Unknown Action';

  @override
  List<Object?> get props => [isUndoable];
}

// --- Viewport Events ---
class CanvasPanned extends CanvasEvent {
  final Offset delta;

  const CanvasPanned(this.delta);

  @override
  String get description => 'Panned Canvas';

  @override
  List<Object> get props => [delta];
}

class CanvasZoomed extends CanvasEvent {
  final double zoom;

  const CanvasZoomed(this.zoom);

  @override
  String get description => 'Zoomed Canvas';

  @override
  List<Object> get props => [zoom];
}

class ViewportSet extends CanvasEvent {
  final double zoom;
  final Offset offset;

  const ViewportSet({required this.zoom, required this.offset})
      : super(isUndoable: false);

  @override
  String get description => 'Set Viewport';

  @override
  List<Object> get props => [zoom, offset];
}

// --- Object Manipulation Events ---
class NodeAdded extends CanvasEvent {
  final NodeInstance node;

  const NodeAdded(this.node);

  @override
  String get description => 'Added Node "${node.heading ?? 'Untitled'}"';

  @override
  List<Object> get props => [node];
}

class DrawingObjectAdded extends CanvasEvent {
  final DrawingObject object;

  const DrawingObjectAdded(this.object);

  @override
  String get description {
    if (object is RectangleObject) return 'Added Rectangle';
    if (object is CircleObject) return 'Added Circle';
    if (object is ArrowObject) return 'Added Arrow';
    if (object is LineObject) return 'Added Line';
    if (object is TextObject) return 'Added Text';
    if (object is FigureObject) return 'Added Figure';
    if (object is PencilStrokeObject) return 'Added Drawing';
    return 'Added Object';
  }

  @override
  List<Object> get props => [object];
}

class ObjectsRemoved extends CanvasEvent {
  final Set<String> nodeIds;
  final Set<String> drawingObjectIds;

  const ObjectsRemoved({required this.nodeIds, required this.drawingObjectIds});

  @override
  String get description {
    final count = nodeIds.length + drawingObjectIds.length;
    return 'Removed $count object(s)';
  }

  @override
  List<Object> get props => [nodeIds, drawingObjectIds];
}

class ObjectsDragged extends CanvasEvent {
  final Set<String> objectIds;
  final Offset delta;

  const ObjectsDragged(this.objectIds, this.delta) : super(isUndoable: false);

  @override
  List<Object> get props => [objectIds, delta];
}

class ObjectsDragEnded extends CanvasEvent {
  // This event marks the end of a drag and IS undoable.
  const ObjectsDragEnded() : super(isUndoable: true);

  @override
  String get description => 'Moved object(s)';
}

class DrawingObjectUpdated extends CanvasEvent {
  final DrawingObject object;

  const DrawingObjectUpdated(this.object);

  @override
  List<Object> get props => [object];
}

class ObjectsResizeEnded extends CanvasEvent {
  const ObjectsResizeEnded() : super(isUndoable: true);

  @override
  String get description => 'Resized object(s)';
}

class NodeValueUpdated extends CanvasEvent {
  final String nodeId;
  final String value;

  const NodeValueUpdated(this.nodeId, this.value);

  @override
  String get description => 'Updated node content: $nodeId';

  @override
  List<Object> get props => [nodeId];
}

class NodeHeadingUpdated extends CanvasEvent {
  final String nodeId;
  final String heading;

  const NodeHeadingUpdated(this.nodeId, this.heading);

  @override
  String get description => 'Updated node heading: $nodeId';

  @override
  List<Object> get props => [nodeId];
}

class NodeToggled extends CanvasEvent {
  final String nodeId;

  const NodeToggled(this.nodeId);

  @override
  String get description => 'Toggled node collapse: $nodeId';

  @override
  List<Object> get props => [nodeId];
}

// --- History Events ---
class UndoRequested extends CanvasEvent {}

class RedoRequested extends CanvasEvent {}

// --- Project Events ---
class ProjectSaved extends CanvasEvent {
  final Function(Map<String, dynamic>) onSave;

  const ProjectSaved({required this.onSave});

  @override
  List<Object> get props => [onSave];
}

class ProjectLoaded extends CanvasEvent {
  final Map<String, dynamic> data;

  const ProjectLoaded(this.data);

  @override
  List<Object> get props => [data];
}

class NewProjectCreated extends CanvasEvent {}

// --- Clipboard Events ---
class SelectionCopied extends CanvasEvent {}

class SelectionCut extends CanvasEvent {}

class SelectionPasted extends CanvasEvent {
  final Offset pastePosition;

  const SelectionPasted({required this.pastePosition});

  @override
  List<Object> get props => [pastePosition];
}
