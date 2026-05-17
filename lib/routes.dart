// lib/routes.dart
import 'package:flutter/material.dart';
// import 'home_page.dart';
// import 'home/history_page.dart';
import 'home/mode_selection.dart';
import 'analysisfood.dart';
import 'auth.dart';
import 'admin.dart';
import 'settings.dart';
import 'pages/family_settings_page.dart';

final Map<String, WidgetBuilder> appRoutes = {
  // '/': (context) => const NutritionHomePage(), // 主畫面
  '/': (context) => const ModeSelection(), // 模式選擇頁
  '/auth': (context) => const AuthPage(), // 登入/註冊頁
  '/settings': (context) => const SettingsPage(), // 設定頁
  '/admin': (context) => const AdminPage(), // 管理頁
  '/analysis': (context) => const AnalysisPage(), // 分析頁
  '/family_settings': (context) => const FamilySettingsPage(),
};
