import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/constants.dart';
import 'package:fldraw/src/core/utils/renderbox.dart';
import 'package:fldraw/src/gen/assets.gen.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide TabItem;
import 'package:uuid/uuid.dart';

import 'custom_tab.dart';

class FlToolbar extends StatelessWidget {
  final List<String> svgs;
  final bool showUtilityTools;

  /// Target screen-space width (in logical pixels) for newly placed SVG
  /// objects. The actual world-coordinate size is computed by dividing this
  /// value by the current viewport zoom so that the SVG appears at a
  /// consistent visual size regardless of zoom level.
  /// When `null` (the default), the SVG's natural pixel size is used.
  final double? targetSvgScreenWidth;

  /// Whether to show keyboard shortcut labels on buttons (e.g. "V", "R").
  /// Set to false for mobile-first apps where shortcuts aren't used.
  final bool showShortcutLabels;

  /// Color for toolbar icons. Defaults to white when null.
  final Color? iconColor;

  /// Background color for tab groups. When null, uses shadcn theme default.
  final Color? tabBackgroundColor;

  /// Background color for the selected/active tab. When null, uses shadcn
  /// theme default.
  final Color? tabSelectedColor;

  /// Optional override for the "+" (add-object) tool. When provided, tapping
  /// the add button invokes this callback instead of showing fldraw's built-in
  /// flat SVG popover — letting the host present its own asset picker (e.g. a
  /// grouped/categorized sheet). The passed context is the add button's
  /// element, suitable for anchoring a popover or opening a modal sheet.
  final void Function(BuildContext context)? onAddPressed;

