import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Remembers light/dark mode, same as in My Apps.
// The choice is saved on the phone, so it survives closing the app.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'isDark';
  bool isDark = false;

  // Read the saved choice when the app starts
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDark = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  // Flip between light and dark, and save it
  Future<void> toggle() async {
    isDark = !isDark;
    notifyListeners(); // redraw the app straight away
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark);
  }
}
