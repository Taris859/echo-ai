import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _accentKey = 'echo_accent_theme';

  // Available Accent Color Schemes (Neon + Soft / Pastel Options)
  static final Map<String, Map<String, dynamic>> accentThemes = {
    'Neon Lime': {
      'primary': const Color(0xFFCCFF00),
      'secondary': const Color(0xFF99CC00),
      'dark': const Color(0xFF16161A),
      'isDarkText': true, // Black text on accent buttons
    },
    'Soft Sage': {
      'primary': const Color(0xFFA8C3A0),
      'secondary': const Color(0xFF8BAA82),
      'dark': const Color(0xFF161B16),
      'isDarkText': true,
    },
    'Soft Lavender': {
      'primary': const Color(0xFFD4C1EC),
      'secondary': const Color(0xFFB89FE1),
      'dark': const Color(0xFF1A1622),
      'isDarkText': true,
    },
    'Soft Peach': {
      'primary': const Color(0xFFF7C59F),
      'secondary': const Color(0xFFEEA876),
      'dark': const Color(0xFF221A16),
      'isDarkText': true,
    },
    'Soft Rose': {
      'primary': const Color(0xFFF2B5D4),
      'secondary': const Color(0xFFE291BE),
      'dark': const Color(0xFF22161D),
      'isDarkText': true,
    },
    'Soft Sky Blue': {
      'primary': const Color(0xFFA0C4FF),
      'secondary': const Color(0xFF7CB0FF),
      'dark': const Color(0xFF141924),
      'isDarkText': true,
    },
    'Soft Yellow': {
      'primary': const Color(0xFFFFFACD),
      'secondary': const Color(0xFFEEB600),
      'dark': const Color(0xFF1A1A14),
      'isDarkText': true,
    },
    'Soft Orange': {
      'primary': const Color(0xFFF7B79D),
      'secondary': const Color(0xFFD99D7D),
      'dark': const Color(0xFF1A1614),
      'isDarkText': true,
    },
    'Soft Green': {
      'primary': const Color(0xFFD4FFB8),
      'secondary': const Color(0xFFA8D97D),
      'dark': const Color(0xFF161A14),
      'isDarkText': true,
    },
    'Soft Purple': {
      'primary': const Color(0xFFE0C3FF),
      'secondary': const Color(0xFFB87DFF),
      'dark': const Color(0xFF1A141A),
      'isDarkText': true,
    },
  };

  String _currentThemeName = 'Neon Lime';

  String get currentThemeName => _currentThemeName;
  Color get primaryColor => accentThemes[_currentThemeName]?['primary'] ?? const Color(0xFFCCFF00);
  Color get secondaryColor => accentThemes[_currentThemeName]?['secondary'] ?? const Color(0xFF99CC00);
  Color get darkContainerColor => accentThemes[_currentThemeName]?['dark'] ?? const Color(0xFF16161A);
  bool get isDarkText => accentThemes[_currentThemeName]?['isDarkText'] ?? true;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_accentKey);
    if (savedTheme != null && accentThemes.containsKey(savedTheme)) {
      _currentThemeName = savedTheme;
      notifyListeners();
    }
  }

  Future<void> setTheme(String themeName) async {
    if (accentThemes.containsKey(themeName)) {
      _currentThemeName = themeName;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accentKey, themeName);
    }
  }
}
