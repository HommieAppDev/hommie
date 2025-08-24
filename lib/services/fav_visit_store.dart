import 'package:shared_preferences/shared_preferences.dart';

class FavVisitStore {
  static const _favKey = 'fav_ids';
  static const _visitKey = 'visited_ids';

  static Future<Set<String>> _get(String key) async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(key) ?? const <String>[]).toSet();
    }

  static Future<void> _set(String key, Set<String> ids) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(key, ids.toList());
  }

  // ----- Favorite -----
  static Future<bool> isFavorite(String id) async => (await _get(_favKey)).contains(id);
  static Future<void> toggleFavorite(String id) async {
    final s = await _get(_favKey);
    s.contains(id) ? s.remove(id) : s.add(id);
    await _set(_favKey, s);
  }

  // ----- Visited -----
  static Future<bool> isVisited(String id) async => (await _get(_visitKey)).contains(id);
  static Future<void> toggleVisited(String id) async {
    final s = await _get(_visitKey);
    s.contains(id) ? s.remove(id) : s.add(id);
    await _set(_visitKey, s);
  }
}
