import 'package:shadcn_flutter/shadcn_flutter.dart';

class TabContainerData {
  static TabContainerData of(BuildContext context) {
    var data = Data.maybeOf<TabContainerData>(context);
    assert(data != null, 'TabChild must be a descendant of TabContainer');
    return data!;
  }

  int index;
  final int selected;
  final ValueChanged<int>? onSelect;
  final TabChildBuilder childBuilder;

  TabContainerData({
    required this.index,
    required this.selected,
    required this.onSelect,
    required this.childBuilder,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TabContainerData &&
        other.selected == selected &&
        other.onSelect == onSelect &&
        other.index == index &&
        other.childBuilder == childBuilder;
  }

  @override
  int get hashCode => Object.hash(index, selected, onSelect, childBuilder);
}

class CustomTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<TabChild> children;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? selectedColor;

  const CustomTabs({
    super.key,
    required this.index,
    required this.onChanged,
    required this.children,
    this.padding,
    this.backgroundColor,
    this.selectedColor,
  });

  Widget _childBuilder(
      BuildContext context, TabContainerData data, Widget child) {
    final theme = Theme.of(context);
    final scaling = theme.scaling;
    final i = data.index;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        onChanged(i);
      },
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(
              milliseconds: 50),
          alignment: Alignment.center,
          padding: padding ??
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ) *
                  scaling,
          decoration: BoxDecoration(
            color: i == index
                ? (selectedColor ?? theme.colorScheme.background)
                : null,
            borderRadius: BorderRadius.circular(
              theme.radiusMd,
            ),
          ),
          child: (i == index ? child.foreground() : child.muted())
              .small()
              .medium(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaling = theme.scaling;
    return TabContainer(
      selected: index,
      onSelect: onChanged,
      builder: (context, children) {
        return Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? theme.colorScheme.muted,
            borderRadius: BorderRadius.circular(theme.radiusLg),
          ),
          padding: const EdgeInsets.all(4) * scaling,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ).muted(),
          ),
        );
      },
      childBuilder: _childBuilder,
      children: children,
    );
  }
}

mixin TabChild on Widget {
  bool get indexed;
}

mixin KeyedTabChild<T> on TabChild {
  T get tabKey;
}

class TabChildWidget extends StatelessWidget with TabChild {
  final Widget child;
  @override
  final bool indexed;

  const TabChildWidget({
    super.key,
    required this.child,
    this.indexed = false,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class KeyedTabChildWidget<T> extends TabChildWidget with KeyedTabChild<T> {
  KeyedTabChildWidget({
    required T key,
    required super.child,
    super.indexed,
  }) : super(key: ValueKey(key));

  @override
  ValueKey<T> get key => super.key as ValueKey<T>;

  @override
  T get tabKey => key.value;
}

class TabItem extends StatelessWidget with TabChild {
  final Widget child;
  final int? index;

  const TabItem({
    super.key,
    required this.child,
    this.index
  });

  @override
  bool get indexed => true;

  @override
  Widget build(BuildContext context) {
    TabContainerData data = TabContainerData.of(context);
    if(index != null) {
      data.index = index!;
    }
    return data.childBuilder(context, data, child);
  }
}

class KeyedTabItem<T> extends TabItem with KeyedTabChild<T> {
  KeyedTabItem({
    required T key,
    required super.child,
  }) : super(key: ValueKey(key));

  @override
  ValueKey<T> get key => super.key as ValueKey<T>;

  @override
  T get tabKey => key.value;
}

typedef TabBuilder = Widget Function(
    BuildContext context, List<Widget> children);
typedef TabChildBuilder = Widget Function(
    BuildContext context, TabContainerData data, Widget child);

class TabContainer extends StatelessWidget {
  final int selected;
  final ValueChanged<int>? onSelect;
  final List<TabChild> children;
  final TabBuilder builder;
  final TabChildBuilder childBuilder;

  const TabContainer({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.children,
    required this.builder,
    required this.childBuilder,
  });

  @override
  Widget build(BuildContext context) {
    List<Widget> wrappedChildren = [];
    int index = 0;
    for (TabChild child in children) {
      if (child.indexed) {
        wrappedChildren.add(
          Data.inherit(
            key: ValueKey(child),
            data: TabContainerData(
              index: index,
              selected: selected,
              onSelect: onSelect,
              childBuilder: childBuilder,
            ),
            child: child,
          ),
        );
        index++;
      } else {
        wrappedChildren.add(
          child,
        );
      }
    }
    return builder(
      context,
      wrappedChildren,
    );
  }
}
