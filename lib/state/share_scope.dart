import 'package:flutter/widgets.dart';

import 'share_controller.dart';

/// Exposes the single [ShareController] to the widget tree.
class ShareScope extends InheritedNotifier<ShareController> {
  const ShareScope({
    super.key,
    required ShareController controller,
    required super.child,
  }) : super(notifier: controller);

  static ShareController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShareScope>();
    assert(scope != null, 'ShareScope not found in the widget tree');
    return scope!.notifier!;
  }
}
