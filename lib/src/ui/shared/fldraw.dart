import 'dart:async';

import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/core/controller/fldraw_controller.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// InheritedWidget that passes host-app configuration down to fldraw internals.
class FlDrawConfig extends InheritedWidget {
  /// When provided, the host app handles text input instead of the default
  /// inline overlay TextField. Called with the tap position (world coords)
  /// and the existing text (null for new objects). Return the desired text,
  /// or null to cancel.
  final Future<String?> Function(Offset position, String? existingText)?
      onTextInputRequested;

  /// Called when a TextObject is single-tapped on mobile (short tap, no drag).
  /// The host app can use this to show a read-only viewer for the note text.
  final void Function(TextObject object)? onTextObjectTapped;

  /// Called when a vertex (start, end, or midPoint) on a line or arrow is
  /// double-tapped. The host app should show a UI to let the user add/edit a
  /// label or distance annotation.  Return the updated annotation, or null to
  /// cancel.
  final Future<VertexAnnotation?> Function(
    DrawingObject object,
    Handle handle,
    Offset vertexPosition,
    VertexAnnotation? existingAnnotation,
  )? onVertexDoubleTapped;

  /// Called when an SvgObject is double-tapped on the canvas.
  final void Function(SvgObject object)? onSvgDoubleTapped;

  const FlDrawConfig({
    super.key,
    required super.child,
    this.onTextInputRequested,
    this.onTextObjectTapped,
    this.onVertexDoubleTapped,
    this.onSvgDoubleTapped,
  });

  static FlDrawConfig? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FlDrawConfig>();
  }

  @override
  bool updateShouldNotify(FlDrawConfig oldWidget) {
    return onTextInputRequested != oldWidget.onTextInputRequested ||
        onTextObjectTapped != oldWidget.onTextObjectTapped ||
        onVertexDoubleTapped != oldWidget.onVertexDoubleTapped ||
        onSvgDoubleTapped != oldWidget.onSvgDoubleTapped;
  }
}

class FlDraw extends StatefulWidget {
  final Widget child;
  final Function(FlDrawController)? onControllerCreated;

  final void Function(CanvasState)? onCanvasStateChanged;
  final void Function(SelectionState)? onSelectionStateChanged;
  final void Function(ToolState)? onToolStateChanged;

  /// When provided, the host app handles text input instead of the default
  /// inline overlay TextField.
  final Future<String?> Function(Offset position, String? existingText)?
      onTextInputRequested;

  /// Called when a TextObject is single-tapped on mobile (short tap, no drag).
  final void Function(TextObject object)? onTextObjectTapped;

  /// Called when a vertex on a line/arrow is double-tapped.
  final Future<VertexAnnotation?> Function(
    DrawingObject object,
    Handle handle,
    Offset vertexPosition,
    VertexAnnotation? existingAnnotation,
  )? onVertexDoubleTapped;

  /// Called when an SvgObject is double-tapped on the canvas.
  final void Function(SvgObject object)? onSvgDoubleTapped;

  const FlDraw({
    super.key,
    required this.child,
    this.onCanvasStateChanged,
    this.onSelectionStateChanged,
    this.onToolStateChanged, this.onControllerCreated,
    this.onTextInputRequested,
    this.onTextObjectTapped,
    this.onVertexDoubleTapped,
    this.onSvgDoubleTapped,
  });

  @override
  State<FlDraw> createState() => _FlDrawState();
}

class _FlDrawState extends State<FlDraw> {
  FlDrawControllerImpl controller = FlDrawControllerImpl();
  late final CanvasBloc _canvasBloc;
  late final SelectionBloc _selectionBloc;
  late final ToolBloc _toolBloc;

  StreamSubscription? _canvasSub;
  StreamSubscription? _selectionSub;
  StreamSubscription? _toolSub;

  @override
  void initState() {
    super.initState();
    _canvasBloc = CanvasBloc();
    _selectionBloc = SelectionBloc();
    _toolBloc = ToolBloc();

    controller.init(_canvasBloc, _selectionBloc, _toolBloc);
    if(widget.onControllerCreated != null) {
      widget.onControllerCreated!(controller);
    }

    if (widget.onCanvasStateChanged != null) {
      _canvasSub = _canvasBloc.stream.listen(widget.onCanvasStateChanged);
    }

    if (widget.onSelectionStateChanged != null) {
      _selectionSub = _selectionBloc.stream.listen(
        widget.onSelectionStateChanged,
      );
    }

    if (widget.onToolStateChanged != null) {
      _toolSub = _toolBloc.stream.listen(widget.onToolStateChanged);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    _canvasSub?.cancel();
    _selectionSub?.cancel();
    _toolSub?.cancel();

    _canvasBloc.close();
    _selectionBloc.close();
    _toolBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _canvasBloc),
        BlocProvider.value(value: _selectionBloc),
        BlocProvider.value(value: _toolBloc),
      ],
      child: FlDrawConfig(
        onTextInputRequested: widget.onTextInputRequested,
        onTextObjectTapped: widget.onTextObjectTapped,
        onVertexDoubleTapped: widget.onVertexDoubleTapped,
        onSvgDoubleTapped: widget.onSvgDoubleTapped,
        child: ShadcnApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.7),
          home: DrawerOverlay(child: widget.child),
        ),
      ),
    );
  }
}
