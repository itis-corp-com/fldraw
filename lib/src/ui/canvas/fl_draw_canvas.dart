import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/ui/shared/debug_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../ui/nodes/builders.dart';
import 'fldraw_editor_data_layer.dart';

export 'fldraw_editor_data_layer.dart' show FlOverlayData;

class FlDrawCanvas extends StatelessWidget {
  final bool expandToParent;
  final Size? fixedSize;
  final List<FlOverlayData> Function()? overlay;
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final bool debug;
  final FlDrawEditorStyle? style;

  const FlDrawCanvas({
    super.key,
    this.expandToParent = true,
    this.fixedSize,
    this.overlay,
    this.headerBuilder,
    this.nodeBuilder,
    this.debug = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final FlDrawEditorStyle effectiveStyle = style ?? const FlDrawEditorStyle();

    final Widget editor = Container(
      decoration: effectiveStyle.decoration,
      padding: effectiveStyle.padding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FlDrawEditorDataLayer(
              fragmentShader: 'packages/fldraw/shaders/grid.frag',
              style: effectiveStyle,
              headerBuilder: headerBuilder,
              nodeBuilder: nodeBuilder,
            ),
          ),
          if (overlay != null)
            ...overlay!().map(
              (overlayData) => Positioned(
                top: overlayData.top,
                left: overlayData.left,
                bottom: overlayData.bottom,
                right: overlayData.right,
                child: RepaintBoundary(child: overlayData.child),
              ),
            ),
          if (debug) const DebugInfoWidget(),
        ],
      ),
    );

    if (expandToParent) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: editor,
          );
        },
      );
    } else {
      return BlocBuilder<CanvasBloc, CanvasState>(
        builder: (context, state) {
          return SizedBox(
            width: fixedSize?.width ?? 100,
            height: fixedSize?.height ?? 100,
            child: editor,
          );
        },
      );
    }
  }
}
