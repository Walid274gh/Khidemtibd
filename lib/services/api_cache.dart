// lib/services/api_cache.dart
//
// STEP 5 MIGRATION: renamed from repositories/firestore_cache.dart.
// Identical implementation — LRU TTL cache backed by LinkedHashMap.
// O(1) eviction via insertion-order LinkedHashMap.

import 'dart:collection' show LinkedHashMap;
import 'package:flutter/foundation.dart';

class _CachedItem<T> {
  final T        item;
  final DateTime cachedAt;

  _CachedItem(this.item) : cachedAt = DateTime.now();

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}

class ApiCache<T> {
  final Duration ttl;
  final int      maxSize;
  final String   _tag;

  final LinkedHashMap<String, _CachedItem<T>> _store =
      LinkedHashMap<String, _CachedItem<T>>();

  ApiCache({
    required this.ttl,
    required this.maxSize,
    required String tag,
  }) : _tag = tag;

  T? get(String key) {
    final item = _store[key];
    if (item == null) return null;
    if (item.isExpired(ttl)) {
      _store.remove(key);
      return null;
    }
    return item.item;
  }

  void set(String key, T value) {
    _store.remove(key);
    if (_store.length >= maxSize) _evictOldest();
    _store[key] = _CachedItem(value);
  }

  void update(String key, T Function(T existing) updater) {
    final existing = _store[key];
    if (existing != null) {
      _store[key] = _CachedItem(updater(existing.item));
    }
  }

  void cleanExpired() {
    _store.removeWhere((_, v) => v.isExpired(ttl));
    if (_store.length > maxSize) _store.clear();
    if (kDebugMode) debugPrint('$_tag Cache cleaned — ${_store.length} entries remaining');
  }

  void clear() => _store.clear();

  int get length => _store.length;

  void _evictOldest() {
    if (_store.isEmpty) return;
    _store.remove(_store.keys.first);
  }
}
