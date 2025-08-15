// lib/utils/api_cache.dart
class ApiCache {
  ApiCache._();
  static final ApiCache I = ApiCache._();

  Duration ttl = const Duration(minutes: 15);

  final Map<String, _Entry> _mem = {};

  Future<List<Map<String, dynamic>>> getOrFetch(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    final now = DateTime.now();
    final hit = _mem[key];
    if (hit != null && now.isBefore(hit.expires)) {
      return hit.data;
    }
    final data = await fetch();
    _mem[key] = _Entry(data, now.add(ttl));
    return data;
  }

  /// Optional: wipe a group of keys (e.g., when filters change drastically)
  void invalidatePrefix(String prefix) {
    _mem.removeWhere((k, _) => k.startsWith(prefix));
  }

  /// Optional: clear everything (e.g. on sign-out)
  void clear() => _mem.clear();
}

class _Entry {
  _Entry(this.data, this.expires);
  final List<Map<String, dynamic>> data;
  final DateTime expires;
}
