import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'nav.dart';
import 'prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 读一次本地设置（制作人 / 上次选的型号 / 上次的打印参数）
  await AppPrefs.load();
  runApp(const ExpiryApp());
}

/// 效期管理系统。
///
/// 一级页面 = [HomeShell]（模板 / 打印机两节 + 底部玻璃栏），
/// 具体的模板输入页、预览页都是它的二级 / 三级页面。
class ExpiryApp extends StatelessWidget {
  const ExpiryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00695C);
    return MaterialApp(
      title: '效期管理程序',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [glassRouteObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF7F9F8),
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
