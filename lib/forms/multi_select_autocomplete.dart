import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

typedef AsyncSearch = Future<List<String>> Function(String query);

class MultiSelectController extends ValueNotifier<List<String>> {
  MultiSelectController({List<String> initialValue = const []}) : super(initialValue);

  FutureOr<bool> add(String item) async {
    final canAdd = await canAddItem(item);

    if (canAdd) {
      value = [...value, item];
      return true;
    }

    return false;
  }

  FutureOr<bool> canAddItem(String item) => true;

  void remove(String item) {
    value = value.where((e) => e != item).toList();
  }

  void removeLast() {
    if (value.isNotEmpty) {
      value = value.sublist(0, value.length - 1);
    }
  }

  void clear() {
    value = [];
  }
}

class MultiSelectAutocomplete extends StatefulWidget {
  const MultiSelectAutocomplete({
    super.key,
    required this.search,
    this.onChanged,
    this.style,
    this.constraints,
    this.autofocus,
    this.focusNode,
    this.controller,
    this.textController,
    this.popoverController,
    this.placeholder,
    this.placeholderStyle,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.minimumSearchLength = 2,
    this.initialValue,
  });

  final AsyncSearch search;
  final ValueChanged<List<String>>? onChanged;
  final TextStyle? style;
  final BoxConstraints? constraints;
  final bool? autofocus;
  final FocusNode? focusNode;
  final MultiSelectController? controller;
  final TextEditingController? textController;
  final ShadPopoverController? popoverController;
  final Widget? placeholder;
  final TextStyle? placeholderStyle;
  final List<String>? initialValue;
  final Duration debounceDuration;
  final int minimumSearchLength;

  @override
  State createState() => _MultiSelectAutocompleteState();
}

class _MultiSelectAutocompleteState extends State<MultiSelectAutocomplete> {
  final editableTextKey = GlobalKey<EditableTextState>();
  final tapRegionGroupId = Object();
  final dropdownMenuItems = ValueNotifier<List<String>>([]);
  final selectedOption = ValueNotifier<int>(0);

  late final popoverController = widget.popoverController ?? ShadPopoverController();
  late final controller = widget.controller ?? MultiSelectController();
  late final textController = widget.textController ?? TextEditingController();
  late final focusNode = widget.focusNode ?? FocusNode();

  Timer? debounceTimer;
  TextSelection? lastSelection;
  int seq = 0;

