// lib/utils/composite_listenable.dart

import 'package:flutter/foundation.dart';

class CompositeListenable extends ChangeNotifier {
  final List<Listenable> _listenables;

  CompositeListenable(this._listenables) {
    for (final l in _listenables) {
      l.addListener(notifyListeners);
    }
  }

  @override
  void dispose() {
    for (final l in _listenables) {
      l.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
