import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Значения по умолчанию
  static const String _defaultBaseUrl = 'https://abdalbuntu.swallow-lydian.ts.net';
  static const String _defaultSocketUrl = 'https://abdalbuntu.swallow-lydian.ts.net';

  static const String _prefBaseUrl = 'custom_base_url';
  static const String _prefSocketUrl = 'custom_socket_url';

  // Текущие значения (инициализируются из SharedPreferences или default)
  static String _baseUrl = _defaultBaseUrl;
  static String _socketUrl = _defaultSocketUrl;

  static String get baseUrl => _baseUrl;
  static String get socketUrl => _socketUrl;

  /// Загрузить сохранённые URL из SharedPreferences.
  /// Вызывать в main() перед runApp().
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_prefBaseUrl) ?? _defaultBaseUrl;
    _socketUrl = prefs.getString(_prefSocketUrl) ?? _defaultSocketUrl;
  }

  /// Сохранить пользовательский сервер и обновить текущие значения.
  /// baseUrl и socketUrl обычно одинаковые; если socket отличается — передать отдельно.
  static Future<void> setCustomServer(String url) async {
    // Нормализуем: убираем trailing slash
    final normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _baseUrl = normalized;
    _socketUrl = normalized;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBaseUrl, normalized);
    await prefs.setString(_prefSocketUrl, normalized);
  }

  /// Сбросить на значения по умолчанию
  static Future<void> resetToDefault() async {
    _baseUrl = _defaultBaseUrl;
    _socketUrl = _defaultSocketUrl;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefBaseUrl);
    await prefs.remove(_prefSocketUrl);
  }

  /// Возвращает true, если используется кастомный сервер
  static bool get isCustom => _baseUrl != _defaultBaseUrl;
}