  const FlToolbar({
    super.key,
    required this.svgs,
    this.showUtilityTools = true,
    this.targetSvgScreenWidth,
    this.showShortcutLabels = true,
    this.iconColor,
    this.tabBackgroundColor,
    this.tabSelectedColor,
    this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.symmetric(vertical: 10.0);

    final toolBloc = context.watch<ToolBloc>();

    void onToolSelected(int index, BuildContext? popoverContext) {
      final tool = EditorTool.values.elementAt(index);

      if (tool == EditorTool.add) {
        if (popoverContext == null) return;
        if (onAddPressed != null) {
          onAddPressed!(popoverContext);
        } else {
          _showAddPopover(popoverContext);
        }
      } else {
        toolBloc.add(ToolSelected(tool));
      }
    }

    return BlocBuilder<ToolBloc, ToolState>(
      builder: (context, state) {
        final ic = iconColor ?? Colors.white;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                return CustomTabs(
                  index: state.activeTool.index,
                  backgroundColor: tabBackgroundColor,
                  selectedColor: tabSelectedColor,
                  onChanged: (index) =>
                      onToolSelected(index, index == 9 ? context : null),
                  children: [
                    TabItem(
                      index: 9,
                      child: SizedBox(
                        child: Padding(
                          padding: padding.copyWith(
                            top: padding.top + 2,
                            bottom: padding.bottom + 2,
                          ),
                          child: showShortcutLabels
                              ? Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Assets.icons.add.svg(width: 16, color: ic),
                                    Positioned(
                                      bottom: -10,
                                      right: -10,
                                      child: Text(
                                        '/',
                                        style: TextStyle(fontSize: 10, color: ic),
                                      ),
                                    ),
                                  ],
                                )
                              : Assets.icons.add.svg(width: 16, color: ic),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Gap(16),
            CustomTabs(
              index: state.activeTool.index,
              backgroundColor: tabBackgroundColor,
              selectedColor: tabSelectedColor,
              onChanged: (index) => onToolSelected(index, null),
              children: [
                TabItem(
                  index: EditorTool.arrow.index,
                  child: Padding(
                    padding: padding,
                    child: showShortcutLabels
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.arrow.svg(width: 16, color: ic),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('V', style: TextStyle(fontSize: 10, color: ic)),
                              ),
                            ],
                          )
                        : Assets.icons.arrow.svg(width: 16, color: ic),
                  ),
                ),
                TabItem(
                  index: EditorTool.referencePoint.index,
                  child: Padding(
                    padding: padding,
                    child: showShortcutLabels
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.my_location, size: 16, color: ic),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('P', style: TextStyle(fontSize: 10, color: ic)),
                              ),
                            ],
                          )
                        : Icon(Icons.my_location, size: 16, color: ic),
                  ),
                ),
                TabItem(
                  index: EditorTool.square.index,
                  child: Padding(
                    padding: padding,
                    child: showShortcutLabels
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.square.svg(width: 16, color: ic),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('R', style: TextStyle(fontSize: 10, color: ic)),
                              ),
                            ],
                          )
                        : Assets.icons.square.svg(width: 16, color: ic),
                  ),
                ),
                TabItem(
                  index: EditorTool.circle.index,
                  child: Padding(
                    padding: padding,
                    child: showShortcutLabels
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.circle.svg(width: 16, color: ic),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('O', style: TextStyle(fontSize: 10, color: ic)),
                              ),
                            ],
                          )
                        : Assets.icons.circle.svg(width: 16, color: ic),
                  ),
                ),
                TabItem(
                  index: EditorTool.arrowTopRight.index,
                  child: Padding(
                    padding: padding,
                    child: showShortcutLabels
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.arrowTopRight.svg(width: 16, color: ic),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('A', style: TextStyle(fontSize: 10, color: ic)),
                              ),
                            ],
                          )
                        : Assets.icons.arrowTopRight.svg(width: 16, color: ic),
                  ),
                ),
                TabItem(
                  index: EditorTool.line.index,
                  child: Padding(
                    padding: padding,
                    child: showShortcutLabels
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Assets.icons.line.svg(width: 16, color: ic),
                              Positioned(
                                bottom: -10,
                                right: -10,
                                child: Text('L', style: TextStyle(fontSize: 10, color: ic)),
                              ),
                            ],
                          )
                        : Assets.icons.line.svg(width: 16, color: ic),
                  ),
                ),
              ],
            ),
            if (showUtilityTools) ...[
              Gap(16),
              CustomTabs(
                index: state.activeTool.index,
                backgroundColor: tabBackgroundColor,
                selectedColor: tabSelectedColor,
                onChanged: (index) => onToolSelected(index, null),
                children: [
                  TabItem(
                    index: 7,
                    child: Padding(
                      padding: padding.copyWith(
                        top: padding.top + 2,
                        bottom: padding.bottom + 2,
                      ),
                      child: showShortcutLabels
                          ? Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Assets.icons.figure.svg(width: 16, color: ic),
                                Positioned(
                                  bottom: -10,
                                  right: -10,
                                  child: Text('F', style: TextStyle(fontSize: 10, color: ic)),
                                ),
                              ],
                            )
                          : Assets.icons.figure.svg(width: 16, color: ic),
                    ),
                  ),
                  TabItem(
                    index: 8,
                    child: Padding(
                      padding: padding,
                      child: showShortcutLabels
                          ? Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Assets.icons.comment.svg(width: 16, color: ic),
                                Positioned(
                                  bottom: -10,
                                  right: -10,
                                  child: Text('C', style: TextStyle(fontSize: 10, color: ic)),
                                ),
                              ],
                            )
                          : Assets.icons.comment.svg(width: 16, color: ic),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  void _showAddPopover(BuildContext context) {
    final canvasBloc = context.read<CanvasBloc>();
    final toolBloc = context.read<ToolBloc>();

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileScreen = screenWidth < 600;
    final popoverWidth = isMobileScreen
        ? (screenWidth - 32).clamp(200.0, 460.0)
        : 460.0;

    showPopover(
      context: context,
      alignment: Alignment.topCenter,
      offset: isMobileScreen ? const Offset(0, 8) : const Offset(240, 8),
      builder: (context) {
        // Skip ModalContainer / SurfaceCard: shadcn's dark theme
        // scales the fill via theme.surfaceOpacity, so even a fully-
        // white fillColor renders as a dark-tinted glass. Wrap the
        // content in a plain Material so the white reads as the
        // user-requested "slightly translucent white" without the
        // theme touching it.
        return material.Material(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 280),
            child: SizedBox(
              width: popoverWidth,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isMobileScreen ? 5 : 8,
                    crossAxisSpacing: isMobileScreen ? 12 : 16,
                    mainAxisSpacing: isMobileScreen ? 12 : 16,
                  ),
                  itemCount: svgs.length,
                  itemBuilder: (context, index) => material.InkWell(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(8)),
                    onTap: () {
                      closeOverlay(context, svgs.elementAt(index));
                    },
                    child: material.Ink(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.18),
                          width: 1,
                        ),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(8)),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: SvgPicture.asset(
                        svgs[index],
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF222222),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).future.then((value) async {
      if (value != null && value is String) {
        final String svgString = await rootBundle.loadString(value);
        final pictureInfo = await vg.loadPicture(
          SvgStringLoader(svgString),
          null,
        );
        final Size svgSize = pictureInfo.size;

        final canvasState = canvasBloc.state;
        final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
        final centerOfScreenWorldPos =
            screenToWorld(
              editorBounds?.center ?? Offset.zero,
              canvasState.viewportOffset,
              canvasState.viewportZoom,
            ) ??
            Offset.zero;

        // If there's already an SvgObject on the canvas, match its size
        // so subsequent placements are consistent with any user resizing.
        SvgObject? lastSvg;
        for (final obj in canvasState.drawingObjects.values) {
          if (obj is SvgObject) lastSvg = obj;
        }

        final double placementWidth;
        final double placementHeight;
        if (lastSvg != null) {
          placementWidth = lastSvg.rect.width;
          placementHeight = lastSvg.rect.height;
        } else if (targetSvgScreenWidth != null &&
            svgSize.width.isFinite &&
            svgSize.width > 0) {
          final aspectRatio = svgSize.height / svgSize.width;
          placementWidth =
              targetSvgScreenWidth! / canvasState.viewportZoom;
          placementHeight = placementWidth * aspectRatio;
        } else {
          placementWidth =
              svgSize.width.isFinite ? svgSize.width : 100.0;
          placementHeight =
              svgSize.height.isFinite ? svgSize.height : 100.0;
        }

        final initialRect = Rect.fromCenter(
          center: centerOfScreenWorldPos,
          width: placementWidth,
          height: placementHeight,
        );

        // Auto-assign next sequential unit number
        int nextUnit = 1;
        for (final obj in canvasState.drawingObjects.values) {
          if (obj is SvgObject && obj.label.isNotEmpty) {
            final n = int.tryParse(obj.label);
            if (n != null && n >= nextUnit) {
              nextUnit = n + 1;
            }
          }
        }

        final newObject = SvgObject(
          id: const Uuid().v4(),
          rect: initialRect,
          assetPath: value,
          pictureInfo: pictureInfo,
          label: '$nextUnit',
        );

        canvasBloc.add(DrawingObjectAdded(newObject));
        // Switch to arrow tool so the user can immediately interact
        toolBloc.add(const ToolSelected(EditorTool.arrow));
      }
    });
  }
}
