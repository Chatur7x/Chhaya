import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appearanceProvider = StateNotifierProvider<AppearanceController, ThemeMode>(
  (ref) => AppearanceController(),
);

class AppearanceController extends StateNotifier<ThemeMode> {
  AppearanceController() : super(ThemeMode.system) { _load(); }
  int _revision = 0;

  Future<void> _load() async {
    final revision = _revision;
    SharedPreferences prefs;
    try { prefs = await SharedPreferences.getInstance(); }
    catch (_) { return; }
    if (!mounted || revision != _revision) return;
    state = switch (prefs.getString('chhaya_appearance')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> select(ThemeMode mode) async {
    _revision++;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chhaya_appearance', mode.name);
  }
}
