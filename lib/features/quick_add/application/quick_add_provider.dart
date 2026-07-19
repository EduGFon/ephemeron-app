import 'package:flutter_riverpod/flutter_riverpod.dart';

enum QuickAddState {
  closed,
  expanded,
}

class QuickAddData {
  final QuickAddState state;
  final Object? entity;

  const QuickAddData({
    this.state = QuickAddState.closed,
    this.entity,
  });
}

class QuickAddNotifier extends Notifier<QuickAddData> {
  @override
  QuickAddData build() => const QuickAddData();

  void expand([Object? entity]) {
    state = QuickAddData(state: QuickAddState.expanded, entity: entity);
  }

  void close() {
    state = const QuickAddData(state: QuickAddState.closed, entity: null);
  }
}

final quickAddProvider = NotifierProvider<QuickAddNotifier, QuickAddData>(() {
  return QuickAddNotifier();
});