  static const Map<ShortcutActivator, Intent> appleShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowUp, meta: true): MoveToFirstIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown, meta: true): MoveToLastIntent(),
  };

  static const Map<ShortcutActivator, Intent> nonAppleShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowUp, control: true): MoveToFirstIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown, control: true): MoveToLastIntent(),
  };

  static const Map<ShortcutActivator, Intent> commonShortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowDown): MoveDownIntent(),
    SingleActivator(LogicalKeyboardKey.arrowUp): MoveUpIntent(),
    SingleActivator(LogicalKeyboardKey.enter): SubmitTextIntent(),
    SingleActivator(LogicalKeyboardKey.backspace): DeleteLastItemIntent(),
    SingleActivator(LogicalKeyboardKey.escape): ClosePopoverIntent(),
  };

  static Map<ShortcutActivator, Intent> get shortcuts => {
    ...commonShortcuts,
    ...switch (defaultTargetPlatform) {
      TargetPlatform.iOS => appleShortcuts,
      TargetPlatform.macOS => appleShortcuts,
      TargetPlatform.android => nonAppleShortcuts,
      TargetPlatform.linux => nonAppleShortcuts,
      TargetPlatform.windows => nonAppleShortcuts,
      TargetPlatform.fuchsia => nonAppleShortcuts,
    },
  };

  late final actions = <Type, Action<Intent>>{
    ClosePopoverIntent: ClosePopoverAction(popoverController),
    DeleteLastItemIntent: DeleteLastItemAction(() => textController.text.isEmpty && controller.value.isNotEmpty, removeLastIfInputEmpty),
    SubmitTextIntent: SubmitTextAction(() {
      if (popoverController.isOpen && dropdownMenuItems.value.isNotEmpty) {
        final selectedIndex = selectedOption.value;
        final items = dropdownMenuItems.value;

        if (selectedIndex < 0 || selectedIndex >= items.length) {
          add(textController.text);
        } else {
          add(items[selectedIndex]);
        }
      } else {
        add(textController.text);
      }

      popoverController.hide();
    }),
    MoveDownIntent: MoveDownAction(selectedOption, dropdownMenuItems),
    MoveUpIntent: MoveUpAction(selectedOption, dropdownMenuItems),
    MoveToFirstIntent: MoveToFirstAction(selectedOption, dropdownMenuItems),
    MoveToLastIntent: MoveToLastAction(selectedOption, dropdownMenuItems),
  };

  bool containsSelected(String value) {
    final lcValue = value.toLowerCase();
    final selected = controller.value;

    return selected.any((e) => e.toLowerCase() == lcValue);
  }

  Future<void> add(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final added = await controller.add(trimmed);
    if (!added || !mounted) {
      return;
    }

    textController.clear();
    focusNode.requestFocus();
  }

  void remove(String value) {
    controller.remove(value);
    focusNode.requestFocus();
  }

  void removeLastIfInputEmpty() {
    controller.removeLast();
    focusNode.requestFocus();
  }

  void refocusPreservingSelection() {
    focusNode.requestFocus();

    final selection = lastSelection;
    if (selection != null && selection.start >= 0 && selection.end >= 0 && selection.end <= textController.text.length) {
      textController.selection = selection;
    } else {
      textController.selection = TextSelection.collapsed(offset: textController.text.length);
    }
  }

  void scheduleRefocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !popoverController.isOpen) {
        return;
      }

      refocusPreservingSelection();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !popoverController.isOpen) {
          return;
        }

        refocusPreservingSelection();
      });
    });

    final theme = ShadTheme.of(context);
    final duration = theme.popoverTheme.reverseDuration ?? const Duration(milliseconds: 200);

    Future.delayed(duration, () {
      if (!mounted || !popoverController.isOpen) {
        return;
      }

      refocusPreservingSelection();
    });
  }

  void onTextChanged() {
    lastSelection = textController.selection;
    debounceTimer?.cancel();

    final query = textController.text.trim();
    if (query.length < widget.minimumSearchLength) {
      popoverController.hide();
      debounceTimer = null;
      return;
    }

    debounceTimer = Timer(widget.debounceDuration, () {
      invokeSearch(query);
    });
  }

  Future<void> invokeSearch(String query) async {
    final mySeq = ++seq;
    final results = await widget.search(query);

    if (!mounted || mySeq != seq) {
      return;
    }

    final filtered = results.where((e) => !containsSelected(e)).toList();
    if (filtered.isEmpty) {
      if (popoverController.isOpen) {
        popoverController.hide();
      }
      return;
    }

    dropdownMenuItems.value = filtered;

    if (!popoverController.isOpen) {
      popoverController.show();
      scheduleRefocus();
    }
  }

  void onMenuClose() {
    if (!popoverController.isOpen) {
      dropdownMenuItems.value = [];
      selectedOption.value = 0;
    }
  }

  void invokeOnChanged() {
    widget.onChanged?.call(List.unmodifiable(controller.value));
  }

  @override
  void initState() {
    super.initState();

    textController.addListener(onTextChanged);
    popoverController.addListener(onMenuClose);
    dropdownMenuItems.addListener(() {
      final maxIndex = max(0, dropdownMenuItems.value.length - 1);
      selectedOption.value = min(selectedOption.value, maxIndex);
    });

    if (widget.initialValue != null) {
      controller.value = widget.initialValue!;
    }

    controller.addListener(invokeOnChanged);
  }

  @override
  void dispose() {
    debounceTimer?.cancel();
    textController.removeListener(onTextChanged);
    popoverController.removeListener(onMenuClose);
    controller.removeListener(invokeOnChanged);

    if (widget.popoverController == null) {
      popoverController.dispose();
    }
    if (widget.textController == null) {
      textController.dispose();
    }
    if (widget.focusNode == null) {
      focusNode.dispose();
    }
    if (widget.controller == null) {
      controller.dispose();
    }

    dropdownMenuItems.dispose();
    selectedOption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    final hoveredBackgroundColor = theme.optionTheme.hoveredBackgroundColor;

    final effectiveTextStyle = theme.textTheme.muted
        .copyWith(color: theme.colorScheme.foreground)
        .merge(theme.inputTheme.style)
        .merge(widget.style);
    final textScaler = MediaQuery.textScalerOf(context);
    final effectivePlaceholderStyle = theme.textTheme.muted
        .merge(theme.inputTheme.placeholderStyle)
        .merge(widget.placeholderStyle)
        .fallback(color: theme.colorScheme.mutedForeground);

    final maxFontSize = max(
      (effectivePlaceholderStyle.fontSize ?? 0) * (effectivePlaceholderStyle.height ?? 0),
      (effectiveTextStyle.fontSize ?? 0) * (effectiveTextStyle.height ?? 0),
    );
    final maxFontSizeScaled = textScaler.scale(maxFontSize);
    final effectiveConstraints = widget.constraints ?? theme.inputTheme.constraints ?? BoxConstraints(minHeight: maxFontSizeScaled);
    final cursorColor = theme.inputTheme.cursorColor ?? cs.primary;

    return ConstrainedBox(
      constraints: effectiveConstraints,
      child: ShadGestureDetector(
        cursor: SystemMouseCursors.text,
        onTap: focusNode.requestFocus,
        child: ShadPopover(
          anchor: const ShadAnchor(childAlignment: Alignment.topLeft, overlayAlignment: Alignment.bottomLeft, offset: Offset(0, 10)),
          controller: popoverController,
          groupId: tapRegionGroupId,
          areaGroupId: tapRegionGroupId,
          popover: (context) {
            return ValueListenableBuilder<List<String>>(
              valueListenable: dropdownMenuItems,
              builder: (context, items, child) {
                final maxHeight = items.length > 10 ? 400.0 : items.length * 40.0;

                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 300),
                  child: TextFieldTapRegion(
                    groupId: tapRegionGroupId,
                    child: Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: ValueListenableBuilder<int>(
                        valueListenable: selectedOption,
                        builder: (context, selected, child) {
                          return ListView.builder(
                            padding: const EdgeInsets.all(0),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final option = items[index];
                              final highlight = index == selected;

                              return ShadButton.ghost(
                                height: 40,
                                mainAxisAlignment: MainAxisAlignment.start,
                                backgroundColor: highlight ? hoveredBackgroundColor : null,
                                onPressed: () {
                                  add(option);
                                  popoverController.hide();
                                },
                                child: Text(option, textAlign: TextAlign.left, overflow: TextOverflow.ellipsis),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
          child: ListenableBuilder(
            listenable: focusNode,
            builder: (context, child) => ShadDecorator(
              decoration: theme.inputTheme.decoration,
              focused: focusNode.hasFocus,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: controller,
                  builder: (context, selected, child) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final maxLineWidth = constraints.maxWidth;

                        return Stack(
                          children: [
                            if (selected.isEmpty && widget.placeholder != null)
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: textController,
                                builder: (context, value, child) => Positioned.fill(
                                  child: value.text.isEmpty
                                      ? IgnorePointer(
                                          child: DefaultTextStyle(style: effectivePlaceholderStyle, child: widget.placeholder!),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final item in selected)
                                    ShadBadge(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        spacing: 4,
                                        children: [
                                          Text(item),
                                          ShadGestureDetector(
                                            cursor: SystemMouseCursors.click,
                                            onTap: () => remove(item),
                                            child: Icon(LucideIcons.x, size: 16, color: cs.background),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(minWidth: 24, maxWidth: maxLineWidth),
                                    child: IntrinsicWidth(
                                      child: TextFieldTapRegion(
                                        groupId: tapRegionGroupId,
                                        child: Shortcuts(
                                          shortcuts: shortcuts,
                                          child: Actions(
                                            actions: actions,
                                            child: EditableText(
                                              key: editableTextKey,
                                              autofocus: widget.autofocus ?? false,
                                              backgroundCursorColor: const Color(0xFF9E9E9E),
                                              cursorColor: cursorColor,
                                              style: effectiveTextStyle,
                                              controller: textController,
                                              focusNode: focusNode,
                                              groupId: tapRegionGroupId,
                                              selectionColor: focusNode.hasFocus ? theme.colorScheme.selection : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ClosePopoverIntent extends Intent {
  const ClosePopoverIntent();
}

class DeleteLastItemIntent extends Intent {
  const DeleteLastItemIntent();
}

class SubmitTextIntent extends Intent {
  const SubmitTextIntent();
}

class MoveDownIntent extends Intent {
  const MoveDownIntent();
}

class MoveUpIntent extends Intent {
  const MoveUpIntent();
}

class MoveToFirstIntent extends Intent {
  const MoveToFirstIntent();
}

class MoveToLastIntent extends Intent {
  const MoveToLastIntent();
}

class SubmitTextAction extends Action<SubmitTextIntent> {
  SubmitTextAction(this.onSubmit);

  final VoidCallback onSubmit;

  @override
  Object? invoke(covariant SubmitTextIntent intent) {
    onSubmit();
    return null;
  }
}

class ClosePopoverAction extends Action<ClosePopoverIntent> {
  ClosePopoverAction(this.popoverController);

  final ShadPopoverController popoverController;

  @override
  Object? invoke(covariant ClosePopoverIntent intent) {
    if (popoverController.isOpen) {
      popoverController.hide();
    }

    return null;
  }
}

class DeleteLastItemAction extends Action<DeleteLastItemIntent> {
  DeleteLastItemAction(this.shouldDelete, this.onDelete);

  final bool Function() shouldDelete;
  final VoidCallback onDelete;

  @override
  Object? invoke(covariant DeleteLastItemIntent intent) {
    if (shouldDelete()) {
      onDelete();
      return null;
    }

    return Actions.invoke(primaryFocus!.context!, const DeleteCharacterIntent(forward: false));
  }
}

class MoveDownAction extends Action<MoveDownIntent> {
  MoveDownAction(this.selectedOption, this.dropdownMenuItems);

  final ValueNotifier<int> selectedOption;
  final ValueNotifier<List<String>> dropdownMenuItems;

  @override
  Object? invoke(covariant MoveDownIntent intent) {
    selectedOption.value = min(selectedOption.value + 1, max(0, dropdownMenuItems.value.length - 1));
    return null;
  }
}

class MoveUpAction extends Action<MoveUpIntent> {
  MoveUpAction(this.selectedOption, this.dropdownMenuItems);

  final ValueNotifier<int> selectedOption;
  final ValueNotifier<List<String>> dropdownMenuItems;

  @override
  Object? invoke(covariant MoveUpIntent intent) {
    selectedOption.value = max(0, selectedOption.value - 1);
    return null;
  }
}

class MoveToFirstAction extends Action<MoveToFirstIntent> {
  MoveToFirstAction(this.selectedOption, this.dropdownMenuItems);

  final ValueNotifier<int> selectedOption;
  final ValueNotifier<List<String>> dropdownMenuItems;

  @override
  Object? invoke(covariant MoveToFirstIntent intent) {
    if (dropdownMenuItems.value.isNotEmpty) {
      selectedOption.value = 0;
    }
    return null;
  }
}

class MoveToLastAction extends Action<MoveToLastIntent> {
  MoveToLastAction(this.selectedOption, this.dropdownMenuItems);

  final ValueNotifier<int> selectedOption;
  final ValueNotifier<List<String>> dropdownMenuItems;

  @override
  Object? invoke(covariant MoveToLastIntent intent) {
    if (dropdownMenuItems.value.isNotEmpty) {
      selectedOption.value = dropdownMenuItems.value.length - 1;
    }
    return null;
  }
}
